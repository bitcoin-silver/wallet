import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final walletProvider = Provider.of<WalletProvider>(context);

    final address = walletProvider.address;
    final privateKey = walletProvider.privateKey ?? '';
    print('Address: $address, KEY: $privateKey');

    return Scaffold(
      backgroundColor: const Color(0xFF333333),
      appBar: AppBar(
        backgroundColor: const Color(0xFF333333),
        automaticallyImplyLeading: false,
        actions: const <Widget>[
          SizedBox(width: 16), // Abstand zwischen den Icons
        ],
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
              'Your private key is a critical piece of information for accessing your cryptocurrency. Keep it secure and never share it with anyone. If someone gains access to your private key, they can control your assets. Make sure to store it in a safe place and back it up if necessary.',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await walletProvider.deleteWallet();
                if (context.mounted) {
                  final address = walletProvider.address;
                  final privateKey = walletProvider.privateKey;
                  print('Deleted Address: $address, Deleted Key: $privateKey');
                  Navigator.pushReplacementNamed(context, '/');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12.0),
              ),
              child: const Text('Delete Wallet'),
            ),
          ],
        ),
      ),
    );
  }
}
