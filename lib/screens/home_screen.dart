import 'package:flutter/material.dart';

/// This is the first screen of the app.
/// From here, the user will choose what they want to do.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UniShare'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App title / description
            Text(
              'Local File Transfer',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Transfer files between Windows and Android over local Wi-Fi.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // Button for users who are on desktop
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  // TODO: Later - Navigate to Desktop screen
                  // Navigator.push(...);
                },
                icon: const Icon(Icons.computer),
                label: const Text('I am using Desktop'),
              ),
            ),

            const SizedBox(height: 12),

            // Button for users who are on mobile
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  // TODO: Later - Navigate to Mobile screen
                  // Navigator.push(...);
                },
                icon: const Icon(Icons.smartphone),
                label: const Text('I am using Mobile'),
              ),
            ),

            const SizedBox(height: 24),

            // (Optional) Info text for team / users
            Text(
              'This is just the starting screen. '
              'Desktop and Mobile flows will be added from here.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
