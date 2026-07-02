// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

//import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:bitcoinsilver_wallet/main.dart';
import 'package:bitcoinsilver_wallet/providers/blockchain_provider.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/services/rpc_config_service.dart';

void main() {
  testWidgets('app boots to setup screen', (WidgetTester tester) async {
    final rpcConfig = RpcConfigService();
    final walletProvider = WalletProvider(rpcConfig);
    final blockchainProvider = BlockchainProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WalletProvider>.value(value: walletProvider),
          ChangeNotifierProvider<BlockchainProvider>.value(value: blockchainProvider),
        ],
        child: MyApp(startupFuture: Future<void>.value()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Recover Wallet'), findsOneWidget);
  });
}
