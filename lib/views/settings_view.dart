import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'start_view.dart';

class SettingsView extends StatelessWidget {
  final storage = const FlutterSecureStorage();

  const SettingsView({super.key});

  Future<void> _deleteWallet(BuildContext context) async {
    // Lösche den privaten Schlüssel aus dem sicheren Speicher
    await storage.delete(key: 'private_key');

    // Navigiere zur StartView und ersetze die aktuelle Route
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => StartView()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings View'),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: () => _deleteWallet(context),
          child: const Text('Delete Wallet'),
        ),
      ),
    );
  }
}
