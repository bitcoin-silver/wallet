// main.dart - Fixed for Flutter 3.35.3
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:bitcoinsilver_wallet/providers/addressbook_provider.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/providers/blockchain_provider.dart';
import 'package:bitcoinsilver_wallet/views/setup_view.dart';
import 'package:bitcoinsilver_wallet/views/biometric_gate.dart';

// Backend URL - HTTPS endpoint
const String backendUrl = 'https://bitcoinsilver.eu';

// Global navigator key for navigation from notifications
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  try {
    await Firebase.initializeApp();
    if (kDebugMode) {
      debugPrint('✓ Firebase initialized');
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('✗ Firebase initialization failed: $e');
    }
  }

  // Enable edge-to-edge display for Android 15+ compatibility
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );

  // Add basic system UI customization
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      // The colors are removed to avoid deprecated API calls in Android 15+.
      // Edge-to-edge is handled by the native side and SystemUiMode.edgeToEdge.
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Note: Removed orientation restrictions to support large screen devices
  // (tablets, foldables) as required by Android 16+
  // The app now supports all orientations for better user experience

  // Initialize providers
  final wp = WalletProvider();
  final bp = BlockchainProvider();
  final abp = AddressbookProvider();

  // Link providers - so notifications refresh both balance and transactions silently
  wp.setTransactionRefreshCallback((address) => bp.loadBlockchain(address, silent: true));

  // Add error handling for Flutter framework
  if (kDebugMode) {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
    };
  } else {
    FlutterError.onError = (details) {
      // In release mode, log to your crash reporting service
      debugPrint('Flutter error: ${details.exception}');
    };
  }

  final startupFuture = _bootstrapApp(wp, bp);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<WalletProvider>.value(value: wp),
        ChangeNotifierProvider<BlockchainProvider>.value(value: bp),
        ChangeNotifierProvider<AddressbookProvider>.value(value: abp),
      ],
      child: MyApp(startupFuture: startupFuture),
    ),
  );
}

Future<void> _bootstrapApp(
  WalletProvider wp,
  BlockchainProvider bp,
) async {
  try {
    await wp.loadWallet();
    final rpcReachable = await _configureRpcConnection(wp);

    if (wp.address != null) {
      final futures = <Future<void>>[
        bp.loadBlockchain(wp.address),
      ];

      // RPC affects UTXO/balance fetching, but explorer history can still load.
      if (rpcReachable) {
        futures.add(wp.fetchUtxos(force: true));
      }

      await Future.wait(futures);
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Startup bootstrap failed: $e');
    }
  }
}

Future<bool> _configureRpcConnection(
  WalletProvider wp,
) async {
  try {
    final rpcResponse = await wp.walletService
        .rpcRequest('getblockchaininfo')
        .timeout(const Duration(seconds: 4));
    final hasValidResult = rpcResponse != null &&
        rpcResponse['error'] == null &&
        rpcResponse['result'] != null;

    if (!hasValidResult) {
      wp.setRpcError(
        'RPC is unreachable right now. Balance display is affected until connection is restored.',
      );
      return false;
    } else {
      wp.setRpcError(null);
      return true;
    }
  } catch (e) {
    wp.setRpcError(
      'RPC is unreachable right now. Balance display is affected until connection is restored.',
    );
    return false;
  }
}

class MyApp extends StatelessWidget {
  final Future<void> startupFuture;

  const MyApp({super.key, required this.startupFuture});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: startupFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupLoadingScreen();
        }

        return Consumer<WalletProvider>(
          builder: (context, wp, child) {
            final initialRoute = wp.privateKey != null ? '/home' : '/setup';

            return MaterialApp(
              navigatorKey: navigatorKey, // For navigation from notifications
              title: 'Bitcoin Silver Wallet',
              debugShowCheckedModeBanner: false,

              // Material 3 theme with silver accent
              theme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
                scaffoldBackgroundColor: const Color(0xFF0A0A0A),
                colorScheme: ColorScheme.dark(
                  primary: const Color(0xFFC0C0C0), // Silver
                  secondary: const Color(0xFF00E5FF), // Cyan accent
                  surface: const Color(0xFF1A1A1A),
                  onPrimary: Colors.black,
                  onSecondary: Colors.black,
                  onSurface: Colors.white,
                ),
                appBarTheme: const AppBarTheme(
                  centerTitle: true,
                  elevation: 0,
                  backgroundColor: Color(0xFF0A0A0A),
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                cardTheme: CardThemeData(
                  color: const Color(0xFF1A1A1A),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: const Color(0xFFC0C0C0).withValues(alpha: 0.1),
                    ),
                  ),
                ),
              ),

              darkTheme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
                scaffoldBackgroundColor: const Color(0xFF0A0A0A),
                colorScheme: ColorScheme.dark(
                  primary: const Color(0xFFC0C0C0), // Silver
                  secondary: const Color(0xFF00E5FF), // Cyan accent
                  surface: const Color(0xFF1A1A1A),
                  onPrimary: Colors.black,
                  onSecondary: Colors.black,
                  onSurface: Colors.white,
                ),
                appBarTheme: const AppBarTheme(
                  centerTitle: true,
                  elevation: 0,
                  backgroundColor: Color(0xFF0A0A0A),
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                cardTheme: CardThemeData(
                  color: const Color(0xFF1A1A1A),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: const Color(0xFFC0C0C0).withValues(alpha: 0.1),
                    ),
                  ),
                ),
              ),

              themeMode: ThemeMode.dark, // Always use dark theme

              initialRoute: initialRoute,
              routes: {
                '/setup': (context) => SetupView(),
                '/home': (context) => const BiometricGate(),
              },

              // Add navigation observer for debugging
              navigatorObservers: kDebugMode ? [_DebugNavigatorObserver()] : [],
            );
          },
        );
      },
    );
  }
}

class _StartupLoadingScreen extends StatelessWidget {
  const _StartupLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
      ),
      home: const Scaffold(
        backgroundColor: Color(0xFF0A0A0A),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Color(0xFF00E5FF),
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Starting Bitcoin Silver Wallet...',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Simple navigation observer for debugging
class _DebugNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    debugPrint('Navigation: Pushed ${route.settings.name}');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    debugPrint('Navigation: Popped ${route.settings.name}');
  }
}