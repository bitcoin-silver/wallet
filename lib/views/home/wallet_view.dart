import 'package:bitcoinsilver_wallet/widgets/transaction_widget.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/providers/blockchain_provider.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/views/home/receive_view.dart';
import 'package:bitcoinsilver_wallet/views/home/send_view.dart';
import 'package:bitcoinsilver_wallet/widgets/button_widget.dart';
import 'package:bitcoinsilver_wallet/modals/transaction_modal.dart';
import 'package:bitcoinsilver_wallet/views/home/transactions_view.dart';

class WalletView extends StatefulWidget {
  const WalletView({super.key});

  @override
  State<WalletView> createState() => _WalletViewState();
}

class _WalletViewState extends State<WalletView> {
  Future<void> _onRefresh() async {
    final wp = Provider.of<WalletProvider>(context, listen: false);
    final bp = Provider.of<BlockchainProvider>(context, listen: false);
    await bp.loadBlockchain(wp.address);
  }

  void _showTransactionDetails(String txid) {
    showModalBottomSheet(
      context: context,
      builder: (context) => TransactionModal(txid: txid),
    );
  }

  List<FlSpot> _generateDataPoints(List<dynamic> transactions) {
    final reversedTransactions = transactions.reversed.toList();
    if (reversedTransactions.isEmpty) {
      return [
        const FlSpot(0.0, 0.0),
        const FlSpot(1.0, 0.0),
      ];
    }

    return [
      const FlSpot(0.0, 0.0),
      ...reversedTransactions.asMap().entries.map((entry) {
        final index = entry.key;
        final transaction = entry.value;
        return FlSpot(
          (index + 1).toDouble(),
          double.parse(transaction['balance'].toString()),
        );
      }),
    ];
  }

  LineChartData _buildChartData(List<dynamic> transactions, double? balance) {
    final maxX = transactions.isNotEmpty ? transactions.length.toDouble() : 1.0;
    final maxY = balance != null ? (balance * 1.1) : 1.0;
    return LineChartData(
      borderData: FlBorderData(show: false),
      backgroundColor: Colors.transparent,
      minX: 0.0,
      maxX: maxX,
      minY: 0.0,
      maxY: maxY,
      lineBarsData: [
        LineChartBarData(
          spots: _generateDataPoints(transactions),
          isCurved: false,
          color: Colors.cyanAccent,
          barWidth: 2,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            color: Colors.cyanAccent.withOpacity(0.3),
          ),
        ),
      ],
      gridData: const FlGridData(show: false),
      titlesData: const FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        rightTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blockchainProvider = Provider.of<BlockchainProvider>(context);

    // Extrahiere die relevanten Daten aus dem Provider
    final String timestamp = blockchainProvider.timestamp;
    final List<dynamic> transactions = blockchainProvider.transactions;
    final double? balance =
        transactions.isNotEmpty ? transactions[0]['balance'].toDouble() : 0.0;
    final double price = blockchainProvider.price;
    final String? balanceInUSD =
        balance != null ? (balance * price).toStringAsFixed(2) : null;

    return Scaffold(
      body: RefreshIndicator(
        backgroundColor: const Color.fromARGB(255, 25, 25, 25),
        color: Colors.cyanAccent,
        onRefresh: _onRefresh,
        child: SingleChildScrollView(
          physics:
              const AlwaysScrollableScrollPhysics(), // Ermöglicht das Ziehen, auch wenn der Inhalt nicht scrollt
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
                padding: const EdgeInsets.only(top: 50, bottom: 20),
                child: Column(
                  children: [
                    if (blockchainProvider.isLoading)
                      const SizedBox(
                        height: 100,
                        child: Center(
                            child: CircularProgressIndicator(
                          color: Colors.white,
                        )),
                      )
                    else ...[
                      // Balance-Anzeige
                      Column(
                        children: [
                          const SizedBox(height: 20),
                          Text(
                            balanceInUSD != null ? '\$$balanceInUSD' : '-',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            balance != null ? '$balance' : '-',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const Text(
                            'BTCS',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          // Diagramm
                          SizedBox(
                            height: 250,
                            child: LineChart(
                                _buildChartData(transactions, balance)),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Synchronized: $timestamp',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                      // Buttons: Send und Receive
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
                                      builder: (context) => const SendView()),
                                );
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
                                          const ReceiveView()),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      // Transaktionsliste
                      Column(
                        children: [
                          if (transactions.isEmpty)
                            const SizedBox(
                              height: 100,
                              child: Center(
                                child: Text(
                                  'No transactions found',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ),
                            ),
                          if (transactions.isNotEmpty)
                            const Text('Recent transactions',
                                style: TextStyle(color: Colors.white54)),
                          ...transactions.take(5).map((tx) => TransactionTile(
                                tx: tx,
                                onTap: () =>
                                    _showTransactionDetails(tx['txid']),
                              )),
                          if (transactions.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: ButtonWidget(
                                text: 'Show all',
                                isPrimary: true,
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            const TransactionsView()),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
