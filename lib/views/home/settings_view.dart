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

const String btcsDisclaimerTitle = 'Disclaimer: ';
const String btcsDisclaimerSummaryText =
  'Silver Wallet is self-custodial software provided for technical and informational use. It is provided "as is" without warranties.';
const String btcsDisclaimerResponsibilityText =
  'You are solely responsible for protecting your seed phrase and WIF private key, and for complying with local laws and tax obligations.';
const String btcsDisclaimerText =
  'BTCS (Bitcoin Silver) is a fully decentralized, open-source cryptocurrency based on the Proof-of-Work algorithm. There is no corporate entity, no pre-sale and no developer allocation. This website is for technical and informational purposes only. The software is provided "as is", without warranty of any kind. Users are solely responsible for securing their private keys and seed phrases and for complying with applicable local laws and tax regulations. BTCS does not constitute a crypto-asset service under EU Regulation 2023/1114 (MiCA).';
const String _pendingMigrationInterruptedNoticeKey =
    'pending_migration_interrupted_notice';

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
    _consumePendingMigrationInterruptedNotice();
  }

  Future<void> _markPendingMigrationInterruptedNotice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pendingMigrationInterruptedNoticeKey, true);
  }

  Future<void> _consumePendingMigrationInterruptedNotice() async {
    final prefs = await SharedPreferences.getInstance();
    final shouldShow = prefs.getBool(_pendingMigrationInterruptedNoticeKey) ?? false;
    if (!shouldShow) return;

    await prefs.remove(_pendingMigrationInterruptedNoticeKey);
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showMigrationInterruptedDialog(context);
    });
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
    final acknowledged = await _showMigrationWarningDialog(context);
    if (acknowledged != true) {
      return;
    }

    int migrationSeedWords = 12;

    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
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

    if (confirmed != true) return;
    if (!context.mounted) return;

    BuildContext? preparingDialogContext;
    final preparingMessage = ValueNotifier<String>('Preparing migration...');
    bool preparingMessageDisposed = false;

    void disposePreparingMessageIfNeeded() {
      if (preparingMessageDisposed) return;
      preparingMessage.dispose();
      preparingMessageDisposed = true;
    }

    void closePreparingDialogIfOpen() {
      final dialogContext = preparingDialogContext;
      if (dialogContext == null) return;

      try {
        Navigator.of(dialogContext).pop();
      } catch (_) {
        // If already closed, ignore.
      } finally {
        preparingDialogContext = null;
        disposePreparingMessageIfNeeded();
      }
    }

    Future<void> setPreparingStage(
      String message, {
      int minVisibleMs = 220,
    }) async {
      if (preparingMessageDisposed) return;
      preparingMessage.value = message;
      await Future<void>.delayed(Duration(milliseconds: minVisibleMs));
    }

    showDialog(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (dialogContext) {
        preparingDialogContext = dialogContext;
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          content: ValueListenableBuilder<String>(
            valueListenable: preparingMessage,
            builder: (context, message, _) {
              return Row(
                children: [
                  const CircularProgressIndicator(color: Colors.cyanAccent),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 80));

    try {
      // Safety pre-checks before generating migration wallet data.
      await setPreparingStage('Refreshing wallet balance...', minVisibleMs: 220);
      await wp.refreshBalance();
      if (!context.mounted) return;

      if (wp.hasPendingTransactions) {
        closePreparingDialogIfOpen();
        await _showMigrationPendingDialog(context, wp.pendingTransactionsCount);
        return;
      }

      final currentBalance = wp.balance ?? 0.0;
      if (currentBalance > 0.00001) {
        await setPreparingStage('Checking network fee estimate...', minVisibleMs: 240);
        final smartFeeAvailable = await wp.fetchFeeRate();
        if (!context.mounted) return;

        if (!smartFeeAvailable) {
          closePreparingDialogIfOpen();
          await _showSmartFeeUnavailableDialog(context, wp.feeEstimateError);
          return;
        }
      }

      // Generate new wallet first and let user review/save it before sending.
      await setPreparingStage('Generating new seed wallet...', minVisibleMs: 300);
      final walletData = await wp.walletService.generateNewSeedWallet(words: migrationSeedWords);
      final newAddress = walletData['address'] ?? '';
      final newPrivateKey = walletData['privateKey'] ?? '';
      final newMnemonic = walletData['mnemonic'] ?? '';

      final derived = wp.walletService.loadAddressFromKey(newPrivateKey);
      if (newAddress.isEmpty || newPrivateKey.isEmpty || derived == null || derived != newAddress) {
        closePreparingDialogIfOpen();
        await _showMigrationFailedDialog(
          context,
          'Generated migration wallet failed integrity checks. Please retry migration.',
        );
        return;
      }

      closePreparingDialogIfOpen();

      final continueWithSend = await _showMigrationPreparedWalletDialog(
        context,
        newAddress: newAddress,
        privateKey: newPrivateKey,
        mnemonic: newMnemonic,
        amountToSend: currentBalance,
      );

      if (!context.mounted) {
        await _markPendingMigrationInterruptedNotice();
        return;
      }

      if (continueWithSend != true) {
        await _showMigrationCancelledDialog(context);
        return;
      }

      // If this route is no longer active (e.g., app backgrounded and navigation changed),
      // abort migration flow to avoid continuing from a stale context.
      if (!(ModalRoute.of(context)?.isCurrent ?? false)) {
        await _showMigrationInterruptedDialog(context);
        return;
      }

      // Keep old wallet active unless everything below succeeds.
      BuildContext? progressDialogContext;
      final progressMessage = ValueNotifier<String>('Preparing migration...');
      bool progressMessageDisposed = false;

      void disposeProgressMessageIfNeeded() {
        if (progressMessageDisposed) return;
        progressMessage.dispose();
        progressMessageDisposed = true;
      }

      void closeProgressDialogIfOpen() {
        final dialogContext = progressDialogContext;
        if (dialogContext == null) return;

        try {
          Navigator.of(dialogContext).pop();
        } catch (_) {
          // If the dialog is already closed, ignore.
        } finally {
          progressDialogContext = null;
          disposeProgressMessageIfNeeded();
        }
      }

      Future<void> setProgressStage(
        String message, {
        int minVisibleMs = 220,
      }) async {
        if (progressMessageDisposed) return;
        progressMessage.value = message;
        await Future<void>.delayed(Duration(milliseconds: minVisibleMs));
      }

      showDialog(
        context: context,
        useRootNavigator: false,
        barrierDismissible: false,
        builder: (dialogContext) {
          progressDialogContext = dialogContext;
          return AlertDialog(
            backgroundColor: Color(0xFF1A1A1A),
            content: ValueListenableBuilder<String>(
              valueListenable: progressMessage,
              builder: (context, message, _) {
                return Row(
                  children: [
                    const CircularProgressIndicator(color: Colors.cyanAccent),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      );

      // Give the dialog one frame to render before starting async migration work,
      // so users reliably see stage updates.
      await Future<void>.delayed(const Duration(milliseconds: 80));

      try {
        await setProgressStage('Checking secure storage...', minVisibleMs: 240);

        final storageReady = await wp.runMigrationStoragePreflight();
        if (!storageReady) {
          throw Exception(wp.lastError ?? 'Secure storage is unavailable.');
        }

        Map<String, dynamic> sweepResult = {'success': true};

        if (currentBalance > 0.00001) {
          await setProgressStage('Sending migration transaction...', minVisibleMs: 260);

          sweepResult = await wp.sendTransaction(
            newAddress,
            currentBalance,
            feeRate: wp.feeRate,
            preferBatchSend: true,
            isSweep: true,
          );

          if (sweepResult['success'] != true) {
            throw Exception((sweepResult['message'] ?? 'Sweep failed').toString());
          }

          final txid = (sweepResult['txid'] ?? '').toString();
          final batchTxids = (sweepResult['batchTxids'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .where((id) => id.isNotEmpty)
              .toList();
          final primaryTxid = txid.isNotEmpty
              ? txid
              : (batchTxids.isNotEmpty ? batchTxids.first : '');
          await setProgressStage(
            primaryTxid.isNotEmpty
                ? 'Transaction broadcast (${primaryTxid.substring(0, 8)}...). Finalizing migration...'
                : 'Transaction broadcast. Finalizing migration...',
            minVisibleMs: 320,
          );
        } else {
          await setProgressStage('No sweep needed. Finalizing migration...', minVisibleMs: 320);
        }

        await setProgressStage('Saving new wallet...', minVisibleMs: 220);
        await wp.saveWallet(newAddress, newPrivateKey, mnemonic: newMnemonic);

        await setProgressStage('Refreshing wallet balance...', minVisibleMs: 220);
        await wp.refreshBalance();

        await setProgressStage('Loading updated transaction history...', minVisibleMs: 220);
        await bp.loadBlockchain(newAddress);

        closeProgressDialogIfOpen();
        if (!context.mounted) return;

        await _showMigrationTxSuccessDialog(
          context,
          txid: (() {
            final singleTxid = (sweepResult['txid'] ?? '').toString();
            if (singleTxid.isNotEmpty) return singleTxid;
            final batchTxids = (sweepResult['batchTxids'] as List<dynamic>? ?? [])
                .map((e) => e.toString())
                .where((id) => id.isNotEmpty)
                .toList();
            return batchTxids.isNotEmpty ? batchTxids.first : '';
          })(),
          newAddress: newAddress,
          amount: currentBalance,
        );

        if (!context.mounted) return;

        final backupConfirmed = await _showMigrationPostSuccessBackupDialog(
          context,
          newAddress: newAddress,
          privateKey: newPrivateKey,
          mnemonic: newMnemonic,
        );

        if (backupConfirmed != true || !context.mounted) {
          return;
        }

        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Migration complete. New wallet loaded.'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        closeProgressDialogIfOpen();
        if (context.mounted) {
          await _showMigrationFailedDialog(context, e.toString());
        }
        return;
      } finally {
        disposeProgressMessageIfNeeded();
      }
    } catch (e) {
      closePreparingDialogIfOpen();
      if (!context.mounted) return;
      await _showMigrationFailedDialog(context, e.toString());
    } finally {
      disposePreparingMessageIfNeeded();
    }
  }

  String _formatMigrationBackupData({
    required String newAddress,
    required String privateKey,
    required String mnemonic,
    double? plannedSweepAmountBtcs,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('Bitcoin Silver Wallet - Migration Backup');
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln('');
    buffer.writeln('New Address:');
    buffer.writeln(newAddress);
    buffer.writeln('');
    if (mnemonic.isNotEmpty) {
      buffer.writeln('Seed Phrase:');
      buffer.writeln(mnemonic);
      buffer.writeln('');
    }
    buffer.writeln('Private Key (WIF):');
    buffer.writeln(privateKey);
    if (plannedSweepAmountBtcs != null) {
      buffer.writeln('');
      buffer.writeln('Planned Sweep Amount (BTCS):');
      buffer.writeln(plannedSweepAmountBtcs.toStringAsFixed(8));
    }
    return buffer.toString();
  }

  Future<void> _copyMigrationBackupData(
    BuildContext context, {
    required String newAddress,
    required String privateKey,
    required String mnemonic,
    double? plannedSweepAmountBtcs,
  }) async {
    final payload = _formatMigrationBackupData(
      newAddress: newAddress,
      privateKey: privateKey,
      mnemonic: mnemonic,
      plannedSweepAmountBtcs: plannedSweepAmountBtcs,
    );

    await Clipboard.setData(ClipboardData(text: payload));
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Migration backup data copied to clipboard'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<bool?> _showMigrationPreparedWalletDialog(
    BuildContext context, {
    required String newAddress,
    required String privateKey,
    required String mnemonic,
    required double amountToSend,
  }) async {
    bool hasSaved = false;

    return showDialog<bool>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: const Row(
                children: [
                  Icon(Icons.verified_user, color: Colors.cyanAccent),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Review New Seed Wallet',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      amountToSend > 0.00001
                          ? 'The app generated a new wallet. Save it now, then confirm sending ${amountToSend.toStringAsFixed(8)} BTCS to this new address.'
                          : 'The app generated a new wallet. Save it now and confirm loading this wallet.',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    const Text('New Address', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    SelectableText(
                      newAddress,
                      style: const TextStyle(color: Colors.white60, fontFamily: 'monospace', fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    if (mnemonic.isNotEmpty) ...[
                      const Text('Seed Phrase', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      SelectableText(
                        mnemonic,
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const Text('Private Key (WIF)', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    SelectableText(
                      privateKey,
                      style: const TextStyle(color: Colors.white60, fontFamily: 'monospace', fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _copyMigrationBackupData(
                          dialogContext,
                          newAddress: newAddress,
                          privateKey: privateKey,
                          mnemonic: mnemonic,
                          plannedSweepAmountBtcs: amountToSend,
                        ),
                        icon: const Icon(Icons.copy, size: 16, color: Colors.cyanAccent),
                        label: const Text(
                          'Copy All Backup Data',
                          style: TextStyle(color: Colors.cyanAccent),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (amountToSend > 0.00001)
                      Text(
                        'Planned sweep amount: ${amountToSend.toStringAsFixed(8)} BTCS',
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                      ),
                    const SizedBox(height: 8),
                    const Text(
                      'Important: complete migration in one go. Avoid switching apps, locking the screen, or navigating away until migration finishes.',
                      style: TextStyle(color: Colors.redAccent, fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: hasSaved,
                      onChanged: (value) {
                        setState(() {
                          hasSaved = value ?? false;
                        });
                      },
                      activeColor: Colors.cyanAccent,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'I saved the new seed phrase/private key and want to continue.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: hasSaved ? () => Navigator.of(dialogContext).pop(true) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                  ),
                  child: Text(amountToSend > 0.00001 ? 'Continue & Send' : 'Load New Wallet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showMigrationInterruptedDialog(BuildContext context) async {
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orangeAccent),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Migration Interrupted',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Migration could not continue because app context changed in the middle of the flow.',
              style: TextStyle(color: Colors.white70),
            ),
            SizedBox(height: 12),
            Text(
              'Please retry migration in one continuous session and avoid switching apps or opening other screens until it completes.',
              style: TextStyle(color: Colors.redAccent, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('OK, I Will Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMigrationCancelledDialog(BuildContext context) async {
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.cyanAccent),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Migration Cancelled',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: const Text(
          'Migration was cancelled before sending. If you want to continue, please start migration again and complete it in one go.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showMigrationPostSuccessBackupDialog(
    BuildContext context, {
    required String newAddress,
    required String privateKey,
    required String mnemonic,
  }) async {
    bool hasSaved = false;

    return showDialog<bool>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color.fromARGB(255, 25, 25, 25),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Backup Required',
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
                      'Migration succeeded. Before continuing, confirm you saved the new wallet recovery details.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'New Address',
                      style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      newAddress,
                      style: const TextStyle(color: Colors.white60, fontFamily: 'monospace', fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    if (mnemonic.isNotEmpty) ...[
                      const Text(
                        'Seed Phrase',
                        style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        mnemonic,
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const Text(
                      'Private Key (WIF)',
                      style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      privateKey,
                      style: const TextStyle(color: Colors.white60, fontFamily: 'monospace', fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _copyMigrationBackupData(
                          dialogContext,
                          newAddress: newAddress,
                          privateKey: privateKey,
                          mnemonic: mnemonic,
                        ),
                        icon: const Icon(Icons.copy, size: 16, color: Colors.orangeAccent),
                        label: const Text(
                          'Copy All Backup Data',
                          style: TextStyle(color: Colors.orangeAccent),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: hasSaved,
                      onChanged: (value) {
                        setState(() {
                          hasSaved = value ?? false;
                        });
                      },
                      activeColor: Colors.orangeAccent,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'I saved my new seed phrase and private key securely.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: hasSaved ? () => Navigator.of(dialogContext).pop(true) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasSaved ? Colors.orangeAccent : Colors.grey,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('I Saved It - Continue'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showMigrationTxSuccessDialog(
    BuildContext context, {
    required String txid,
    required String newAddress,
    required double amount,
  }) async {
    final hasSweepTx = amount > 0.00001;

    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.greenAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasSweepTx ? 'Migration Transaction Sent' : 'Migration Complete',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasSweepTx
                  ? 'Funds were sent to your new seed wallet. The new wallet is now loaded.'
                  : 'No funds needed to be moved. Your new seed wallet is now loaded.',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 10),
            const Text('New Address', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            SelectableText(
              newAddress,
              style: const TextStyle(color: Colors.white60, fontFamily: 'monospace', fontSize: 12),
            ),
            if (txid.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Transaction ID', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              SelectableText(
                txid,
                style: const TextStyle(color: Colors.white60, fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMigrationPendingDialog(BuildContext context, int pendingCount) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Row(
          children: [
            Icon(Icons.schedule, color: Colors.amberAccent),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Migration Delayed',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have $pendingCount pending transaction${pendingCount == 1 ? '' : 's'}. Migration is temporarily blocked until they finish confirming or clear from the mempool.',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            const Text(
              'This avoids changing the wallet address while unconfirmed activity is still being tracked.',
              style: TextStyle(color: Colors.orangeAccent, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amberAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMigrationFailedDialog(BuildContext context, String? error) async {
    final message = (error != null && error.trim().isNotEmpty)
        ? error.trim()
        : 'Migration failed due to an unexpected error. Your current wallet was not replaced.';

    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Migration Failed',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Seed migration could not be completed. Your existing wallet remains active.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            const Text(
              'Reason:',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
              ),
              child: Text(
                message,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showMigrationWarningDialog(BuildContext context) async {
    bool acknowledged = false;

    return showDialog<bool>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Confirm Migration',
                      style: TextStyle(color: Colors.white, fontSize: 18),
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
                      'Migration will create a brand-new wallet and move your funds to a new address.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Important:',
                      style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• Your wallet address will change\n'
                      '• Any balance will be swept to the new address\n'
                      '• Fees may apply\n'
                      '• You must back up the new seed phrase and private key immediately',
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      value: acknowledged,
                      onChanged: (value) {
                        setState(() {
                          acknowledged = value ?? false;
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      activeColor: Colors.cyanAccent,
                      title: const Text(
                        'I understand my wallet address will change and I will back up the new wallet immediately.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: acknowledged ? () => Navigator.of(dialogContext).pop(true) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Agree & Continue'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showSmartFeeUnavailableDialog(BuildContext context, String? feeError) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Migration Temporarily Unavailable',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Smart fee is not initialized yet from node, so the app cannot safely sweep funds during migration.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            const Text(
              'Please wait for a few more blocks and try again.',
              style: TextStyle(color: Colors.orangeAccent, fontStyle: FontStyle.italic),
            ),
            if (feeError != null && feeError.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Node response:',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.35)),
                ),
                child: Text(
                  feeError,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDisclaimerDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Row(
          children: [
            Icon(Icons.policy_outlined, color: Colors.cyanAccent),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                btcsDisclaimerTitle,
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                btcsDisclaimerSummaryText,
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 10),
              const Text(
                btcsDisclaimerResponsibilityText,
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12.5, height: 1.35),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.18)),
                ),
                child: const Text(
                  btcsDisclaimerText,
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 11.5,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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
                    Material(
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
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
                  Material(
                    color: Colors.white.withValues(alpha: 0.05),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
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
                      'Disclaimer',
                      style: TextStyle(color: Colors.white),
                    ),
                    leading: const Icon(Icons.policy_outlined, color: Colors.white),
                    onTap: () => _showDisclaimerDialog(context),
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
