import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/connection_service.dart';
import '../services/http_client_service.dart';


class MobileHome extends StatefulWidget {
  const MobileHome({super.key});

  @override
  State<MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends State<MobileHome> {
  String? scannedUrl;
  bool isScanning = true;
  bool isChecking = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('UniShare – Mobile')),
      body: isScanning ? _buildScanner() : _buildConnectedView(),
    );
  }

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
            onDetect: (capture) async {
  final barcode = capture.barcodes.first;
  final String? code = barcode.rawValue;

  if (code == null) return;

  setState(() {
    isScanning = false;
    scannedUrl = 'Connecting...';
  });

  final isConnected =
      await HttpClientService.testConnection(code);

  if (!mounted) return;

  if (isConnected) {
    setState(() {
      scannedUrl = code;
    });
  } else {
    setState(() {
      isScanning = true;
      scannedUrl = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Failed to connect to desktop'),
      ),
    );
  }
},

          ),
        ),
      ],
    );
  }

  Widget _buildConnectedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle,
              color: Colors.green, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Connected',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            scannedUrl ?? '',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
