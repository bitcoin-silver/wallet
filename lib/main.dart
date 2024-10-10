import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/providers/blockchain_provider.dart';
import 'package:bitcoinsilver_wallet/views/setup_view.dart';
import 'package:bitcoinsilver_wallet/views/home_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final wp = WalletProvider();
  final bp = BlockchainProvider();
  await wp.loadWallet();
  if (wp.address != null) {
    bp.loadBlockchain(wp.address);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<WalletProvider>.value(value: wp),
        ChangeNotifierProvider<BlockchainProvider>.value(value: bp),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final wp = Provider.of<WalletProvider>(context);
    final initialRoute = wp.privateKey != null ? '/home' : '/setup';

    return MaterialApp(
      initialRoute: initialRoute,
      routes: {
        '/setup': (context) => SetupView(),
        '/home': (context) => const HomeView(),
      },
    );
  }
}
