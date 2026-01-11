import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../services/http_client_service.dart';



class MobileHome extends StatefulWidget {
  const MobileHome({super.key});

  @override
  State<MobileHome> createState() => _MobileHomeState();
}

enum ConnectionStateStatus {
  scanning,
  connecting,
  connected,
  failed,
}

class _MobileHomeState extends State<MobileHome> {
  String? serverUrl;
  ConnectionStateStatus status = ConnectionStateStatus.scanning;

  Timer? _pingTimer;

  @override
  void dispose() {
    _pingTimer?.cancel();
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
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Scan the QR code shown on Desktop',
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: MobileScanner(
            onDetect: (capture) {
              final code = capture.barcodes.first.rawValue;
              if (code != null) {
                _onQrScanned(code);
              }
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
  return Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Connected',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: _disconnect,
              child: const Text('Disconnect'),
            ),
          ],
        ),
      ),

      const Divider(),

      Expanded(
        child: FutureBuilder<List<String>>(
          future: HttpClientService.getFiles(serverUrl!),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return const Center(child: Text('Connection lost'));
            }

            final files = snapshot.data ?? [];

            if (files.isEmpty) {
              return const Center(child: Text('No files available'));
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
                      final dir = await getApplicationDocumentsDirectory();
                      final savePath = '${dir.path}/$fileName';

                      await HttpClientService.downloadFile(
                        serverUrl!,
                        fileName,
                        savePath,
                      );

                      if (!mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$fileName downloaded')),
                      );
                    },
                  ),
                );
              },
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
              });
            },
            child: const Text('Scan Again'),
          ),
        ],
      ),
    );
  }

  // ---------- NETWORK LOGIC ----------
  Future<void> _checkConnection() async {
    try {
      final uri = Uri.parse('$serverUrl/ping');

      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        setState(() {
          status = ConnectionStateStatus.connected;
        });

        _startHeartbeat();
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
        final response = await http
            .get(Uri.parse('$serverUrl/ping'))
            .timeout(const Duration(seconds: 3));

        if (response.statusCode != 200) {
          _failConnection();
        }
      } catch (_) {
        _failConnection();
      }
    });
  }

  void _failConnection() {
    _pingTimer?.cancel();
    if (!mounted) return;

    setState(() {
      status = ConnectionStateStatus.failed;
    });
  }

  void _disconnect() {
    _pingTimer?.cancel();
    setState(() {
      status = ConnectionStateStatus.scanning;
      serverUrl = null;
    });
  }
}
