import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';

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
        backgroundColor: Colors.black, // Same color as the background
        elevation: 0, // No shadow
        title: const Text(
          'Receive',
          style: TextStyle(color: Colors.white, fontSize: 20), // White text
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white), // White icon
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        centerTitle: true, // Center the title
      ),
      body: Container(
        color: Colors.black, // Set the background color of the view
        padding: const EdgeInsets.all(16.0), // Padding from screen edges
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (address != null && address.isNotEmpty)
              QrImageView(
                data: address, // Address displayed in the QR code
                version: QrVersions.auto,
                size: MediaQuery.of(context).size.width -
                    32, // Width of the QR code with padding
                backgroundColor:
                    Colors.white, // Background color of the QR code
              )
            else
              const Text('Address is not available',
                  style: TextStyle(color: Colors.red)),
            const SizedBox(height: 20), // Spacer for better layout
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
            const SizedBox(height: 20), // Spacer for better layout
            const Text(
              'To receive cryptocurrency, you can either scan the QR code or use the address displayed above. Simply share this address with the sender to complete the transaction. Make sure to double-check the address before confirming the transfer to ensure that the funds are sent to the correct location.',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}
