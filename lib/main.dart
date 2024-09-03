import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/providers/transaction_provider.dart';
import 'package:bitcoinsilver_wallet/views/setup_view.dart';
import 'package:bitcoinsilver_wallet/views/home_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final walletProvider = WalletProvider();
  await walletProvider.loadWallet();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<WalletProvider>.value(value: walletProvider),
        ChangeNotifierProvider(create: (_) => TransactionProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final walletProvider = Provider.of<WalletProvider>(context);
    final initialRoute = walletProvider.privateKey != null ? '/home' : '/';

    return MaterialApp(
      initialRoute: initialRoute,
      routes: {
        '/': (context) => SetupView(),
        '/home': (context) => const HomeView(),
      },
    );
  }
}
