import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/widgets/balance_widget.dart';
import 'package:bitcoinsilver_wallet/views/home/transactions_view.dart';

class WalletView extends StatelessWidget {
  const WalletView({super.key});

  @override
  Widget build(BuildContext context) {
    final walletProvider = Provider.of<WalletProvider>(context);
    if (walletProvider.address == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF333333),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF333333),
      body: Column(
        children: [
          const BalanceHeader(), // BalanceHeader Widget
          Expanded(
            child: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TransactionsView(
                        address: walletProvider.address!,
                      ),
                    ),
                  );
                },
                child: const Text('Show transactions'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
