import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// API Key for backend authentication (from dart_defines.json)
const String apiKey = String.fromEnvironment('NOTIFICATION_API_KEY');

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('Background message: ${message.messageId}');
  debugPrint('Title: ${message.notification?.title}');
  debugPrint('Body: ${message.notification?.body}');
}

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final String backendUrl;

  // Callbacks for handling notifications
  Function(String txid, String amount, String address)? onTransactionReceived;
  Function(String txid)? onNotificationTapped;

  static bool _initialized = false;

  NotificationService({
    required this.backendUrl,
    this.onTransactionReceived,
    this.onNotificationTapped,
  });

  /// Initialize Firebase and request notification permissions
  Future<void> initialize(String walletAddress) async {
    if (_initialized) {
      debugPrint('NotificationService already initialized, re-registering device...');
      // Even if already initialized, we should re-register the device
      // This ensures the backend has the current token after re-enabling
      String? token = await _messaging.getToken();
      if (token != null) {
        await registerDevice(walletAddress, token);
      }
      return;
    }

    try {
      // Request permission (will return current status if already granted)
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint('Permission status: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('✓ Notification permission granted');

        // Get device token
        String? token = await _messaging.getToken();

        if (token != null) {
          debugPrint('✓ FCM Token: ${token.substring(0, 20)}...');

          // Register with backend
          await registerDevice(walletAddress, token);

          // Listen for token refresh
          _messaging.onTokenRefresh.listen((newToken) {
            debugPrint('✓ FCM Token refreshed');
            registerDevice(walletAddress, newToken);
          });
        } else {
          debugPrint('✗ Failed to get FCM token');
        }
      } else if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('✗ Notification permission denied');
        throw Exception('Notification permission denied. Please enable in system settings.');
      } else {
        debugPrint('⚠ Notification permission provisional');
      }

      // Setup background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('✓ Foreground message received');
        debugPrint('Title: ${message.notification?.title}');
        debugPrint('Body: ${message.notification?.body}');
        _handleMessage(message);
      });

      // Handle notification tap (app opened from notification)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('✓ Notification tapped');
        _handleNotificationTap(message);
      });

      _initialized = true;
      debugPrint('✓ NotificationService initialized successfully');

    } catch (e) {
      debugPrint('✗ Failed to initialize NotificationService: $e');
      rethrow;
    }
  }

  /// Register device token with backend
  Future<void> registerDevice(String address, String deviceToken) async {
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/api/register'),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': apiKey,
        },
        body: json.encode({
          'address': address,
          'device_token': deviceToken,
          'platform': 'android',
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('✓ Device registered with backend: ${data['message']}');
      } else {
        debugPrint('✗ Registration failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('✗ Registration error: $e');
    }
  }

  /// Unregister device token from backend
  Future<void> unregisterDevice(String address) async {
    try {
      String? token = await _messaging.getToken();
      if (token == null) {
        debugPrint('No token to unregister');
        return;
      }

      final response = await http.post(
        Uri.parse('$backendUrl/api/unregister'),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': apiKey,
        },
        body: json.encode({
          'address': address,
          'device_token': token,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('✓ Device unregistered from backend');
      } else {
        debugPrint('✗ Unregistration failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('✗ Unregister error: $e');
    }
  }

  /// Handle foreground notification
  void _handleMessage(RemoteMessage message) {
    // You can show in-app notification or update UI
    debugPrint('Notification Data: ${message.data}');

    // Parse transaction data if present
    if (message.data['type'] == 'incoming_tx') {
      String? txid = message.data['txid'];
      String? amount = message.data['amount'];
      String? address = message.data['address'];
      String? confirmationsStr = message.data['confirmations'];
      int confirmations = int.tryParse(confirmationsStr ?? '0') ?? 0;

      debugPrint('Incoming transaction:');
      debugPrint('  TXID: $txid');
      debugPrint('  Amount: $amount BTCS');
      debugPrint('  Address: $address');
      debugPrint('  Confirmations: $confirmations');

      // Trigger callback only if confirmed (to refresh balance)
      if (txid != null && amount != null && address != null && confirmations >= 1) {
        onTransactionReceived?.call(txid, amount, address);
      }
    }
  }

  /// Handle notification tap
  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('User tapped notification');

    String? txid = message.data['txid'];
    String? type = message.data['type'];

    if (type == 'incoming_tx' && txid != null) {
      // Trigger callback to navigate to transaction details
      debugPrint('Navigate to transaction: $txid');
      onNotificationTapped?.call(txid);
    }
  }

  /// Get current FCM token
  Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      debugPrint('Error getting token: $e');
      return null;
    }
  }

  /// Delete FCM token
  Future<void> deleteToken() async {
    try {
      await _messaging.deleteToken();
      _initialized = false;
      debugPrint('✓ FCM token deleted');
    } catch (e) {
      debugPrint('Error deleting token: $e');
    }
  }
}
