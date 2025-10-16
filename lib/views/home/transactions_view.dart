import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/providers/blockchain_provider.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/widgets/transaction_widget.dart';
import 'package:bitcoinsilver_wallet/widgets/skeleton_loader.dart';
import 'package:bitcoinsilver_wallet/widgets/empty_state.dart';
import 'package:bitcoinsilver_wallet/modals/transaction_modal.dart';
import 'package:bitcoinsilver_wallet/views/home/receive_view.dart';

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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
      // Show feedback message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                ),
              ),
              SizedBox(width: 12),
              Text('Checking for new transactions...'),
            ],
          ),
          backgroundColor: Colors.black87,
          duration: Duration(seconds: 2),
        ),
      );

      // Use loadBlockchain to reset pagination and fetch from beginning
      await bp.loadBlockchain(address);

      // Show completion message
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 18),
                SizedBox(width: 12),
                Text('Transactions updated'),
              ],
            ),
            backgroundColor: Colors.black87,
            duration: Duration(seconds: 1),
          ),
        );
      }
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
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.6,
                      child: EmptyState(
                        icon: Icons.history,
                        title: 'No Transaction History',
                        message: 'Your transaction history will appear here once you start using your wallet',
                        actionText: 'Receive BTCS',
                        onAction: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ReceiveView(),
                            ),
                          );
                        },
                      ),
                    ),
                  ...bp.transactions.map((tx) => TransactionTile(
                        tx: tx,
                        onTap: () => _showTransactionDetails(tx['txid']),
                      )),
                  if (bp.isLoading && bp.transactions.isEmpty)
                    // Show skeleton loaders for initial load
                    ...List.generate(5, (index) => const TransactionSkeleton())
                  else if (bp.isLoading)
                    // Show spinner for loading more
                    const SizedBox(
                      height: 100,
                      child: Center(
                          child:
                              CircularProgressIndicator(color: Colors.cyanAccent)),
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
