import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/providers/blockchain_provider.dart';
import 'package:bitcoinsilver_wallet/views/home/privacy_view.dart';
import 'package:bitcoinsilver_wallet/views/home/about_view.dart';
import 'package:bitcoinsilver_wallet/views/home/support_view.dart';
import 'package:bitcoinsilver_wallet/services/biometric_service.dart';
import 'package:bitcoinsilver_wallet/widgets/app_background.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final BiometricService _biometricService = BiometricService();
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _isCheckingBiometric = true;
  String _biometricType = 'Biometric';

  @override
  void initState() {
    super.initState();
    _checkBiometricStatus();
  }

  Future<void> _checkBiometricStatus() async {
    final isAvailable = await _biometricService.isBiometricAvailable();
    final isEnabled = await _biometricService.isBiometricEnabled();
    final types = await _biometricService.getAvailableBiometrics();
    final typeName = _biometricService.getBiometricTypeName(types);

    if (mounted) {
      setState(() {
        _biometricAvailable = isAvailable;
        _biometricEnabled = isEnabled;
        _biometricType = typeName;
        _isCheckingBiometric = false;
      });
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      // Enabling - test authentication first
      final authenticated = await _biometricService.authenticate(
        localizedReason: 'Authenticate to enable $_biometricType',
      );

      if (authenticated) {
        await _biometricService.enableBiometric();
        setState(() {
          _biometricEnabled = true;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$_biometricType enabled'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Authentication failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      // Disabling
      await _biometricService.disableBiometric();
      setState(() {
        _biometricEnabled = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$_biometricType disabled'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _showDeleteWalletDialog(BuildContext context, WalletProvider wp, BlockchainProvider bp) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color.fromARGB(255, 25, 25, 25),
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Delete Wallet?',
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
                  '⚠️ IMPORTANT WARNING',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'This action will:',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '• Remove your wallet from this device\n'
                  '• Delete all transaction history\n'
                  '• Disable biometric authentication',
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lightbulb_outline, color: Colors.orange, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Did you know?',
                            style: TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        'You can switch wallets without deleting! Simply recover a different wallet using its private key in the setup screen.',
                        style: TextStyle(color: Colors.orange, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.security, color: Colors.red, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Before you delete:',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '✓ Make sure your private key is safely backed up\n'
                        '✓ Without it, you CANNOT recover your funds\n'
                        '✓ This action is IRREVERSIBLE',
                        style: TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete Wallet'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await wp.deleteWallet();
      bp.clearTransactions();
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/setup');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wp = Provider.of<WalletProvider>(context);
    final bp = Provider.of<BlockchainProvider>(context);
    final privateKey = wp.privateKey ?? '';

    return Scaffold(
      body: AppBackground(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  MediaQuery.of(context).size.height - kBottomNavigationBarHeight,
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
                  const SizedBox(height: 30),

                  // Security Section
                  const Text(
                    'Security',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Biometric Toggle - Always show placeholder while loading to prevent layout shift
                  if (_isCheckingBiometric)
                    Container(
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFC0C0C0)),
                          ),
                        ),
                      ),
                    )
                  else if (_biometricAvailable)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: SwitchListTile(
                        title: Text(
                          'Enable $_biometricType',
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          _biometricEnabled
                              ? 'App requires $_biometricType authentification'
                              : 'Secure your wallet with $_biometricType',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        secondary: Icon(
                          _biometricType.contains('Face')
                              ? Icons.face
                              : Icons.fingerprint,
                          color: _biometricEnabled ? const Color(0xFFC0C0C0) : Colors.white,
                        ),
                        value: _biometricEnabled,
                        onChanged: _toggleBiometric,
                        activeColor: const Color(0xFFC0C0C0),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange, size: 20),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Biometric authentication not available on this device',
                              style: TextStyle(color: Colors.orange, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 30),
                  const Text(
                    'General',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),

                  ListTile(
                    title: const Text(
                      'Privacy Policy',
                      style: TextStyle(color: Colors.white),
                    ),
                    leading: const Icon(Icons.description, color: Colors.white),
                    onTap: () async {
                      if (context.mounted) {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const PrivacyView()));
                      }
                    },
                  ),
                  const Divider(color: Colors.white),
                  ListTile(
                    title: const Text(
                      'Support',
                      style: TextStyle(color: Colors.white),
                    ),
                    leading: const Icon(Icons.help, color: Colors.white),
                    onTap: () {
                      if (context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SupportView(),
                          ),
                        );
                      }
                    },
                  ),
                  const Divider(color: Colors.white),
                  ListTile(
                    title: const Text(
                      'About',
                      style: TextStyle(color: Colors.white),
                    ),
                    leading: const Icon(Icons.info, color: Colors.white),
                    onTap: () {
                      if (context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AboutView(),
                          ),
                        );
                      }
                    },
                  ),
                  const Divider(color: Colors.white),
                  ListTile(
                    title: const Text(
                      'Delete Wallet',
                      style: TextStyle(color: Colors.red),
                    ),
                    leading: const Icon(Icons.delete, color: Colors.red),
                    onTap: () => _showDeleteWalletDialog(context, wp, bp),
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
