import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:bitcoinsilver_wallet/providers/transaction_provider.dart';

class BalanceWidget extends StatefulWidget {
  const BalanceWidget({super.key});

  @override
  State<BalanceWidget> createState() => BalanceWidgetState();
}

class BalanceWidgetState extends State<BalanceWidget> {
  List<dynamic> _transactions = [];
  double? _reactiveBalance = 0.0;
  double? _originalBalance;
  double? _balance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      updateBalance();
    });
  }

  void updateBalance() {
    final transactionProvider =
        Provider.of<TransactionProvider>(context, listen: false);
    if (mounted) {
      setState(() {
        _transactions = transactionProvider.transactions;
        _originalBalance =
            _transactions.isNotEmpty ? _transactions[0]['balance'] : 0.0;
        _balance = _originalBalance;
        _reactiveBalance = _balance;
      });
    }
  }

  List<FlSpot> _generateDataPoints() {
    final reversedTransactions = _transactions.reversed.toList();
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

  LineChartData _buildChartData() {
    final maxX =
        _transactions.isNotEmpty ? (_transactions.length).toDouble() : 1.0;
    final maxY = _balance != null ? (_balance! * 1.1) : 1.0;
    return LineChartData(
      borderData: FlBorderData(show: false),
      backgroundColor: Colors.transparent,
      minX: 0.0,
      maxX: maxX,
      minY: 0.0,
      maxY: maxY,
      lineBarsData: [
        LineChartBarData(
          spots: _generateDataPoints(),
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
    return Column(
      children: [
        const SizedBox(height: 50),
        Text(
          '$_reactiveBalance',
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
        const SizedBox(height: 50),
        SizedBox(height: 250, child: LineChart(_buildChartData())),
      ],
    );
  }
}
