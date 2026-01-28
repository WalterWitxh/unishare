import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../widgets/qr_code_display.dart';
import '../services/server_service.dart';

enum ReceiveStatus { receiving, completed }

class DesktopHome extends StatefulWidget {
  const DesktopHome({super.key});

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHome> {
  bool isServerRunning = false;
  bool isLoading = false;
  bool isConnected = false;

  late DateTime _sessionStart;

  final ServerService _serverService = ServerService();
  StreamSubscription<bool>? _connSub;
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

  Widget _buildStartView() => Column(
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

  Widget _buildMainLayout() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isConnected ? 'Connected' : 'Scan QR on Mobile',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
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
          Expanded(
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton(
                    icon: const Icon(Icons.history),
                    onPressed: _showHistoryFiles,
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.icon(
                        onPressed: _pickAndShareFile,
                        icon: const Icon(Icons.upload),
                        label: const Text('Send'),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _showSessionReceivedFiles,
                        icon: const Icon(Icons.download),
                        label: const Text('Receive'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startServer() async {
    setState(() => isLoading = true);
    await _serverService.start();
    _sessionStart = DateTime.now();

    _connSub = _serverService.connectionStream.listen(
      (c) => setState(() {
        isConnected = c;
      }),
    );

    setState(() {
      connectionUrl = 'http://${_serverService.ip}:${_serverService.port}';
      isServerRunning = true;
      isLoading = false;
    });
  }

  Future<void> _stopServer() async {
    await _serverService.stop();
    await _connSub?.cancel();
    setState(() => isServerRunning = false);
  }

  Future<void> _pickAndShareFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.first.path == null) return;
    _serverService.addFile(File(result.files.first.path!));
  }

  void _showSessionReceivedFiles() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Timer? timer;

            void startTimer() {
              timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
                setDialogState(() {});
              });
            }

            startTimer();

            final files = _serverService
                .getReceivedFiles()
                .where((f) => f.lastModifiedSync().isAfter(_sessionStart))
                .toList();

            return AlertDialog(
              title: const Text('Received Files'),
              content: SizedBox(
                width: 420,
                height: 320,
                child: files.isEmpty
                    ? const Center(child: Text('Waiting for files…'))
                    : ListView.builder(
                        itemCount: files.length,
                        itemBuilder: (_, i) {
                          final f = files[i];
                          final name = f.uri.pathSegments.last;
                          final receiving = _serverService.isReceiving(name);

                          return ListTile(
                            leading: Icon(
                              receiving
                                  ? Icons.downloading
                                  : Icons.check_circle,
                              color: receiving ? Colors.blue : Colors.green,
                            ),
                            title: Text(name),
                            subtitle: receiving
                                ? const LinearProgressIndicator()
                                : const Text('Completed'),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    timer?.cancel();
                    Navigator.pop(context);
                  },
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showHistoryFiles() {
    final files = _serverService.getReceivedFiles();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Received Files (History)'),
        content: SizedBox(
          width: 420,
          height: 320,
          child: ListView(
            children: files
                .map((f) => ListTile(title: Text(f.uri.pathSegments.last)))
                .toList(),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }
}
