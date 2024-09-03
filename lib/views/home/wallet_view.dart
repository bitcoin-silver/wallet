import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/views/home/transaction/receive_view.dart';
import 'package:bitcoinsilver_wallet/views/home/transaction/send_view.dart';

class WalletView extends StatefulWidget {
  const WalletView({super.key});

  @override
  State<WalletView> createState() => _WalletViewState();
}

class _WalletViewState extends State<WalletView> {
  @override
  void initState() {
    super.initState();
    _onRefresh();
  }

  Future<void> _onRefresh() async {
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    walletProvider.fetchUtxos();
  }

  @override
  Widget build(BuildContext context) {
    final walletProvider = Provider.of<WalletProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF333333),
      appBar: AppBar(
        backgroundColor: const Color(0xFF333333),
        automaticallyImplyLeading: false,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.arrow_downward, color: Colors.white),
            onPressed: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const ReceiveView()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.arrow_upward, color: Colors.white),
            onPressed: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const SendView()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.sync, color: Colors.white),
            onPressed: () {
              _onRefresh();
            },
          ),
          const SizedBox(width: 16), // Abstand zwischen den Icons
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: walletProvider.balance != null
              ? Text(
                  'Balance: ${walletProvider.balance}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: MediaQuery.of(context).size.width *
                        0.08, // Textgröße proportional zur Bildschirmbreite
                    fontWeight: FontWeight
                        .bold, // Optional: Fettdruck für bessere Sichtbarkeit
                  ),
                  textAlign: TextAlign.center,
                )
              : const Text(
                  'Loading balance...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
        ),
      ),
    );
  }
}
