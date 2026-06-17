import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/services/biometric_service.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/providers/blockchain_provider.dart';
import 'package:bitcoinsilver_wallet/widgets/button_widget.dart';

class SetupView extends StatelessWidget {
  SetupView({super.key});

  final TextEditingController _recoverController = TextEditingController();
  final BiometricService _biometricService = BiometricService();

  Future<void> _processWallet(BuildContext context, String privateKey, {String? mnemonic, bool isNewWallet = false}) async {
    final wp = Provider.of<WalletProvider>(context, listen: false);
    final walletService = wp.walletService;
    final address = walletService.loadAddressFromKey(privateKey);
    if (address != null) {
      // Show backup dialog for new wallets
      if (isNewWallet) {
        final confirmed = await _showBackupDialog(context, privateKey, address, mnemonic: mnemonic);
        if (!confirmed) {
          // User cancelled, don't proceed
          return;
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Valid key/phrase found!'),
          backgroundColor: Colors.green,
        ));
      }

      if (!context.mounted) return;
      await wp.saveWallet(address, privateKey, mnemonic: mnemonic);

      // Fetch UTXOs before loading blockchain
      await wp.fetchUtxos(force: true);

      if (!context.mounted) return;
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

    if (!context.mounted) return;
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

  Future<bool> _showBackupDialog(BuildContext context, String privateKey, String address, {String? mnemonic}) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        bool hasConfirmed = false;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color.fromARGB(255, 25, 25, 25),
              title: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange, size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      mnemonic != null ? 'Save Your Seed Phrase' : 'Save Your Private Key',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mnemonic != null 
                        ? 'Your wallet has been created! Write down these ${mnemonic.split(' ').length} words and store them safely.'
                        : 'Your wallet has been created! Write down your private key and store it safely.',
                      style: const TextStyle(
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
                      '• Never share this with anyone\n• This is the ONLY way to recover your wallet\n• If you lose it, your funds are GONE FOREVER\n• Write it on paper and store it securely',
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
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                      ),
                      child: SelectableText(
                        address,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.cyanAccent,
                        ),
                      ),
                    ),
                    if (mnemonic != null) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Your Seed Phrase:',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                        ),
                        child: SelectableText(
                          mnemonic,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            fontFamily: 'monospace',
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text(
                      'Your Raw Private Key:',
                      style: TextStyle(
                        color: Colors.white38,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: SelectableText(
                        privateKey,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 9,
                          fontFamily: 'monospace',
                          color: Colors.white38,
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
                        Expanded(
                          child: Text(
                            mnemonic != null 
                              ? 'I have written down my seed phrase'
                              : 'I have written down my private key',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
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

  void _recoverWallet(BuildContext context) async {
    final input = _recoverController.text.trim();
    if (input.isEmpty) return;

    final wp = Provider.of<WalletProvider>(context, listen: false);
    
    // Check if it's a mnemonic (multiple words)
    if (input.split(' ').length >= 12) {
      final walletData = await wp.walletService.getWalletFromMnemonic(input);
      if (walletData != null) {
        if (!context.mounted) return;
        await _processWallet(context, walletData['privateKey']!, mnemonic: input);
        return;
      }
    }

    // Otherwise treat as WIF
    if (!context.mounted) return;
    _processWallet(context, input);
  }

  Future<void> _generateWallet(BuildContext context) async {
    final wp = Provider.of<WalletProvider>(context, listen: false);
    final privateKey = wp.walletService.generatePrivateKey();
    if (privateKey != null) {
      await _processWallet(context, privateKey, isNewWallet: true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to generate wallet. Please try again.'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _generateSeedWallet(BuildContext context) async {
    final int? words = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Seed Phrase Length', style: TextStyle(color: Colors.white)),
        content: const Text('Choose how many words you want for your recovery phrase.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 12),
            child: const Text('12 Words', style: TextStyle(color: Colors.cyanAccent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 24),
            child: const Text('24 Words', style: TextStyle(color: Colors.cyanAccent)),
          ),
        ],
      ),
    );

    if (words == null) return;

    if (!context.mounted) return;
    final wp = Provider.of<WalletProvider>(context, listen: false);
    final walletData = await wp.walletService.generateNewSeedWallet(words: words);
    
    if (!context.mounted) return;
    await _processWallet(
      context, 
      walletData['privateKey']!, 
      mnemonic: walletData['mnemonic'], 
      isNewWallet: true
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
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
                        color: Colors.black.withValues(alpha: 0.5),
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
                            'Enter your seed phrase or private key to recover your wallet.',
                            style: TextStyle(color: Colors.white54),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _recoverController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Seed phrase or private key',
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
                            text: 'Recover Wallet',
                            isPrimary: true,
                            onPressed: () => _recoverWallet(context),
                          ),
                          const SizedBox(height: 40),
                          const Divider(color: Colors.white24),
                          const SizedBox(height: 20),
                          const Text(
                            'New to Bitcoin Silver?',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ButtonWidget(
                            text: 'Generate Seed Phrase',
                            isPrimary: true,
                            onPressed: () => _generateSeedWallet(context),
                          ),
                          const SizedBox(height: 10),
                          ButtonWidget(
                            text: 'Legacy Private Key',
                            isPrimary: false,
                            onPressed: () => _generateWallet(context),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Note: Seed phrases (12/24 words) are the modern standard and highly recommended.',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
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
      ),
    );
  }
}
