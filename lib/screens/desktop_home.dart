import 'package:flutter/material.dart';

class DesktopHome extends StatelessWidget {
  const DesktopHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('UniShare – Desktop')),
      body: const Center(
        child: Text(
          'Desktop Mode\n\nServer will run here.\nQR code will be shown here.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}
