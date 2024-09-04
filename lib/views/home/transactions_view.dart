import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:bitcoinsilver_wallet/providers/transaction_provider.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/views/home/transaction/receive_view.dart';
import 'package:bitcoinsilver_wallet/views/home/transaction/send_view.dart';
import 'package:bitcoinsilver_wallet/widgets/transaction_widget.dart';
import 'package:bitcoinsilver_wallet/modals/transaction_modal.dart';

class TransactionsView extends StatefulWidget {
  const TransactionsView({super.key});

  @override
  State<TransactionsView> createState() => _TransactionsViewState();
}

class _TransactionsViewState extends State<TransactionsView> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_scrollListener);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final transactionProvider =
          Provider.of<TransactionProvider>(context, listen: false);
      final walletProvider =
          Provider.of<WalletProvider>(context, listen: false);
      final address = walletProvider.address;

      if (address != null) {
        transactionProvider.fetchTransactions(address);
      } else {
        // Handle case where address is null, if necessary
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No wallet address found.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });
  }

  void _scrollListener() {
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent) {
      final transactionProvider =
          Provider.of<TransactionProvider>(context, listen: false);
      final walletProvider =
          Provider.of<WalletProvider>(context, listen: false);
      final address = walletProvider.address;

      if (address != null &&
          transactionProvider.hasMore &&
          !transactionProvider.isLoading) {
        transactionProvider.fetchTransactions(address);
      }
    }
  }

  Future<void> _onRefresh() async {
    final transactionProvider =
        Provider.of<TransactionProvider>(context, listen: false);
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final address = walletProvider.address;

    if (address != null) {
      transactionProvider.clearTransactions();
      await transactionProvider.fetchTransactions(address);
    } else {
      // Handle case where address is null, if necessary
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
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
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              controller: _scrollController,
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
                ...transactionProvider.transactions.map((tx) => TransactionTile(
                      tx: tx,
                      onTap: () => _showTransactionDetails(tx.txid),
                    )),
                if (transactionProvider.isLoading)
                  const SizedBox(
                    height: 100,
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
