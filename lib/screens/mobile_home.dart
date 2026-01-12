import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';

import '../services/http_client_service.dart';

class MobileHome extends StatefulWidget {
  const MobileHome({super.key});

  @override
  State<MobileHome> createState() => _MobileHomeState();
}

enum ConnectionStateStatus { scanning, connecting, connected, failed }

enum ConnectedView { menu, receive }

class _MobileHomeState extends State<MobileHome> {
  String? serverUrl;
  ConnectionStateStatus status = ConnectionStateStatus.scanning;
  ConnectedView connectedView = ConnectedView.menu;

  bool showScanner = false;

  Timer? _pingTimer;
  Timer? _filePollTimer;

  List<String> _availableFiles = [];

  @override
  void dispose() {
    _pingTimer?.cancel();
    _filePollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('UniShare – Mobile')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (status) {
      case ConnectionStateStatus.scanning:
        return _buildScanner();
      case ConnectionStateStatus.connecting:
        return _buildConnecting();
      case ConnectionStateStatus.connected:
        return _buildConnected();
      case ConnectionStateStatus.failed:
        return _buildFailed();
    }
  }

  // ---------- SCAN ----------
  Widget _buildScanner() {
    if (!showScanner) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.qr_code_scanner, size: 72),
            const SizedBox(height: 20),
            const Text(
              'Connect to Desktop',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                setState(() {
                  showScanner = true;
                });
              },
              child: const Text('Start Scanning'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // Camera
        MobileScanner(
          onDetect: (capture) {
            final code = capture.barcodes.first.rawValue;
            if (code != null) _onQrScanned(code);
          },
        ),

        // Dark overlay
        Container(color: Colors.black.withOpacity(0.6)),

        // Scan box
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(
                color: const Color.fromARGB(255, 78, 175, 255),
                width: 3,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),

        // Instruction text
        Positioned(
          bottom: 120,
          left: 0,
          right: 0,
          child: const Text(
            'Align QR code inside the box',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),

        // Back button
        Positioned(
          top: 40,
          left: 16,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              setState(() {
                showScanner = false;
              });
            },
          ),
        ),
      ],
    );
  }

  void _onQrScanned(String url) {
    setState(() {
      serverUrl = url;
      status = ConnectionStateStatus.connecting;
    });
    _checkConnection();
  }

  // ---------- CONNECTING ----------
  Widget _buildConnecting() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Connecting to desktop...'),
        ],
      ),
    );
  }

  // ---------- CONNECTED ----------
  Widget _buildConnected() {
    return connectedView == ConnectedView.menu
        ? _buildConnectedMenu()
        : _buildReceiveView();
  }

  // ---------- MENU ----------
  Widget _buildConnectedMenu() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton(
            onPressed: _disconnect,
            child: const Text('Close Connection'),
          ),
          const SizedBox(height: 40),

          // SEND (Phone → PC)
          FilledButton(
            onPressed: () async {
              try {
                final result = await FilePicker.platform.pickFiles();
                if (result == null || result.files.first.path == null) return;

                final file = File(result.files.first.path!);

                _pauseHeartbeat();
                await HttpClientService.uploadFile(serverUrl!, file);
                _resumeHeartbeat();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('File sent to PC')),
                );
              } catch (_) {
                _resumeHeartbeat();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to send file')),
                );
              }
            },
            child: const Text('Send'),
          ),

          const SizedBox(height: 16),

          // RECEIVE (PC → Phone)
          FilledButton(
            onPressed: () {
              setState(() {
                connectedView = ConnectedView.receive;
              });
            },
            child: const Text('Receive'),
          ),
        ],
      ),
    );
  }

  // ---------- RECEIVE ----------
  Widget _buildReceiveView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: () {
              setState(() {
                connectedView = ConnectedView.menu;
              });
            },
            child: const Text('Back'),
          ),
        ),
        Expanded(
          child: _availableFiles.isEmpty
              ? const Center(
                  child: Text(
                    'Waiting for desktop files...',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  itemCount: _availableFiles.length,
                  itemBuilder: (context, index) {
                    final fileName = _availableFiles[index];

                    return ListTile(
                      leading: const Icon(Icons.insert_drive_file),
                      title: Text(fileName),
                      trailing: IconButton(
                        icon: const Icon(Icons.download),
                        onPressed: () async {
                          final savePath = await _getDownloadPath(fileName);

                          await HttpClientService.downloadFile(
                            serverUrl!,
                            fileName,
                            savePath,
                          );

                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '$fileName saved to Downloads/UniShare',
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ---------- FAILED ----------
  Widget _buildFailed() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error, color: Colors.red, size: 72),
          const SizedBox(height: 16),
          const Text(
            'Connection Failed',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              setState(() {
                status = ConnectionStateStatus.scanning;
                showScanner = false;
              });
            },
            child: const Text('Scan Again'),
          ),
        ],
      ),
    );
  }

  // ---------- NETWORK ----------
  Future<void> _checkConnection() async {
    try {
      final res = await http
          .get(Uri.parse('$serverUrl/ping'))
          .timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        setState(() {
          status = ConnectionStateStatus.connected;
          connectedView = ConnectedView.menu;
        });

        _startHeartbeat();
        _startFilePolling();
      } else {
        _failConnection();
      }
    } catch (_) {
      _failConnection();
    }
  }

  void _startHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final res = await http
            .get(Uri.parse('$serverUrl/ping'))
            .timeout(const Duration(seconds: 3));
        if (res.statusCode != 200) _failConnection();
      } catch (_) {
        _failConnection();
      }
    });
  }

  void _pauseHeartbeat() {
    _pingTimer?.cancel();
  }

  void _resumeHeartbeat() {
    _startHeartbeat();
  }

  void _startFilePolling() {
    _filePollTimer?.cancel();
    _filePollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final files = await HttpClientService.getFiles(serverUrl!);
        if (!mounted) return;
        setState(() {
          _availableFiles = files;
        });
      } catch (_) {}
    });
  }

  void _failConnection() {
    _pingTimer?.cancel();
    _filePollTimer?.cancel();
    if (!mounted) return;

    setState(() {
      status = ConnectionStateStatus.failed;
      _availableFiles.clear();
      showScanner = false;
    });
  }

  void _disconnect() {
    _pingTimer?.cancel();
    _filePollTimer?.cancel();

    setState(() {
      status = ConnectionStateStatus.scanning;
      serverUrl = null;
      connectedView = ConnectedView.menu;
      _availableFiles.clear();
      showScanner = false;
    });
  }

  // ---------- DOWNLOAD PATH ----------
  Future<String> _getDownloadPath(String fileName) async {
    final dir = Directory('/storage/emulated/0/Download/UniShare');

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return '${dir.path}/$fileName';
  }
}
