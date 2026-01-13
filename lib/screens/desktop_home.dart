import 'dart:io';
import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';
import '../widgets/qr_code_display.dart';
import '../services/server_service.dart';
import '../services/http_client_service.dart';

class DesktopHome extends StatefulWidget {
  const DesktopHome({super.key});

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHome> {
  bool isServerRunning = false;
  bool isLoading = false;

  final ServerService _serverService = ServerService();
  String? connectionUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('UniShare – Desktop')),
      body: Center(
        child: isServerRunning
            ? _buildMainLayout()
            : isLoading
            ? const CircularProgressIndicator()
            : _buildStartView(),
      ),
    );
  }

  /// Start screen
  Widget _buildStartView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.computer, size: 64),
        const SizedBox(height: 16),
        const Text(
          'Desktop Mode',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _startServer,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start Server'),
        ),
      ],
    );
  }

  /// Main layout after server starts
  Widget _buildMainLayout() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          // LEFT SIDE – QR + Stop
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Scan QR on Mobile',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                QrCodeDisplay(data: connectionUrl!),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _stopServer,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop Server'),
                ),
              ],
            ),
          ),

          const VerticalDivider(width: 40),

          // RIGHT SIDE – Actions
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _pickAndShareFile,
                  icon: const Icon(Icons.upload),
                  label: const Text('Send'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(160, 48),
                  ),
                ),

                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _showReceivedFiles,
                  icon: const Icon(Icons.download),
                  label: const Text('Receive'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Start HTTP server
  Future<void> _startServer() async {
    setState(() {
      isLoading = true;
    });

    await _serverService.start();

    setState(() {
      connectionUrl = 'http://${_serverService.ip}:${_serverService.port}';
      isServerRunning = true;
      isLoading = false;
    });
  }

  /// Stop HTTP server
  Future<void> _stopServer() async {
    await _serverService.stop();

    setState(() {
      isServerRunning = false;
      connectionUrl = null;
    });
  }

  Future<void> _pickAndShareFile() async {
    final result = await FilePicker.platform.pickFiles();

    if (result == null || result.files.isEmpty) return;

    final pickedFile = result.files.first;

    if (pickedFile.path == null) return;

    final file = File(pickedFile.path!);

    _serverService.addFile(file);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${pickedFile.name} ready to send')));
  }

  void _showReceivedFiles() {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Incoming Files'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: FutureBuilder<List<String>>(
            future: HttpClientService.getIncomingFiles(connectionUrl!),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return const Center(child: Text('Connection lost'));
              }

              final files = snapshot.data ?? [];

              if (files.isEmpty) {
                return const Center(child: Text('No incoming files'));
              }

              return ListView.builder(
                itemCount: files.length,
                itemBuilder: (context, index) {
                  final fileName = files[index];

                  return ListTile(
                    leading: const Icon(Icons.insert_drive_file),
                    title: Text(fileName),
                    trailing: IconButton(
                      icon: const Icon(Icons.download),
                      onPressed: () async {
                        final dir = _serverService.getReceiveDir();
                        final savePath = '${dir.path}/$fileName';

                        await HttpClientService.downloadIncoming(
                          connectionUrl!,
                          fileName,
                          savePath,
                        );

                        if (!context.mounted) return;

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$fileName saved')),
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

}
