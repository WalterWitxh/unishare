import 'package:flutter/material.dart';
import '../widgets/qr_code_display.dart';

class DesktopHome extends StatelessWidget {
  const DesktopHome({super.key});

  @override
  Widget build(BuildContext context) {
    // Temporary demo values (will be dynamic later)
    const String ip = '192.168.1.5';
    const int port = 52343;
    final String connectionUrl = 'http://$ip:$port';

    return Scaffold(
      appBar: AppBar(title: const Text('UniShare – Desktop')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Desktop Mode',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 16),

            const Text('Local server address:'),
            const SizedBox(height: 4),
            Text(
              connectionUrl,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 24),

            QrCodeDisplay(data: connectionUrl),

            const SizedBox(height: 24),

            const Text(
              'Scan this QR code from the mobile app to connect',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
