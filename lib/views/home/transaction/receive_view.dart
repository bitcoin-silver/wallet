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
        const SnackBar(content: Text('Adresse kopiert!')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor:
            const Color(0xFF333333), // Gleiche Farbe wie der Hintergrund
        elevation: 0, // Keine Schatten
        title: const Text(
          'Receive',
          style: TextStyle(color: Colors.white, fontSize: 20), // Weißer Text
        ),
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back, color: Colors.white), // Weißes Icon
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        centerTitle: true, // Text zentrieren
      ),
      body: Container(
        color: const Color(0xFF333333), // Setze den Hintergrund der View
        padding: const EdgeInsets.symmetric(
            horizontal: 16.0), // Abstand zu den Bildschirmrändern
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (address != null && address.isNotEmpty)
              QrImageView(
                data: address, // Adresse, die im QR-Code angezeigt wird
                version: QrVersions.auto,
                size: MediaQuery.of(context).size.width -
                    32, // Breite des QR-Codes mit Abstand
                backgroundColor: Colors.white, // Hintergrundfarbe des QR-Codes
              )
            else
              const Text('Address is not available',
                  style: TextStyle(color: Colors.red)),
            const SizedBox(height: 20), // Abstands-Widget für besseren Layout
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
            const SizedBox(height: 20), // Abstands-Widget für besseren Layout
            const Text(
              'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
