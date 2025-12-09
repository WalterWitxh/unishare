import 'package:flutter/material.dart';
import 'screens/home_screen.dart'; // We are going to create this file

/// Entry point of the Flutter application.
/// This is the first function that runs when the app starts.
void main() {
  runApp(const UniShareApp());
}

/// Root widget of the entire application.
/// It sets up themes, routes, and the first screen.
class UniShareApp extends StatelessWidget {
  const UniShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UniShare',

      // Remove the debug banner in the top-right corner.
      debugShowCheckedModeBanner: false,

      // Light theme
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue, // All colors are based on this seed
        brightness: Brightness.light,
      ),

      // Dark theme
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
      ),

      // First screen that will be shown when the app starts.
      home: const HomeScreen(),
    );
  }
}
