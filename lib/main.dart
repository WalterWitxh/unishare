import 'dart:io';

import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/desktop_home.dart';
import 'screens/mobile_home.dart';

void main() {
  runApp(const UniShareApp());
}

class UniShareApp extends StatelessWidget {
  const UniShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UniShare',
      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.light,
      ),

      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
      ),

      home: _getStartScreen(),
    );
  }

  Widget _getStartScreen() {
    if (Platform.isWindows) {
      return const DesktopHome();
    } else if (Platform.isAndroid) {
      return const MobileHome();
    } else if (Platform.isLinux) {
      return const DesktopHome();
    } else {
      return const HomeScreen();
    }
  }
}
