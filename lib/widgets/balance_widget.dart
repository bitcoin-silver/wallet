import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';

class BalanceHeader extends StatelessWidget {
  const BalanceHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final walletProvider = Provider.of<WalletProvider>(context);
    final balance = walletProvider.balance;

    return Container(
      color: const Color(0xFF333333),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.cyanAccent,
                  Color(0xFF333333),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            height: 300.0,
            child: Center(
              child: Text(
                '${balance?.toStringAsFixed(2)} BTCS',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
