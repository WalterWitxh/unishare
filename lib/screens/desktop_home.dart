import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../widgets/qr_code_display.dart';
import '../services/server_service.dart';

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

  // ── Per-file download state shown in the UI ──────────────────────
  // Maps filename → 'sending' | 'sent'
  final Map<String, String> _sendFileStatus = {};

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

  // ================= START VIEW =================

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

  // ================= MAIN LAYOUT =================

  Widget _buildMainLayout() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          // ── Left: QR + PIN + controls ──
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isConnected ? Icons.wifi : Icons.wifi_off,
                      size: 16,
                      color: isConnected ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isConnected ? 'Connected' : 'Scan QR on Mobile',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isConnected ? Colors.green : null,
                      ),
                    ),
                  ],
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
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
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

          // ── Right: Send / Receive + file status list ──
          Expanded(
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton(
                    icon: const Icon(Icons.history),
                    tooltip: 'Received files history',
                    onPressed: _showHistoryFiles,
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _pickAndShareFile,
                      icon: const Icon(Icons.upload),
                      label: const Text('Send to Mobile'),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _showSessionReceivedFiles,
                      icon: const Icon(Icons.download),
                      label: const Text('View Received'),
                    ),

                    // ── Shared files status list ──────────────────────
                    if (_sendFileStatus.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Divider(),
                      const Text(
                        'Shared files',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._sendFileStatus.entries.map((e) {
                        final isSending = e.value == 'sending';
                        final isSent = e.value == 'sent';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              isSending
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      isSent
                                          ? Icons.check_circle
                                          : Icons.hourglass_empty,
                                      size: 14,
                                      color: isSent
                                          ? Colors.green
                                          : Colors.orange,
                                    ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  e.key,
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isSending ? 'Sending…' : 'Sent ✓',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isSending ? Colors.blue : Colors.green,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================= SERVER LIFECYCLE =================

  Future<void> _startServer() async {
    setState(() => isLoading = true);
    _sessionStart = DateTime.now();
    await _serverService.start();

    // Connection state
    _connSub = _serverService.connectionStream.listen((c) {
      setState(() => isConnected = c);
    });

    // ── File staged for sending (addFile called) ─────────────────────
    _serverService.onFileShared = (fileName) {
      if (!mounted) return;
      setState(() => _sendFileStatus[fileName] = 'ready');
      _showDesktopSnackbar(
        '$fileName ready — waiting for mobile to download',
        icon: Icons.upload_file,
        color: Colors.blue,
      );
    };

    // ── Mobile started downloading ───────────────────────────────────
    _serverService.onFileDownloadStarted = (fileName) {
      if (!mounted) return;
      setState(() => _sendFileStatus[fileName] = 'sending');
      _showDesktopSnackbar(
        'Sending $fileName to mobile…',
        icon: Icons.swap_horiz,
        color: Colors.orange,
      );
    };

    // ── Mobile finished downloading ──────────────────────────────────
    _serverService.onFileDownloadCompleted = (fileName) {
      if (!mounted) return;
      setState(() => _sendFileStatus[fileName] = 'sent');
      _showDesktopSnackbar(
        '$fileName delivered to mobile ✓',
        icon: Icons.check_circle_rounded,
        color: Colors.green,
      );
    };

    // ── Mobile finished uploading (Phone → PC) ───────────────────────
    _serverService.onFileReceived = (fileName) {
      if (!mounted) return;
      _showDesktopSnackbar(
        '$fileName received from mobile',
        icon: Icons.download_done_rounded,
        color: Colors.green,
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
    setState(() {
      isServerRunning = false;
      _sendFileStatus.clear();
    });
  }

  // ================= SEND FILE =================

  Future<void> _pickAndShareFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.first.path == null) return;
    final file = File(result.files.first.path!);
    // addFile triggers onFileShared callback which shows the snackbar
    _serverService.addFile(file);
  }

  // ================= HELPER: DESKTOP SNACKBAR =================

  void _showDesktopSnackbar(
    String message, {
    required IconData icon,
    required Color color,
    Duration duration = const Duration(seconds: 4),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: duration,
        behavior: SnackBarBehavior.floating,
        backgroundColor: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
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
  }

  // ================= IP =================

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

  // ================= RECEIVED FILES DIALOGS =================

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
                    timer.cancel();
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
          child: files.isEmpty
              ? const Center(child: Text('No files received yet'))
              : ListView(
                  children: files
                      .map(
                        (f) => ListTile(
                          leading: const Icon(Icons.insert_drive_file),
                          title: Text(f.uri.pathSegments.last),
                        ),
                      )
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }
}
