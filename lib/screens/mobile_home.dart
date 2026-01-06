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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UniShare – Mobile'),
      ),
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
            onDetect: (capture) {
              final barcode = capture.barcodes.first;
              final String? code = barcode.rawValue;

              if (code != null) {
                setState(() {
                  scannedUrl = code;
                  isScanning = false;
                });
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
          const Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 64,
          ),
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
