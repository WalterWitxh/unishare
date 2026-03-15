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
                Text(
                  'Enter 6-digit PIN on mobile:',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _serverService.sessionPin ?? '---',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _stopServer,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop Server'),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: _refreshIp,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh IP'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _showManualIpDialog,
                      icon: const Icon(Icons.edit),
                      label: const Text('Change IP'),
                    ),
                  ],
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
    _sessionStart = DateTime.now(); // set BEFORE await to avoid race
    await _serverService.start();

    _connSub = _serverService.connectionStream.listen((c) {
      setState(() => isConnected = c);
    });

    _serverService.onFileReceived = (String fileName) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          backgroundColor: Colors.green,
          content: Row(
            children: [
              const Icon(
                Icons.download_done_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$fileName received',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    };

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

  Future<void> _refreshIp() async {
    final newIp = await _serverService.detectLocalIp();
    if (mounted) {
      setState(() {
        _serverService.ip = newIp;
        connectionUrl = 'http://$newIp:${_serverService.port}';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('IP updated to: $newIp')));
    }
  }

  void _showManualIpDialog() {
    final ipController = TextEditingController(text: _serverService.ip);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change IP Address'),
        content: TextField(
          controller: ipController,
          decoration: const InputDecoration(
            hintText: '192.168.1.100',
            labelText: 'IP Address',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newIp = ipController.text.trim();
              if (newIp.isNotEmpty) {
                setState(() {
                  _serverService.ip = newIp;
                  connectionUrl = 'http://$newIp:${_serverService.port}';
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _showSessionReceivedFiles() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final timer = Timer.periodic(const Duration(seconds: 1), (_) {
              if (context.mounted) setDialogState(() {});
            });

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
