// main.dart - Fixed for Flutter 3.35.3
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/providers/blockchain_provider.dart';
import 'package:bitcoinsilver_wallet/providers/addressbook_provider.dart';
import 'package:bitcoinsilver_wallet/providers/chat_provider.dart';
import 'package:bitcoinsilver_wallet/views/setup_view.dart';
import 'package:bitcoinsilver_wallet/views/biometric_gate.dart';
import 'package:bitcoinsilver_wallet/views/chat/chat_view.dart';
import 'package:bitcoinsilver_wallet/services/rpc_config_service.dart';
import 'package:bitcoinsilver_wallet/services/chat_notification_service.dart';
// Migration service removed - was causing issues on Play Store updates
// import 'package:bitcoinsilver_wallet/services/migration_service.dart';

// Backend URL - HTTPS endpoint
const String backendUrl = 'https://btcs-vps13.duckdns.org';

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

  // Initialize RPC credentials in secure storage
  final rpcConfig = RpcConfigService();
  await rpcConfig.initializeRpcCredentials();

  // Enable edge-to-edge display for Android 15+ compatibility
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );

  // Add system UI customization with edge-to-edge support
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light, // Light icons on dark background
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  // Note: Removed orientation restrictions to support large screen devices
  // (tablets, foldables) as required by Android 16+
  // The app now supports all orientations for better user experience

  // Initialize providers with error handling
  final wp = WalletProvider();
  final bp = BlockchainProvider();

  // Link providers - so notification taps refresh transactions
  wp.setTransactionRefreshCallback((address) => bp.loadBlockchain(address));

  // Load wallet and data synchronously
  try {
    await wp.loadWallet();
    if (wp.address != null) {
      await wp.fetchUtxos(force: true);
      await bp.loadBlockchain(wp.address);
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Error loading wallet: $e');
    }
  }

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

  // Setup chat notification tap handler
  final chatNotificationService = ChatNotificationService();
  chatNotificationService.onNotificationTapped = () {
    // Navigate to chat when notification is tapped
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => const ChatView(),
      ),
    );
  };

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<WalletProvider>.value(value: wp),
        ChangeNotifierProvider<BlockchainProvider>.value(value: bp),
        ChangeNotifierProvider<AddressbookProvider>(create: (_) => AddressbookProvider()),
        ChangeNotifierProvider<ChatProvider>(create: (_) => ChatProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
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