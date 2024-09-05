import 'package:flutter/material.dart';
import 'package:bitcoinsilver_wallet/views/home/transaction/receive_view.dart';
import 'package:bitcoinsilver_wallet/views/home/transaction/send_view.dart';
import 'package:bitcoinsilver_wallet/widgets/balance_widget.dart';
import 'package:bitcoinsilver_wallet/widgets/button_widget.dart';

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
    _balanceKey.currentState?.updateBalance();
  }

  @override
  Widget build(BuildContext context) {
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
                child: Column(
                  children: [
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
