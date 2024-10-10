import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/providers/blockchain_provider.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
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
  }

  void _scrollListener() {
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent) {
      final bp = Provider.of<BlockchainProvider>(context, listen: false);
      final wp = Provider.of<WalletProvider>(context, listen: false);
      final address = wp.address;
      if (address != null && bp.hasMore && !bp.isLoading) {
        bp.fetchTransactions(address);
      }
    }
  }

  Future<void> _onRefresh() async {
    final bp = Provider.of<BlockchainProvider>(context, listen: false);
    final wp = Provider.of<WalletProvider>(context, listen: false);
    final address = wp.address;
    if (address != null) {
      await bp.fetchTransactions(address);
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
    final bp = Provider.of<BlockchainProvider>(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Transactions',
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
                  colors: [Colors.black, Colors.black],
                  stops: [0, 0.75],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                children: [
                  if (bp.transactions.isEmpty && !bp.isLoading)
                    const SizedBox(
                      height: 100,
                      child: Center(
                        child: Text(
                          'No transactions found',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ),
                  ...bp.transactions.map((tx) => TransactionTile(
                        tx: tx,
                        onTap: () => _showTransactionDetails(tx['txid']),
                      )),
                  if (bp.isLoading)
                    const SizedBox(
                      height: 100,
                      child: Center(
                          child:
                              CircularProgressIndicator(color: Colors.white)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
