import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/widgets/button_widget.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final walletProvider = Provider.of<WalletProvider>(context);
    final privateKey = walletProvider.privateKey ?? '';

    return Scaffold(
      body: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight:
                MediaQuery.of(context).size.height - kBottomNavigationBarHeight,
          ),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.black, Colors.black],
                stops: [0, 0.75],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 75, left: 16.0, right: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: TextEditingController(text: privateKey),
                    decoration: InputDecoration(
                      labelText: 'Private Key',
                      labelStyle: const TextStyle(color: Colors.white),
                      filled: true,
                      fillColor: const Color.fromARGB(100, 0, 0, 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide:
                            const BorderSide(color: Colors.white, width: 1.0),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide:
                            const BorderSide(color: Colors.white, width: 1.0),
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.copy, color: Colors.white),
                        onPressed: () {
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
                    style: TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 20),
                  ButtonWidget(
                    text: 'Delete Wallet',
                    isPrimary: true,
                    onPressed: () async {
                      await walletProvider.deleteWallet();
                      if (context.mounted) {
                        Navigator.pushReplacementNamed(context, '/setup');
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
