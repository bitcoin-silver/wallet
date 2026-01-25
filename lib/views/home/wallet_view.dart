import 'dart:async';
import 'package:bitcoinsilver_wallet/widgets/transaction_widget.dart';
import 'package:bitcoinsilver_wallet/widgets/skeleton_loader.dart';
import 'package:bitcoinsilver_wallet/widgets/empty_state.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/providers/blockchain_provider.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/providers/chat_provider.dart';
import 'package:bitcoinsilver_wallet/views/home/receive_view.dart';
import 'package:bitcoinsilver_wallet/views/home/send_view.dart';
import 'package:bitcoinsilver_wallet/views/home/addressbook_view.dart';
import 'package:bitcoinsilver_wallet/views/chat/chat_view.dart';
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
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF2A2A2A),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: Colors.cyanAccent.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
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
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 18),
              SizedBox(width: 12),
              Text(
                'Wallet synced',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF2A2A2A),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Colors.green.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
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

  List<FlSpot> _generateDataPoints(List<dynamic> transactions, double? currentBalance) {
    if (transactions.isEmpty || currentBalance == null) {
      // Show a flat line at current balance or 0
      final balanceValue = currentBalance ?? 0.0;
      return [
        FlSpot(0, balanceValue),
        FlSpot(1, balanceValue),
      ];
    }

    // Calculate the starting balance by working backwards from current balance
    // Transactions are ordered newest to oldest
    double startingBalance = currentBalance;
    for (var tx in transactions) {
      final amount = tx['amount']?.toDouble() ?? 0.0;
      startingBalance -= amount;
    }

    // Ensure starting balance is not negative for display
    if (startingBalance < 0) startingBalance = 0.0;

    // Now build the balance history going forwards (oldest to newest)
    final spots = <FlSpot>[];
    final reversedTransactions = transactions.reversed.toList();

    // Start with the calculated starting balance
    double balance = startingBalance;
    spots.add(FlSpot(0, balance));

    // Add each transaction's effect (oldest to newest)
    for (int i = 0; i < reversedTransactions.length; i++) {
      final tx = reversedTransactions[i];
      final amount = tx['amount']?.toDouble() ?? 0.0;
      balance += amount;

      // Ensure balance never goes below 0 for display purposes
      final displayBalance = balance < 0 ? 0.0 : balance;
      spots.add(FlSpot((i + 1).toDouble(), displayBalance));
    }

    return spots;
  }

  LineChartData _buildChartData(List<dynamic> transactions, double? currentBalance) {
    final spots = _generateDataPoints(transactions, currentBalance);

    // Calculate bounds
    double maxY = currentBalance ?? 1.0;
    if (spots.isNotEmpty) {
      final maxSpotY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
      maxY = maxSpotY > maxY ? maxSpotY : maxY;
    }
    maxY = maxY * 1.1; // Add 10% padding
    if (maxY == 0) maxY = 1; // Ensure we have some height

    // maxX is based on the last spot's x value
    final maxX = spots.isNotEmpty ? spots.last.x : 1.0;

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
          getTooltipColor: (spot) => const Color(0xFF1A1A1A).withValues(alpha: 0.95),
          tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          tooltipMargin: 10,
          tooltipBorder: BorderSide(
            color: Colors.cyanAccent.withValues(alpha: 0.3),
            width: 1.5,
          ),
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((LineBarSpot touchedSpot) {
              if (touchedSpot.x == 0) {
                return LineTooltipItem(
                  'Starting Balance\n',
                  const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  children: [
                    TextSpan(
                      text: '${touchedSpot.y.toStringAsFixed(4)} BTCS',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                );
              }

              // x=1 corresponds to oldest transaction, x=transactions.length to newest
              // Calculate which transaction this corresponds to
              final reversedTxIndex = touchedSpot.x.toInt() - 1;
              if (reversedTxIndex >= 0 && reversedTxIndex < transactions.length) {
                // Map back to original transaction index (newest first)
                final txIndex = transactions.length - 1 - reversedTxIndex;
                final tx = transactions[txIndex];
                final amount = tx['amount']?.toDouble() ?? 0.0;
                final isReceived = amount > 0;

                return LineTooltipItem(
                  '${isReceived ? 'Received' : 'Sent'}\n',
                  const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  children: [
                    TextSpan(
                      text: 'Balance: ${touchedSpot.y.toStringAsFixed(4)} BTCS',
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
                color: Colors.cyanAccent.withValues(alpha: 0.6),
                strokeWidth: 3,
                dashArray: [8, 4],
              ),
              FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) {
                  return FlDotCirclePainter(
                    radius: 7,
                    color: Colors.cyanAccent,
                    strokeWidth: 3,
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
            color: Colors.white.withValues(alpha: 0.1),
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

      // Line bars with glow effect (multiple layers)
      lineBarsData: [
        // Outer glow layer
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.3,
          preventCurveOverShooting: true,
          color: Colors.cyanAccent.withValues(alpha: 0.3),
          barWidth: 8,
          isStrokeCapRound: true,
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
        // Middle glow layer
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.3,
          preventCurveOverShooting: true,
          color: Colors.cyanAccent.withValues(alpha: 0.5),
          barWidth: 4,
          isStrokeCapRound: true,
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
        // Main line with enhanced gradient
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.3,
          preventCurveOverShooting: true,
          gradient: LinearGradient(
            colors: [
              const Color(0xFF00E5FF),
              Colors.cyanAccent,
              const Color(0xFFC0C0C0),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
          barWidth: 3,
          isStrokeCapRound: true,

          // Enhanced dots with glow
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, index) {
              // Only show dot if it's touched or it's the last point
              if (index == _touchedIndex || index == spots.length - 1) {
                return FlDotCirclePainter(
                  radius: 6,
                  color: Colors.cyanAccent,
                  strokeWidth: 3,
                  strokeColor: Colors.white,
                );
              }
              return FlDotCirclePainter(
                radius: 0,
                color: Colors.transparent,
              );
            },
          ),

          // Enhanced gradient below line
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [
                const Color(0xFF00E5FF).withValues(alpha: 0.4),
                Colors.cyanAccent.withValues(alpha: 0.25),
                const Color(0xFF00E5FF).withValues(alpha: 0.1),
                Colors.cyanAccent.withValues(alpha: 0.05),
                Colors.transparent,
              ],
              stops: const [0.0, 0.3, 0.6, 0.8, 1.0],
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

    return Scaffold(
      body: Stack(
        children: [
          RefreshIndicator(
        backgroundColor: const Color(0xFF3A3A3A),
        color: Colors.cyanAccent,
        strokeWidth: 3,
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
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: SilverCard(
                            padding: const EdgeInsets.all(16),
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
                        ),
                      ] else ...[
                        // Balance Display with fade-in animation
                        AnimatedOpacity(
                          opacity: displayBalance != null ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOut,
                          child: Column(
                            children: [
                              const SizedBox(height: 20),

                              // USD Value with enhanced styling
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: displayBalance ?? 0.0),
                                duration: const Duration(milliseconds: 800),
                                curve: Curves.easeOut,
                                builder: (context, value, child) {
                                  final usdValue = value * price;
                                  return Text(
                                    '\$${usdValue.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: hasPending
                                          ? Colors.orange.withValues(alpha: 0.8)
                                          : Colors.white60,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  );
                                },
                              ),

                              const SizedBox(height: 12),

                              // BTCS Balance with pending indicator and animation
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: displayBalance ?? 0.0),
                                duration: const Duration(milliseconds: 800),
                                curve: Curves.easeOutCubic,
                                builder: (context, value, child) {
                                  return Stack(
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
                                                  color: Colors.orange
                                                      .withValues(alpha: _pendingAnimation.value),
                                                  size: 22,
                                                );
                                              },
                                            ),
                                          if (hasPending) const SizedBox(width: 10),
                                          ShaderMask(
                                            shaderCallback: (bounds) => LinearGradient(
                                              colors: hasPending
                                                  ? [
                                                      Colors.orange,
                                                      Colors.orange
                                                          .withValues(alpha: 0.8),
                                                    ]
                                                  : [
                                                      Colors.white,
                                                      const Color(0xFFC0C0C0),
                                                    ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ).createShader(bounds),
                                            child: Text(
                                              value.toStringAsFixed(4),
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 42,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 1,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            'BTCS',
                                            style: TextStyle(
                                              color: hasPending
                                                  ? Colors.orange.withValues(alpha: 0.7)
                                                  : const Color(0xFFC0C0C0),
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
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

                            // Floating Chart - no card background
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: SizedBox(
                                height: 220,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 400),
                                  switchInCurve: Curves.easeOut,
                                  switchOutCurve: Curves.easeIn,
                                  child: transactions.isEmpty
                                      ? Center(
                                          key: const ValueKey('empty'),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              ShaderMask(
                                                shaderCallback: (bounds) =>
                                                    LinearGradient(
                                                  colors: [
                                                    Colors.cyanAccent
                                                        .withValues(alpha: 0.5),
                                                    Colors.cyanAccent
                                                        .withValues(alpha: 0.2),
                                                  ],
                                                ).createShader(bounds),
                                                child: const Icon(
                                                  Icons.show_chart_rounded,
                                                  size: 56,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              const SizedBox(height: 16),
                                              const Text(
                                                'No Activity Yet',
                                                style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: 0.3,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                'Your balance chart will appear here',
                                                style: TextStyle(
                                                  color: Colors.white38,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w400,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : Padding(
                                          key: const ValueKey('chart'),
                                          padding: const EdgeInsets.only(
                                            top: 10,
                                            bottom: 10,
                                            left: 5,
                                            right: 20,
                                          ),
                                          child: LineChart(
                                            _buildChartData(transactions, displayBalance),
                                            duration: const Duration(milliseconds: 300),
                                          ),
                                        ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Pending Transactions Pills
                            if (hasPending)
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Colors.orange.withValues(alpha: 0.3),
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
                                                Colors.orange.withValues(alpha: 0.8),
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
                                        color: Colors.orange.withValues(alpha: 0.6),
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
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
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
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: SilverCard(
                            padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  ShaderMask(
                                    shaderCallback: (bounds) => const LinearGradient(
                                      colors: [
                                        Colors.white,
                                        Color(0xFFC0C0C0),
                                      ],
                                    ).createShader(bounds),
                                    child: const Text(
                                      'Recent Transactions',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                  if (hasPending)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.orange.withValues(alpha: 0.25),
                                            Colors.orange.withValues(alpha: 0.15),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.orange.withValues(alpha: 0.3),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        '${walletProvider.pendingTransactionsCount} pending',
                                        style: const TextStyle(
                                          color: Colors.orange,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Show pending transactions first if any
                              if (hasPending) ...[
                                ...walletProvider.pendingTransactionsList.map((pendingTx) =>
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.orange.withValues(alpha: 0.2),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withValues(alpha: 0.2),
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
                                                    color: Colors.orange.withValues(alpha: 0.8),
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
                                                  color: Colors.orange.withValues(alpha: 0.6),
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
          // Addressbook button in top-right corner - Modern glassmorphic design
          Positioned(
            top: 20,
            right: 16,
            child: SafeArea(
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AddressbookView(),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.cyanAccent.withValues(alpha: 0.9),
                        Colors.cyanAccent.withValues(alpha: 0.7),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyanAccent.withValues(alpha: 0.4),
                        blurRadius: 12,
                        spreadRadius: 1,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Background glow effect
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.3),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      // Icon
                      const Icon(
                        Icons.contact_page_rounded,
                        color: Colors.black,
                        size: 26,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Chat button in upper left corner - Matching addressbook design
          Positioned(
            top: 20,
            left: 16,
            child: SafeArea(
              child: Consumer<ChatProvider>(
                builder: (context, chatProvider, child) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ChatView(),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.cyanAccent.withValues(alpha: 0.9),
                            Colors.cyanAccent.withValues(alpha: 0.7),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.cyanAccent.withValues(alpha: 0.4),
                            blurRadius: 12,
                            spreadRadius: 1,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          // Background glow effect
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0.3),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                          // Icon
                          const Icon(
                            Icons.chat_bubble,
                            color: Colors.black,
                            size: 26,
                          ),
                          // Unread badge
                          if (chatProvider.unreadCount > 0)
                            Positioned(
                              right: -8,
                              top: -8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 18,
                                  minHeight: 18,
                                ),
                                child: Text(
                                  chatProvider.unreadCount > 99
                                      ? '99+'
                                      : chatProvider.unreadCount.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}