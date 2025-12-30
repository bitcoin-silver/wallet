// ================================================================================
// CHAT NOTIFICATION SERVICE
// ================================================================================
// Created: 2025-01-12
// Purpose: Local notifications for chat messages
// ================================================================================

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

class ChatNotificationService {
  static final ChatNotificationService _instance = ChatNotificationService._internal();
  factory ChatNotificationService() => _instance;
  ChatNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  // Callback for when user taps notification
  Function()? onNotificationTapped;

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Android initialization settings
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
      );

      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Create notification channel for Android
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'chat_messages', // channel ID
        'Chat Messages', // channel name
        description: 'Notifications for new chat messages',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      // Register the channel with Android
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      _isInitialized = true;
      debugPrint('✅ Chat notification service initialized');
      debugPrint('✅ Chat notification channel created');
    } catch (error) {
      debugPrint('❌ Error initializing chat notifications: $error');
    }
  }

  /// Show notification for new chat message
  Future<void> showMessageNotification({
    required String username,
    required String message,
    int unreadCount = 1,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'chat_messages', // channel ID
        'Chat Messages', // channel name
        channelDescription: 'Notifications for new chat messages',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        icon: '@mipmap/ic_launcher',
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
      );

      // Notification title and body
      final title = unreadCount > 1
          ? 'BTCS Messenger ($unreadCount new messages)'
          : 'BTCS Messenger';
      final body = unreadCount > 1
          ? '$username and others sent messages'
          : '$username: $message';

      await _notificationsPlugin.show(
        0, // notification ID (using 0 to replace previous chat notification)
        title,
        body,
        notificationDetails,
        payload: 'chat_message', // Payload to identify chat notifications
      );

      debugPrint('📬 Notification shown: $username - $message');
    } catch (error) {
      debugPrint('❌ Error showing notification: $error');
    }
  }

  /// Clear all chat notifications
  Future<void> clearNotifications() async {
    try {
      await _notificationsPlugin.cancel(0); // Cancel chat notification
      debugPrint('🔕 Chat notifications cleared');
    } catch (error) {
      debugPrint('❌ Error clearing notifications: $error');
    }
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Chat notification tapped: ${response.payload}');

    // Only handle chat message notifications
    if (response.payload == 'chat_message') {
      // Trigger callback to navigate to chat
      onNotificationTapped?.call();
      debugPrint('✓ Navigating to chat...');
    }
  }
}
