import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// Keys for local storage
const String _registeredTokenKey = 'fcm_registered_token';
const String _registeredAddressKey = 'fcm_registered_address';

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
  static bool _isInitializing = false;

  NotificationService({
    required this.backendUrl,
    this.onTransactionReceived,
    this.onNotificationTapped,
  });

  /// Check if we need to register (token or address changed)
  Future<bool> _needsRegistration(String token, String address) async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString(_registeredTokenKey);
    final savedAddress = prefs.getString(_registeredAddressKey);
    return savedToken != token || savedAddress != address;
  }

  /// Save registration info after successful registration
  Future<void> _saveRegistration(String token, String address) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_registeredTokenKey, token);
    await prefs.setString(_registeredAddressKey, address);
    debugPrint('✓ Registration saved locally');
  }

  /// Clear saved registration (call when disabling notifications)
  Future<void> _clearRegistration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_registeredTokenKey);
    await prefs.remove(_registeredAddressKey);
    debugPrint('✓ Registration cleared locally');
  }

  /// Initialize Firebase and request notification permissions
  Future<void> initialize(String walletAddress) async {
    // Prevent concurrent initialization
    if (_isInitializing) {
      debugPrint('NotificationService initialization already in progress, skipping');
      return;
    }
    _isInitializing = true; // Set immediately to prevent race conditions

    if (_initialized) {
      debugPrint('NotificationService already initialized, checking if re-registration needed...');
      String? token;
      try {
        token = await _messaging.getToken();
      } catch (e) {
        if (e.toString().contains('FIS_AUTH_ERROR') || e.toString().contains('IOException')) {
          debugPrint('⚠ FIS auth error, clearing token and retrying...');
          await _messaging.deleteToken();
          await _clearRegistration();
          await Future.delayed(const Duration(seconds: 1));
          token = await _messaging.getToken();
        }
      }
      if (token != null) {
        // Only register if token or address changed
        if (await _needsRegistration(token, walletAddress)) {
          debugPrint('Token or address changed, re-registering...');
          await registerDevice(walletAddress, token);
          await enablePriceAlerts(walletAddress);
          await enableChatNotifications(walletAddress);
          await _saveRegistration(token, walletAddress);
        } else {
          debugPrint('✓ Already registered with same token, skipping');
        }
      }
      _isInitializing = false;
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

        // Get device token with FIS auth error recovery
        String? token;
        try {
          token = await _messaging.getToken();
        } catch (e) {
          if (e.toString().contains('FIS_AUTH_ERROR') || e.toString().contains('IOException')) {
            debugPrint('⚠ FIS auth error, clearing token and retrying...');
            await _messaging.deleteToken();
            await Future.delayed(const Duration(seconds: 1));
            token = await _messaging.getToken();
          } else {
            rethrow;
          }
        }

        if (token != null) {
          debugPrint('✓ FCM Token: ${token.substring(0, 20)}...');

          // Only register if token or address changed
          if (await _needsRegistration(token, walletAddress)) {
            // Register with backend
            await registerDevice(walletAddress, token);
            await enablePriceAlerts(walletAddress);
            await enableChatNotifications(walletAddress);
            await _saveRegistration(token, walletAddress);
          } else {
            debugPrint('✓ Already registered with same token, skipping');
          }

          // Listen for token refresh
          _messaging.onTokenRefresh.listen((newToken) async {
            debugPrint('✓ FCM Token refreshed');
            await registerDevice(walletAddress, newToken);
            await enablePriceAlerts(walletAddress);
            await enableChatNotifications(walletAddress);
            await _saveRegistration(newToken, walletAddress);
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
      _isInitializing = false;
      debugPrint('✓ NotificationService initialized successfully');

    } catch (e) {
      _isInitializing = false;
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
        await _clearRegistration();
      } else {
        debugPrint('✗ Unregistration failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('✗ Unregister error: $e');
    }
  }

  /// Enable price alerts for this device
  Future<void> enablePriceAlerts(String address) async {
    try {
      String? token = await _messaging.getToken();
      if (token == null) return;

      final response = await http.post(
        Uri.parse('$backendUrl/api/price-alerts/enable'),
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
        debugPrint('✓ Price alerts enabled');
      } else {
        debugPrint('✗ Enable price alerts failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('✗ Enable price alerts error: $e');
    }
  }

  /// Enable chat notifications for this device
  Future<void> enableChatNotifications(String address) async {
    try {
      String? token = await _messaging.getToken();
      if (token == null) return;

      final response = await http.post(
        Uri.parse('$backendUrl/api/chat-notifications/enable'),
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
        debugPrint('✓ Chat notifications enabled');
      } else {
        debugPrint('✗ Enable chat notifications failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('✗ Enable chat notifications error: $e');
    }
  }

  /// Disable chat notifications for this device
  Future<void> disableChatNotifications(String address) async {
    try {
      String? token = await _messaging.getToken();
      if (token == null) return;

      final response = await http.post(
        Uri.parse('$backendUrl/api/chat-notifications/disable'),
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
        debugPrint('✓ Chat notifications disabled');
      } else {
        debugPrint('✗ Disable chat notifications failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('✗ Disable chat notifications error: $e');
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
