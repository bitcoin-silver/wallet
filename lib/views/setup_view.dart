import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/services/wallet_service.dart';
import 'package:bitcoinsilver_wallet/services/biometric_service.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/providers/blockchain_provider.dart';
import 'package:bitcoinsilver_wallet/widgets/button_widget.dart';

class SetupView extends StatelessWidget {
  SetupView({super.key});

  final TextEditingController _recoverController = TextEditingController();
  final WalletService _walletService = WalletService();
  final BiometricService _biometricService = BiometricService();

  Future<void> _processWallet(BuildContext context, String privateKey, {bool isNewWallet = false}) async {
    final address = _walletService.loadAddressFromKey(privateKey);
    if (address != null) {
      // Show private key dialog for new wallets
      if (isNewWallet) {
        final confirmed = await _showPrivateKeyDialog(context, privateKey, address);
        if (!confirmed) {
          // User cancelled, don't proceed
          return;
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Valid private key found!'),
          backgroundColor: Colors.green,
        ));
      }

      final wp = Provider.of<WalletProvider>(context, listen: false);
      await wp.saveWallet(address, privateKey);

      // Fetch UTXOs before loading blockchain
      await wp.fetchUtxos(force: true);

      final bp = Provider.of<BlockchainProvider>(context, listen: false);
      await bp.loadBlockchain(address);

      // Ask about biometric authentication
      if (context.mounted) {
        await _askBiometricSetup(context);
      }

      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Invalid private key found!'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _askBiometricSetup(BuildContext context) async {
    final isAvailable = await _biometricService.isBiometricAvailable();
    if (!isAvailable) return;

    final types = await _biometricService.getAvailableBiometrics();
    final typeName = _biometricService.getBiometricTypeName(types);

    final enable = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color.fromARGB(255, 25, 25, 25),
          title: Row(
            children: [
              Icon(
                typeName.contains('Face') ? Icons.face : Icons.fingerprint,
                color: Colors.cyanAccent,
                size: 28,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Secure Your Wallet',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Would you like to enable $typeName to secure your wallet?',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'When enabled, you\'ll need to authenticate with $typeName each time you open the app.',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Skip',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
              ),
              child: const Text('Enable'),
            ),
          ],
        );
      },
    );

    if (enable == true) {
      // Test authentication first
      final authenticated = await _biometricService.authenticate(
        localizedReason: 'Authenticate to enable $typeName',
      );

      if (authenticated) {
        await _biometricService.enableBiometric();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$typeName enabled successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }

  Future<bool> _showPrivateKeyDialog(BuildContext context, String privateKey, String address) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        bool hasConfirmed = false;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color.fromARGB(255, 25, 25, 25),
              title: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange, size: 28),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Save Your Private Key',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your wallet has been created! Write down your private key and store it safely.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '⚠️ CRITICAL WARNINGS:',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• Never share this key with anyone\n• This is the ONLY way to recover your wallet\n• If you lose it, your funds are GONE FOREVER\n• Write it on paper and store it securely',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Your Address:',
                      style: TextStyle(
                        color: Colors.white60,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                      ),
                      child: SelectableText(
                        address,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.cyanAccent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Your Private Key:',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: SelectableText(
                        privateKey,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Checkbox(
                          value: hasConfirmed,
                          onChanged: (bool? value) {
                            setState(() {
                              hasConfirmed = value ?? false;
                            });
                          },
                          checkColor: Colors.black,
                          activeColor: Colors.orange,
                        ),
                        const Expanded(
                          child: Text(
                            'I have written down my private key',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                ElevatedButton(
                  onPressed: hasConfirmed
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasConfirmed ? Colors.orange : Colors.grey,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('I Saved It - Continue'),
                ),
              ],
            );
          },
        );
      },
    ) ?? false;
  }

  void _recoverWallet(BuildContext context) {
    final privateKey = _recoverController.text.trim();
    if (privateKey.isNotEmpty) {
      _processWallet(context, privateKey);
    }
  }

  Future<void> _generateWallet(BuildContext context) async {
    final privateKey = _walletService.generatePrivateKey();
    if (privateKey != null) {
      await _processWallet(context, privateKey, isNewWallet: true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to generate wallet. Please try again.'),
        backgroundColor: Colors.red,
      ));
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
