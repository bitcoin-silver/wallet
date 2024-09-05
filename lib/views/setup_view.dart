import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/services/wallet_service.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/widgets/button_widget.dart';

class SetupView extends StatelessWidget {
  SetupView({super.key});

  final TextEditingController _recoverController = TextEditingController();
  final WalletService _walletService = WalletService();

  void _processWallet(BuildContext context, String privateKey) {
    final address = _walletService.loadAddressFromKey(privateKey);
    if (address != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Valid private key found!'),
        backgroundColor: Colors.green,
      ));

      final walletProvider =
          Provider.of<WalletProvider>(context, listen: false);
      walletProvider.saveWallet(address, privateKey);
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Invalid private key found!'),
        backgroundColor: Colors.red,
      ));
    }
  }

  void _recoverWallet(BuildContext context) {
    final privateKey = _recoverController.text.trim();
    if (privateKey.isNotEmpty) {
      _processWallet(context, privateKey);
    }
  }

  void _generateWallet(BuildContext context) {
    final privateKey = _walletService.generatePrivateKey();
    if (privateKey != null) {
      _processWallet(context, privateKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/background.jpg',
              fit: BoxFit.cover,
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: IntrinsicHeight(
                    child: Container(
                      color: Colors.black.withOpacity(0.5),
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 50),
                          const Text(
                            'Welcome to Your Future',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Recover Your Wallet',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Enter your private key to recover your wallet. Ensure that the key is correct to access your previous assets and data securely.',
                            style: TextStyle(color: Colors.white54),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _recoverController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Enter your private key',
                              hintStyle: const TextStyle(color: Colors.white54),
                              filled: true,
                              fillColor: Colors.transparent,
                              enabledBorder: OutlineInputBorder(
                                borderSide:
                                    const BorderSide(color: Colors.white),
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide:
                                    const BorderSide(color: Colors.white),
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          ButtonWidget(
                            text: 'Recover',
                            isPrimary: true,
                            onPressed: () => _recoverWallet(context),
                          ),
                          const SizedBox(height: 40),
                          const Divider(color: Colors.white),
                          const SizedBox(height: 20),
                          const Text(
                            'Generate a New Wallet',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Create a new wallet to securely store your assets. A new private key will be generated which you should keep safe and secure.',
                            style: TextStyle(color: Colors.white54),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          ButtonWidget(
                            text: 'Generate',
                            isPrimary: true,
                            onPressed: () => _generateWallet(context),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Note: Always keep your private key secure. Losing it means losing access to your wallet and assets.',
                            style: TextStyle(color: Colors.white54),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
