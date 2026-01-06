import 'package:flutter/material.dart';
import '../widgets/qr_code_display.dart';
import '../services/server_service.dart';

class DesktopHome extends StatefulWidget {
  const DesktopHome({super.key});

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHome> {
  bool isStarted = false;
  bool isLoading = false;

  final ServerService _serverService = ServerService();
  String? connectionUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('UniShare – Desktop')),
      body: Center(
        child: isStarted
            ? _buildQrView()
            : isLoading
            ? const CircularProgressIndicator()
            : _buildStartView(),
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
          onPressed: _startServer,
          icon: const Icon(Icons.qr_code),
          label: const Text('Start & Show QR'),
        ),
      ],
    );
  }

  /// Start real server
  Future<void> _startServer() async {
    setState(() {
      isLoading = true;
    });

    await _serverService.start();

    setState(() {
      connectionUrl = 'http://${_serverService.ip}:${_serverService.port}';
      isStarted = true;
      isLoading = false;
    });
  }

  /// QR code screen
  Widget _buildQrView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Server Running',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(connectionUrl!),
        const SizedBox(height: 24),
        QrCodeDisplay(data: connectionUrl!),
        const SizedBox(height: 24),
        const Text(
          'Scan this QR code from the mobile app',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
