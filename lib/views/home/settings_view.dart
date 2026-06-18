import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_settings/app_settings.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/providers/blockchain_provider.dart';
import 'package:bitcoinsilver_wallet/views/home/privacy_view.dart';
import 'package:bitcoinsilver_wallet/views/home/about_view.dart';
import 'package:bitcoinsilver_wallet/views/home/support_view.dart';
import 'package:bitcoinsilver_wallet/views/home/network_info_view.dart';
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

  // Notification settings
  bool _notificationsEnabled = false;
  bool _isTogglingNotifications = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricStatus();
    _loadNotificationPreference();
  }

  Future<void> _loadNotificationPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _notificationsEnabled = prefs.getBool('notifications_enabled') ?? false;
      });
    }
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

  Future<void> _toggleNotifications(bool value, WalletProvider wp) async {
    if (_isTogglingNotifications) return;

    setState(() {
      _isTogglingNotifications = true;
    });

    try {
      if (value) {
        // Enabling - show confirmation dialog
        final enable = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: const Color.fromARGB(255, 25, 25, 25),
              title: const Row(
                children: [
                  Icon(
                    Icons.notifications_active,
                    color: Color(0xFFC0C0C0),
                    size: 28,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Enable Push Notifications',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              content: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Would you like to enable push notifications?',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Get instant push notifications when you receive transactions to your wallet.',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'You will be taken to system settings where you can choose which notification types to enable.',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
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
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC0C0C0),
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Enable'),
                ),
              ],
            );
          },
        );

        if (enable != true) {
          setState(() {
            _isTogglingNotifications = false;
          });
          return;
        }

        // Save preference
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('notifications_enabled', true);

        // Initialize notifications
        final address = wp.address;
        if (address != null) {
          await wp.enableNotifications(address);
        }

        setState(() {
          _notificationsEnabled = true;
        });

        // Open system notification settings
        if (mounted) {
          await AppSettings.openAppSettings(type: AppSettingsType.notification);
        }
      } else {
        // Disabling - show confirmation dialog
        final disable = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: const Color.fromARGB(255, 25, 25, 25),
              title: const Row(
                children: [
                  Icon(
                    Icons.notifications_off,
                    color: Colors.orange,
                    size: 28,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Disable Notifications',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              content: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you sure you want to disable push notifications?',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Your device will no longer receive any notifications.',
                    style: TextStyle(
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
                    'Cancel',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Disable'),
                ),
              ],
            );
          },
        );

        if (disable != true) {
          setState(() {
            _isTogglingNotifications = false;
          });
          return;
        }

        // Unregister from backend
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('notifications_enabled', false);

        final address = wp.address;
        if (address != null) {
          await wp.disableNotifications(address);
        }

        setState(() {
          _notificationsEnabled = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Push notifications disabled'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update notifications: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isTogglingNotifications = false;
      });
    }
  }

  Future<void> _showMigrationDialog(BuildContext context, WalletProvider wp, BlockchainProvider bp) async {
    int migrationSeedWords = 12;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.cyanAccent),
              SizedBox(width: 8),
              Text('Upgrade to Seed Phrase', style: TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This will generate a new BIP39 seed phrase and move your funds to it.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              const Text('Choose Phrase Length:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              RadioGroup<int>(
                groupValue: migrationSeedWords,
                onChanged: (val) => setState(() => migrationSeedWords = val!),
                child: Row(
                  children: [
                    Radio<int>(
                      value: 12,
                      activeColor: Colors.cyanAccent,
                    ),
                    const Text('12 Words', style: TextStyle(color: Colors.white70)),
                    const SizedBox(width: 20),
                    Radio<int>(
                      value: 24,
                      activeColor: Colors.cyanAccent,
                    ),
                    const Text('24 Words', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Note: If you have a balance, a transaction will be sent to sweep your funds to the new address. Fees will apply.',
                style: TextStyle(color: Colors.orange, fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black),
              child: const Text('Start Migration'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      if (!context.mounted) return;
      
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
      );

      final success = await wp.migrateToSeed(words: migrationSeedWords);

      if (!context.mounted) return;
      Navigator.pop(context); // Close loading indicator

      if (success) {
        await bp.loadBlockchain(wp.address);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Migration successful!'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(wp.lastError ?? 'Migration failed'), backgroundColor: Colors.red),
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
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
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
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
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
    final mnemonic = wp.mnemonic;

    return Scaffold(
      body: AppBackground(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
              MediaQuery.of(context).size.height - kBottomNavigationBarHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 75, left: 16.0, right: 16.0, bottom: 130.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (mnemonic != null) ...[
                    const Text(
                      'Seed Phrase',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: TextEditingController(text: mnemonic),
                      decoration: InputDecoration(
                        labelText: 'Your 12/24 Word Phrase',
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
                            Clipboard.setData(ClipboardData(text: mnemonic));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Seed phrase copied to clipboard'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          },
                        ),
                      ),
                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                      obscureText: true,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Your Seed Phrase above recovers your entire wallet, including all future addresses. Keep it secure and never share it with anyone.',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                    const SizedBox(height: 20),
                  ],
                  const Text(
                    'Private Key (WIF)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: TextEditingController(text: privateKey),
                    decoration: InputDecoration(
                      labelText: 'Private Key (WIF)',
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
                    'This WIF key is derived from your seed and controls ONLY the current address. The Seed Phrase is the primary backup.',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  const SizedBox(height: 20),

                  if (mnemonic == null) ...[
                    ElevatedButton.icon(
                      onPressed: () => _showMigrationDialog(context, wp, bp),
                      icon: const Icon(Icons.upgrade),
                      label: const Text('Migrate to Seed Phrase'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent.withValues(alpha: 0.1),
                        foregroundColor: Colors.cyanAccent,
                        side: const BorderSide(color: Colors.cyanAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Upgrade to a modern 12 or 24 word recovery phrase. This is more secure and easier to back up.',
                      style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontStyle: FontStyle.italic),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                  ],

                  const SizedBox(height: 10),

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
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
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
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
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
                        activeThumbColor: const Color(0xFFC0C0C0),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.3),
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

                  const SizedBox(height: 15),

                  // Push Notifications Toggle
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: SwitchListTile(
                      title: const Text(
                        'Push Notifications',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        _notificationsEnabled
                            ? 'Get notified when you receive BTCS'
                            : 'You will not receive transaction alerts',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      secondary: Icon(
                        _notificationsEnabled ? Icons.notifications_active : Icons.notifications_off,
                        color: _notificationsEnabled ? const Color(0xFFC0C0C0) : Colors.white54,
                      ),
                      value: _notificationsEnabled,
                      onChanged: _isTogglingNotifications
                          ? null
                          : (value) => _toggleNotifications(value, wp),
                      activeThumbColor: const Color(0xFFC0C0C0),
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
                      'Network Status',
                      style: TextStyle(color: Colors.white),
                    ),
                    leading: const Icon(Icons.lan, color: Colors.white),
                    onTap: () {
                      if (context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const NetworkInfoView(),
                          ),
                        );
                      }
                    },
                  ),
                  const Divider(color: Colors.white),
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
