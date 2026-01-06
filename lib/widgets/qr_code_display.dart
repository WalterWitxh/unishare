import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrCodeDisplay extends StatelessWidget {
  final String data;

  const QrCodeDisplay({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return QrImageView(data: data, size: 220, backgroundColor: Colors.white);
  }
}
