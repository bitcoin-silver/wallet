import 'dart:async';
import 'package:bitcoinsilver_wallet/widgets/transaction_widget.dart';
import 'package:bitcoinsilver_wallet/widgets/skeleton_loader.dart';
import 'package:bitcoinsilver_wallet/widgets/empty_state.dart';
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
import 'package:bitcoinsilver_wallet/widgets/app_background.dart';

class WalletView extends StatefulWidget {
  const WalletView({super.key});

  @override
  State<WalletView> createState() => _WalletViewState();
}

class _WalletViewState extends State<WalletView> with SingleTickerProviderStateMixin {
  int? _touchedIndex;
  late AnimationController _pendingAnimationController;
  late Animation<double> _pendingAnimation;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _pendingAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _pendingAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pendingAnimationController,
      curve: Curves.easeInOut,
    ));
    _pendingAnimationController.repeat(reverse: true);

    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      final wp = Provider.of<WalletProvider>(context, listen: false);
      if (wp.hasPendingTransactions) {
        wp.fetchUtxos(force: true, silent: true);
      }
    });

  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _pendingAnimationController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    final wp = Provider.of<WalletProvider>(context, listen: false);
    final bp = Provider.of<BlockchainProvider>(context, listen: false);

    // Show feedback message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
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
            const SizedBox(width: 12),
            Text(
              wp.hasPendingTransactions
                  ? 'Checking for confirmations...'
                  : 'Syncing wallet data...',
            ),
          ],
        ),
        backgroundColor: Colors.black87,
        duration: const Duration(seconds: 2),
      ),
    );

    if (wp.hasPendingTransactions) {
      await wp.fetchUtxos(force: true, silent: true); // Use silent mode
    } else {
      await Future.wait([
        wp.fetchUtxos(force: true),
        bp.loadBlockchain(wp.address),
      ]);
    }

    // Show completion message
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 18),
              SizedBox(width: 12),
              Text('Wallet synced'),
            ],
          ),
          backgroundColor: Colors.black87,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _showTransactionDetails(String txid) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color.fromARGB(255, 25, 25, 25),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: TransactionModal(txid: txid),
      ),
    );
  }

  List<FlSpot> _generateDataPoints(List<dynamic> transactions) {
    if (transactions.isEmpty) {
      // Show a flat line at current balance or 0
      return [
        const FlSpot(0, 0),
        const FlSpot(1, 0),
      ];
    }

    // Create spots from transactions (reversed to show oldest first)
    final reversedTransactions = transactions.reversed.toList();
    final spots = <FlSpot>[];

    // Start from 0 if we have transactions
    spots.add(const FlSpot(0, 0));

    // Add each transaction as a point
    for (int i = 0; i < reversedTransactions.length; i++) {
      final tx = reversedTransactions[i];
      final balance = tx['balance']?.toDouble() ?? 0.0;
      spots.add(FlSpot(i + 1.0, balance));
    }

    return spots;
  }

  LineChartData _buildChartData(List<dynamic> transactions, double? currentBalance) {
    final spots = _generateDataPoints(transactions);

    // Calculate bounds
    double maxY = currentBalance ?? 1.0;
    if (spots.isNotEmpty) {
      final maxSpotY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
      maxY = maxSpotY > maxY ? maxSpotY : maxY;
    }
    maxY = maxY * 1.1; // Add 10% padding
    if (maxY == 0) maxY = 1; // Ensure we have some height

    final maxX = spots.length > 1 ? spots.length - 1.0 : 1.0;

    return LineChartData(
      backgroundColor: Colors.transparent,

      // Touch behavior
      lineTouchData: LineTouchData(
        enabled: true,
        handleBuiltInTouches: true,
        touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {
          if (event is FlTapUpEvent || event is FlPanUpdateEvent) {
            setState(() {
              if (touchResponse?.lineBarSpots != null &&
                  touchResponse!.lineBarSpots!.isNotEmpty) {
                _touchedIndex = touchResponse.lineBarSpots!.first.spotIndex;
              }
            });
          } else if (event is FlPanEndEvent || event is FlTapCancelEvent) {
            setState(() {
              _touchedIndex = null;
            });
          }
        },
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (spot) => Colors.black87,
          tooltipPadding: const EdgeInsets.all(8),
          tooltipMargin: 8,
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((LineBarSpot touchedSpot) {
              if (touchedSpot.x == 0) {
                return LineTooltipItem(
                  'Starting Point\n',
                  const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  children: [
                    TextSpan(
                      text: '0.00 BTCS',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                );
              }

              final txIndex = touchedSpot.x.toInt() - 1;
              if (txIndex >= 0 && txIndex < transactions.length) {
                final reversedTx = transactions.reversed.toList();
                final tx = reversedTx[txIndex];
                return LineTooltipItem(
                  'Transaction ${txIndex + 1}\n',
                  const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  children: [
                    TextSpan(
                      text: '${touchedSpot.y.toStringAsFixed(4)} BTCS',
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                );
              }

              return LineTooltipItem(
                '${touchedSpot.y.toStringAsFixed(4)} BTCS',
                const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              );
            }).toList();
          },
        ),
        getTouchedSpotIndicator: (barData, spotIndexes) {
          return spotIndexes.map((index) {
            return TouchedSpotIndicatorData(
              FlLine(
                color: Colors.cyanAccent.withOpacity(0.5),
                strokeWidth: 2,
                dashArray: [5, 5],
              ),
              FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) {
                  return FlDotCirclePainter(
                    radius: 5,
                    color: Colors.cyanAccent,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  );
                },
              ),
            );
          }).toList();
        },
      ),

      // Grid
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: maxY / 5,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Colors.white.withOpacity(0.1),
            strokeWidth: 0.5,
          );
        },
      ),

      // Titles
      titlesData: FlTitlesData(
        show: true,
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 45,
            interval: maxY / 5,
            getTitlesWidget: (value, meta) {
              if (value == meta.max) return const SizedBox.shrink();

              String text;
              if (value >= 1000) {
                text = '${(value / 1000).toStringAsFixed(1)}k';
              } else if (value >= 1) {
                text = value.toStringAsFixed(0);
              } else {
                text = value.toStringAsFixed(2);
              }

              return Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.right,
                ),
              );
            },
          ),
        ),
        rightTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
      ),

      // Border
      borderData: FlBorderData(
        show: false,
      ),

      // Min/Max values
      minX: 0,
      maxX: maxX,
      minY: 0,
      maxY: maxY,

      // Line bars
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.3,
          preventCurveOverShooting: true,
          color: Colors.cyanAccent,
          barWidth: 2.5,
          isStrokeCapRound: true,

          // Don't show dots by default, only on touch
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, index) {
              // Only show dot if it's touched or it's the last point
              if (index == _touchedIndex || index == spots.length - 1) {
                return FlDotCirclePainter(
                  radius: 4,
                  color: Colors.cyanAccent,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                );
              }
              return FlDotCirclePainter(
                radius: 0,
                color: Colors.transparent,
              );
            },
          ),

          // Gradient below line
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [
                Colors.cyanAccent.withOpacity(0.3),
                Colors.cyanAccent.withOpacity(0.05),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final blockchainProvider = Provider.of<BlockchainProvider>(context);
    final walletProvider = Provider.of<WalletProvider>(context);

    // Get data from providers
    final String timestamp = blockchainProvider.timestamp;
    final List<dynamic> transactions = blockchainProvider.transactions;

    // Use displayBalance for UI (this shows pending balance when available)
    final double? displayBalance = walletProvider.displayBalance;
    final double? confirmedBalance = walletProvider.balance;
    final bool hasPending = walletProvider.hasPendingTransactions;

    final double price = blockchainProvider.price;
    final String balanceInUSD = displayBalance != null
        ? '\$${(displayBalance * price).toStringAsFixed(2)}'
        : '\$0.00';

    return Scaffold(
      body: RefreshIndicator(
        backgroundColor: const Color.fromARGB(255, 25, 25, 25),
        color: Colors.cyanAccent,
        onRefresh: _onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - kBottomNavigationBarHeight,
            ),
            child: AppBackground(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 20),
                  child: Column(
                    children: [
                      if (blockchainProvider.isLoading || walletProvider.isLoading) ...[
                        const WalletBalanceSkeleton(),
                        // Action Buttons Skeleton
                        Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: SkeletonLoader(
                                  width: double.infinity,
                                  height: 48,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SkeletonLoader(
                                  width: double.infinity,
                                  height: 48,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Transactions Section Skeleton
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonLoader(
                                width: 150,
                                height: 20,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              const SizedBox(height: 12),
                              ...List.generate(3, (index) => const TransactionSkeleton()),
                            ],
                          ),
                        ),
                      ] else ...[
                        // Balance Display
                        Column(
                          children: [
                            const SizedBox(height: 20),

                            // USD Value
                            Text(
                              balanceInUSD,
                              style: TextStyle(
                                color: hasPending ? Colors.orange.withOpacity(0.8) : Colors.white54,
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),

                            const SizedBox(height: 8),

                            // BTCS Balance with pending indicator
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    if (hasPending)
                                      AnimatedBuilder(
                                        animation: _pendingAnimation,
                                        builder: (context, child) {
                                          return Icon(
                                            Icons.access_time,
                                            color: Colors.orange.withOpacity(_pendingAnimation.value),
                                            size: 20,
                                          );
                                        },
                                      ),
                                    if (hasPending) const SizedBox(width: 8),
                                    Text(
                                      displayBalance?.toStringAsFixed(4) ?? '0.0000',
                                      style: TextStyle(
                                        color: hasPending
                                            ? Colors.orange.withOpacity(0.9)
                                            : Colors.white,
                                        fontSize: 36,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'BTCS',
                                      style: TextStyle(
                                        color: hasPending
                                            ? Colors.orange.withOpacity(0.7)
                                            : Colors.white54,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            // Show confirmed balance if different from display balance
                            if (hasPending && confirmedBalance != displayBalance)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Confirmed: ${confirmedBalance?.toStringAsFixed(4) ?? '0.0000'} BTCS',
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                ),
                              ),

                            const SizedBox(height: 30),

                            // Chart Container
                            Container(
                              height: 200,
                              margin: const EdgeInsets.symmetric(horizontal: 16),
                              padding: const EdgeInsets.only(
                                top: 20,
                                bottom: 10,
                                left: 5,
                                right: 20,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.05),
                                  width: 1,
                                ),
                              ),
                              child: transactions.isEmpty
                                  ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.show_chart,
                                      size: 48,
                                      color: Colors.cyanAccent.withOpacity(0.3),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'No Activity Yet',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Your balance chart will appear here',
                                      style: TextStyle(
                                        color: Colors.white38,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                                  : LineChart(
                                _buildChartData(transactions, displayBalance),
                                duration: const Duration(milliseconds: 250),
                              ),
                            ),

                            const SizedBox(height: 10),

                            // Pending Transactions Pills
                            if (hasPending)
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Colors.orange.withOpacity(0.3),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                Colors.orange.withOpacity(0.8),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${walletProvider.pendingTransactionsCount} transaction${walletProvider.pendingTransactionsCount > 1 ? 's' : ''} pending',
                                            style: const TextStyle(
                                              color: Colors.orange,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Balance will update after confirmation',
                                      style: TextStyle(
                                        color: Colors.orange.withOpacity(0.6),
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            Text(
                              'Last sync: $timestamp',
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),

                        // Action Buttons
                        Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: AnimatedOpacity(
                                  opacity: hasPending ? 0.6 : 1.0,
                                  duration: const Duration(milliseconds: 200),
                                  child: ButtonWidget(
                                    text: 'Send',
                                    isPrimary: true,
                                    icon: Icons.arrow_upward,
                                    onPressed: hasPending
                                        ? () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Please wait for pending transactions to confirm'),
                                          backgroundColor: Colors.orange,
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                        : () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => const SendView(),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ButtonWidget(
                                  text: 'Receive',
                                  isPrimary: true,
                                  icon: Icons.arrow_downward,
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const ReceiveView(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Transactions Section
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Recent Transactions',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (hasPending)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '${walletProvider.pendingTransactionsCount} pending',
                                        style: const TextStyle(
                                          color: Colors.orange,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Show pending transactions first if any
                              if (hasPending) ...[
                                ...walletProvider.pendingTransactionsList.map((pendingTx) =>
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.orange.withOpacity(0.2),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withOpacity(0.2),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.arrow_upward,
                                              color: Colors.orange,
                                              size: 16,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Sent to ${pendingTx.toAddress.substring(0, 8)}...${pendingTx.toAddress.substring(pendingTx.toAddress.length - 6)}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Pending confirmation',
                                                  style: TextStyle(
                                                    color: Colors.orange.withOpacity(0.8),
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                '-${pendingTx.amount.toStringAsFixed(4)}',
                                                style: const TextStyle(
                                                  color: Colors.orange,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                'BTCS',
                                                style: TextStyle(
                                                  color: Colors.orange.withOpacity(0.6),
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                ),
                                if (transactions.isNotEmpty)
                                  const Divider(color: Colors.white12, height: 20),
                              ],

                              if (transactions.isEmpty && !hasPending)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 24),
                                  child: EmptyState(
                                    icon: Icons.receipt_long_outlined,
                                    title: 'No Transactions Yet',
                                    message: 'Receive BTCS to get started with your wallet',
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

                              if (transactions.isNotEmpty) ...[
                                ...transactions.take(5).map((tx) => TransactionTile(
                                  tx: tx,
                                  onTap: () => _showTransactionDetails(tx['txid']),
                                )),

                                if (transactions.length > 5)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: ButtonWidget(
                                        text: 'View All Transactions',
                                        isPrimary: false,
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => const TransactionsView(),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}