import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'views/start_view.dart';
import 'views/home_view.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  final storage = const FlutterSecureStorage();

  const MyApp({super.key});

  Future<Widget> _decideHomePage() async {
    // Check if private key is stored
    String? privateKey = await storage.read(key: 'private_key');
    if (privateKey == null) {
      // Navigate to start view if private key is not found
      return const StartView();
    } else {
      // Navigate to home view if private key is found
      return const HomeView();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: FutureBuilder<Widget>(
        future: _decideHomePage(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // Display a loading screen while waiting for the future to complete
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          } else if (snapshot.hasData) {
            // Display the decided page
            return snapshot.data!;
          } else {
            // Handle error or show fallback screen
            return const Scaffold(
              body: Center(child: Text('Error')),
            );
          }
        },
      ),
    );
  }
}
