import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/providers/transaction_provider.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/views/home/transaction/receive_view.dart';
import 'package:bitcoinsilver_wallet/views/home/transaction/send_view.dart';
import 'package:bitcoinsilver_wallet/widgets/balance_widget.dart';
import 'package:bitcoinsilver_wallet/widgets/button_widget.dart';
import 'package:bitcoinsilver_wallet/widgets/transaction_widget.dart';
import 'package:bitcoinsilver_wallet/modals/transaction_modal.dart';

class WalletView extends StatefulWidget {
  const WalletView({super.key});

  @override
  State<WalletView> createState() => _WalletViewState();
}

class _WalletViewState extends State<WalletView> {
  final GlobalKey<BalanceWidgetState> _balanceKey =
      GlobalKey<BalanceWidgetState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onRefresh();
    });
  }

  Future<void> _onRefresh() async {
    final transactionProvider =
        Provider.of<TransactionProvider>(context, listen: false);
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final address = walletProvider.address;
    if (address != null) {
      final DateTime now = DateTime.now();
      final String formattedDate =
          DateFormat('dd MMM yyyy HH:mm:ss').format(now);
      await transactionProvider.fetchTransactions(address);
      _balanceKey.currentState?.updateBalance(
          timestamp: formattedDate,
          transactions: transactionProvider.transactions,
          price: transactionProvider.price);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No wallet address found.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showTransactionDetails(String txid) {
    showModalBottomSheet(
      context: context,
      builder: (context) => TransactionModal(txid: txid),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transactionProvider = Provider.of<TransactionProvider>(context);

    return Scaffold(
      body: RefreshIndicator(
        backgroundColor: const Color.fromARGB(255, 25, 25, 25),
        color: Colors.cyanAccent,
        onRefresh: _onRefresh,
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  kBottomNavigationBarHeight,
            ),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color.fromARGB(255, 0, 75, 75), Colors.black],
                  stops: [0, 0.75],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 50),
                child: Column(children: [
                  if (transactionProvider.isLoading)
                    const SizedBox(
                      height: 100,
                      child: Center(
                          child:
                              CircularProgressIndicator(color: Colors.white)),
                    ),
                  if (!transactionProvider.isLoading) ...[
                    BalanceWidget(key: _balanceKey),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ButtonWidget(
                            text: 'Send',
                            isPrimary: true,
                            icon: Icons.arrow_upward,
                            onPressed: () {
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => const SendView()));
                            },
                          ),
                          const SizedBox(width: 10),
                          ButtonWidget(
                            text: 'Receive',
                            isPrimary: true,
                            icon: Icons.arrow_downward,
                            onPressed: () {
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          const ReceiveView()));
                            },
                          ),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        if (transactionProvider.transactions.isEmpty &&
                            !transactionProvider.isLoading)
                          const SizedBox(
                            height: 100,
                            child: Center(
                              child: Text(
                                'No transactions found',
                                style: TextStyle(color: Colors.white54),
                              ),
                            ),
                          ),
                        if (transactionProvider.transactions.isNotEmpty &&
                            !transactionProvider.isLoading)
                          const Text('Recent transactions',
                              style: TextStyle(color: Colors.white54)),
                        ...transactionProvider.transactions
                            .take(2)
                            .map((tx) => TransactionTile(
                                  tx: tx,
                                  onTap: () =>
                                      _showTransactionDetails(tx['txid']),
                                )),
                      ],
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
