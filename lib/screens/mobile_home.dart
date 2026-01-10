import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class MobileHome extends StatefulWidget {
  const MobileHome({super.key});

  @override
  State<MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends State<MobileHome> {
  String? scannedUrl;
  bool isScanning = true;
  bool isConnecting = false;
  bool isConnected = false;
  String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('UniShare – Mobile')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (isScanning) {
      return _buildScanner();
    }

    if (isConnecting) {
      return _buildConnectingView();
    }

    if (isConnected) {
      return _buildConnectedView();
    }

    return _buildErrorView();
  }

  /// QR Scanner view
  Widget _buildScanner() {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Scan the QR code shown on the Desktop app',
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: MobileScanner(
            onDetect: (capture) {
              final barcode = capture.barcodes.first;
              final String? code = barcode.rawValue;

              if (code != null) {
                setState(() {
                  scannedUrl = code;
                  isScanning = false;
                  isConnecting = true;
                });

                _connectToServer(code);
              }
            },
          ),
        ),
      ],
    );
  }

  /// Connecting UI
  Widget _buildConnectingView() {
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

  /// Connected UI
  Widget _buildConnectedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Connected',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(scannedUrl ?? ''),
        ],
      ),
    );
  }

  /// Error UI
  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error, color: Colors.red, size: 64),
          const SizedBox(height: 16),
          Text(
            errorMessage ?? 'Connection failed',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              setState(() {
                isScanning = true;
                isConnecting = false;
                isConnected = false;
                errorMessage = null;
                scannedUrl = null;
              });
            },
            child: const Text('Scan Again'),
          ),
        ],
      ),
    );
  }

  /// Actual connection logic
  Future<void> _connectToServer(String url) async {
    try {
      final uri = Uri.parse('$url/ping');
      final client = HttpClient();

      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 5));

      final response = await request.close();

      if (response.statusCode == 200) {
        setState(() {
          isConnecting = false;
          isConnected = true;
        });
      } else {
        throw Exception('Server not reachable');
      }
    } on TimeoutException {
      _handleFailure('Connection timed out');
    } catch (e) {
      _handleFailure('Failed to connect to desktop');
    }
  }

  void _handleFailure(String message) {
    setState(() {
      isConnecting = false;
      isConnected = false;
      errorMessage = message;
    });
  }
}
