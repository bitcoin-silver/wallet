import 'package:flutter/material.dart';

class WalletView extends StatelessWidget {
  const WalletView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet View'),
      ),
      body: const Center(child: Text('Wallet Content')),
    );
  }
}
