import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';


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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 72),
          const SizedBox(height: 16),
          const Text(
            'Connected',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(serverUrl ?? ''),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _disconnect,
            child: const Text('Disconnect'),
          ),
        ],
      ),
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
