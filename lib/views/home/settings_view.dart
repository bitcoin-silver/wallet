import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/modals/recovery_modal.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  void _showRecoveryModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF333333),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) {
        return const RecoveryModal(); // Nutze das extrahierte RecoveryModal
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final walletProvider = Provider.of<WalletProvider>(context);
    final privateKey = walletProvider.privateKey ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF333333),
      appBar: AppBar(
        backgroundColor: const Color(0xFF333333),
        elevation: 0,
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: TextEditingController(text: privateKey),
              decoration: InputDecoration(
                labelText: 'Private Key',
                labelStyle: const TextStyle(color: Colors.white),
                filled: true,
                fillColor: const Color(0xFF333333),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: const BorderSide(color: Colors.white, width: 1.0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: const BorderSide(color: Colors.white, width: 1.0),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.copy, color: Colors.white),
                  onPressed: () {
                    // Kopieren des Private Keys in die Zwischenablage
                    Clipboard.setData(ClipboardData(text: privateKey));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied to clipboard'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                ),
              ),
              style: const TextStyle(color: Colors.white),
              obscureText: true,
              maxLines: 1,
            ),
            const SizedBox(height: 20),
            const Text(
              'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _showRecoveryModal(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
              ),
              child: const Text(
                'Recover wallet',
                style: TextStyle(color: Color(0xFF333333)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
