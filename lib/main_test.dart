import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => WalletProvider(),
      child: MaterialApp(
        title: 'Bitcoin Silver Wallet',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: const WalletHomePage(),
      ),
    );
  }
}

class WalletHomePage extends StatelessWidget {
  const WalletHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final walletProvider = Provider.of<WalletProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet Dashboard'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Address: ${walletProvider.address ?? 'Loading...'}'),
            const SizedBox(height: 8),
            Text('Private Key: ${walletProvider.privateKey ?? 'Loading...'}'),
            const SizedBox(height: 8),
            Text(
                'Balance: ${walletProvider.balance != null ? walletProvider.balance!.toStringAsFixed(8) : 'Loading...'} BTC'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                await walletProvider.fetchUtxos();
              },
              child: const Text('Refresh UTXOs'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                if (walletProvider.utxos != null &&
                    walletProvider.utxos!.isNotEmpty) {
                  await walletProvider.sendTransaction(
                      'bs1q6q5atydhzfglamz869mpj0qrp3m2gt6vp46m7q',
                      0.000005); // Beispielwert für Betrag
                }
              },
              child: const Text('Send Transaction'),
            ),
          ],
        ),
      ),
    );
  }
}
