import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/services/wallet_service.dart';

class RecoveryModal extends StatefulWidget {
  const RecoveryModal({super.key});

  @override
  State<RecoveryModal> createState() => _RecoveryModalState();
}

class _RecoveryModalState extends State<RecoveryModal> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final TextEditingController _privateKeyController = TextEditingController();
  String _errorMessage = '';

  Future<void> _recoverWallet() async {
    final privateKey = _privateKeyController.text.trim();

    if (privateKey.isEmpty || privateKey.length != 52) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Invalid private key. Must be 52 characters long.';
        });
      }
      return;
    }

    try {
      final walletService = WalletService();
      final address = walletService.recoverAddressFromWif(privateKey);

      if (address == null) {
        if (mounted) {
          setState(() {
            _errorMessage =
                'Failed to recover address. Please check the private key.';
          });
        }
      } else {
        await _storage.write(key: 'wifPrivateKey', value: privateKey);
        await _loadWallet();

        if (mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'Error recovering wallet. Please check the private key.';
        });
      }
    }
  }

  Future<void> _loadWallet() async {
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    await walletProvider.loadWallet();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _privateKeyController,
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
            ),
            style: const TextStyle(color: Colors.white),
            obscureText: true,
          ),
          const SizedBox(height: 20),
          if (_errorMessage.isNotEmpty)
            Text(
              _errorMessage,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 20),
          const Text(
            'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.',
            style: TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _recoverWallet,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF333333),
            ),
            child: const Text(
              'Recover',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
