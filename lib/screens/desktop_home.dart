import 'package:flutter/material.dart';
import '../widgets/qr_code_display.dart';

class DesktopHome extends StatefulWidget {
  const DesktopHome({super.key});

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHome> {
  bool isStarted = false;

  // Temporary demo values
  final String ip = '192.168.1.5';
  final int port = 52343;

  @override
  Widget build(BuildContext context) {
    final String connectionUrl = 'http://$ip:$port';

    return Scaffold(
      appBar: AppBar(title: const Text('UniShare – Desktop')),
      body: Center(
        child: isStarted ? _buildQrView(connectionUrl) : _buildStartView(),
      ),
    );
  }

  /// Initial screen with button
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
          onPressed: () {
            setState(() {
              isStarted = true;
            });
          },
          icon: const Icon(Icons.qr_code),
          label: const Text('Start & Show QR'),
        ),
      ],
    );
  }

  /// QR code screen
  Widget _buildQrView(String connectionUrl) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Server Running',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(connectionUrl),
        const SizedBox(height: 24),
        QrCodeDisplay(data: connectionUrl),
        const SizedBox(height: 24),
        const Text(
          'Scan this QR code from the mobile app',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
