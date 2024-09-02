import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/providers/transaction_provider.dart';
import 'package:bitcoinsilver_wallet/widgets/transaction_widget.dart';
import 'package:bitcoinsilver_wallet/modals/transaction_modal.dart';

class TransactionsView extends StatefulWidget {
  final String address;

  const TransactionsView({super.key, required this.address});

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
      transactionProvider.fetchTransactions(widget.address);
    });
  }

  void _scrollListener() {
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent) {
      final transactionProvider =
          Provider.of<TransactionProvider>(context, listen: false);
      if (transactionProvider.hasMore && !transactionProvider.isLoading) {
        transactionProvider.fetchTransactions(widget.address);
      }
    }
  }

  Future<void> _onRefresh() async {
    final transactionProvider =
        Provider.of<TransactionProvider>(context, listen: false);
    transactionProvider.clearTransactions();
    await transactionProvider.fetchTransactions(widget.address);
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
        backgroundColor: const Color(0xFF333333),
        appBar: AppBar(
          backgroundColor: const Color(0xFF333333),
          elevation: 0,
          title: const Text(
            'Transaktionen',
            style: TextStyle(color: Colors.white),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          centerTitle: true,
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(8.0),
                children: [
                  if (transactionProvider.transactions.isEmpty &&
                      !transactionProvider.isLoading)
                    const SizedBox(
                      height: 100,
                      child: Center(
                        child: Text(
                          'Keine Transaktionen vorhanden',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ...transactionProvider.transactions
                      .map((tx) => TransactionTile(
                            tx: tx,
                            onTap: () => _showTransactionDetails(tx.txid),
                          )),
                  if (transactionProvider.isLoading)
                    const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (!transactionProvider.hasMore)
                    const SizedBox(
                      height: 100,
                      child: Center(
                        child:
                            Text('---', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20), // Spacer
            ElevatedButton(
              onPressed: _onRefresh,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                padding: const EdgeInsets.all(12),
              ),
              child: const Text(
                'Refresh',
                style: TextStyle(color: Color(0xFF333333)), // Textfarbe
              ),
            ),
            const SizedBox(height: 20), // Spacer
          ],
        ));
  }
}
