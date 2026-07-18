import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/services/biometric_service.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/providers/blockchain_provider.dart';

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
                      'Wallet Address:',
                      style: TextStyle(
                        color: Colors.cyanAccent,
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
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: Colors.cyanAccent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: address));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Address copied')),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copy Address'),
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
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: mnemonic));
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Seed phrase copied')),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy Seed Phrase'),
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
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: privateKey));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Private key copied')),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copy Private Key'),
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

  ButtonStyle _primaryActionStyle() {
    return ElevatedButton.styleFrom(
      minimumSize: const Size(double.infinity, 52),
      backgroundColor: Colors.cyanAccent,
      foregroundColor: Colors.black,
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
    );
  }

  ButtonStyle _secondaryActionStyle() {
    return OutlinedButton.styleFrom(
      minimumSize: const Size(double.infinity, 52),
      foregroundColor: Colors.white,
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      side: const BorderSide(color: Colors.white38),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: Colors.white.withValues(alpha: 0.02),
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
                cacheWidth: 1000, // Downsample background for memory efficiency
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.56),
                      padding: EdgeInsets.fromLTRB(
                        16,
                        22,
                        16,
                        20 + MediaQuery.of(context).viewPadding.bottom,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 540),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: Container(
                                  width: 66,
                                  height: 66,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.cyanAccent.withValues(alpha: 0.15),
                                    border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.55)),
                                  ),
                                  child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.cyanAccent, size: 32),
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'Set Up Your Wallet',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Recover an existing wallet or create a new one with modern seed phrase backup.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.45),
                              ),
                              const SizedBox(height: 24),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white24),
                                ),
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const Text(
                                      'Recover Wallet',
                                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Paste your seed phrase or private key to restore access.',
                                      style: TextStyle(color: Colors.white60, fontSize: 13),
                                    ),
                                    const SizedBox(height: 14),
                                    TextField(
                                      controller: _recoverController,
                                      style: const TextStyle(color: Colors.white),
                                      maxLines: null,
                                      textInputAction: TextInputAction.done,
                                      decoration: InputDecoration(
                                        hintText: 'Seed phrase or private key',
                                        hintStyle: const TextStyle(color: Colors.white54),
                                        filled: true,
                                        fillColor: Colors.black.withValues(alpha: 0.25),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: const BorderSide(color: Colors.white30),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderSide: const BorderSide(color: Colors.cyanAccent),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    ElevatedButton.icon(
                                      onPressed: () => _recoverWallet(context),
                                      style: _primaryActionStyle(),
                                      icon: const Icon(Icons.lock_open_rounded, size: 18),
                                      label: const Text('Recover Wallet'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  const Expanded(child: Divider(color: Colors.white24)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    child: Text(
                                      'OR CREATE NEW',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.7),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),
                                  const Expanded(child: Divider(color: Colors.white24)),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white24),
                                ),
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const Text(
                                      'New to Bitcoin Silver?',
                                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Seed phrases (12 or 24 words) are the modern standard and strongly recommended.',
                                      style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.35),
                                    ),
                                    const SizedBox(height: 14),
                                    ElevatedButton.icon(
                                      onPressed: () => _generateSeedWallet(context),
                                      style: _primaryActionStyle(),
                                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                                      label: const Text('Generate Seed Phrase'),
                                    ),
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      onPressed: () => _generateWallet(context),
                                      style: _secondaryActionStyle(),
                                      icon: const Icon(Icons.vpn_key_outlined, size: 18),
                                      label: const Text('Legacy Private Key'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        )
      ),
    );
  }
}
