import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';

class ReceiveView extends StatelessWidget {
  const ReceiveView({super.key});

  @override
  Widget build(BuildContext context) {
    final walletProvider = Provider.of<WalletProvider>(context);
    final address = walletProvider.address;

    void copyToClipboard(String text) {
      Clipboard.setData(ClipboardData(text: text));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Address copied to clipboard!')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Receive',
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        centerTitle: true,
      ),
      body: Container(
        color: Colors.black,
        height: MediaQuery.of(context).size.height,
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (address != null && address.isNotEmpty)
                QrImageView(
                    data: address,
                    version: QrVersions.auto,
                    size: MediaQuery.of(context).size.width - 32,
                    backgroundColor: Colors.white)
              else
                const Text('Address is not available'),
              const SizedBox(height: 20),
              if (address != null && address.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        address,
                        style: const TextStyle(color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: Colors.white),
                      onPressed: () => copyToClipboard(address),
                    ),
                  ],
                ),
              const SizedBox(height: 20),
              const Text(
                'To receive cryptocurrency, you can either scan the QR code or use the address displayed above. Simply share this address with the sender to complete the transaction. Make sure to double-check the address before confirming the transfer to ensure that the funds are sent to the correct location.',
                style: TextStyle(color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
