// ================================================================================
// BTCS MESSENGER - CHAT PROVIDER
// ================================================================================
// Created: 2025-11-11
// Purpose: State management for chat functionality
// ================================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../services/chat_notification_service.dart';

class ChatProvider with ChangeNotifier {
  final ChatService _chatService = ChatService();
  final ChatNotificationService _notificationService = ChatNotificationService();
  final List<ChatMessage> _messages = [];
  bool _isConnected = false;
  bool _isLoading = false;
  String? _currentWalletAddress;
  String? _currentNickname;
  int _unreadCount = 0;
  bool _isChatOpen = false;

  StreamSubscription? _messageSubscription;
  StreamSubscription? _connectionSubscription;

  // Getters
  List<ChatMessage> get messages => _messages;
  bool get isConnected => _isConnected;
  bool get isLoading => _isLoading;
  String? get currentNickname => _currentNickname;
  int get unreadCount => _unreadCount;
  bool get isChatOpen => _isChatOpen;

  ChatProvider() {
    _initialize();
  }

  void _initialize() {
    // Initialize notification service
    _notificationService.initialize();

    // Listen to message stream
    _messageSubscription = _chatService.messages.listen((message) {
      _messages.add(message);

      // Handle notifications and unread count if chat is not open
      if (!_isChatOpen && message.walletAddress != _currentWalletAddress) {
        _unreadCount++;

        // Show notification for new message (skip system messages)
        if (!message.isSystem) {
          final username = message.nickname ??
              '${message.walletAddress.substring(0, 8)}...';

          _notificationService.showMessageNotification(
            username: username,
            message: message.message,
            unreadCount: _unreadCount,
          );
        }
      }

      // Schedule notifyListeners to avoid calling during build
      Future.microtask(() => notifyListeners());
    });

    // Listen to connection status
    _connectionSubscription = _chatService.connectionStatus.listen((connected) {
      _isConnected = connected;
      // Schedule notifyListeners to avoid calling during build
      Future.microtask(() => notifyListeners());

      // Request history when connected
      if (connected && _messages.isEmpty) {
        loadHistory();
      }
    });
  }

  /// Connect to chat
  Future<void> connect(String walletAddress, {String? nickname}) async {
    _currentWalletAddress = walletAddress;
    _currentNickname = nickname;

    // Try to load nickname from server if not provided
    if (nickname == null) {
      _currentNickname = await _chatService.getNickname(walletAddress);
    }

    await _chatService.connect(walletAddress, nickname: _currentNickname);
  }

  /// Disconnect from chat
  void disconnect() {
    _chatService.disconnect();
    _currentWalletAddress = null;
    _currentNickname = null;
  }

  /// Send a message
  Future<bool> sendMessage(String message) async {
    if (message.trim().isEmpty) {
      return false;
    }

    // Handle /price command locally
    if (message.trim().toLowerCase() == '/price') {
      final price = await _chatService.getCurrentPrice();

      if (price != null) {
        // Add local system message with price
        final priceMessage = ChatMessage(
          walletAddress: 'SYSTEM',
          nickname: 'BTCS Price Bot',
          message: '📊 Current BTCS Price: $price USD\nSource: LiveCoinWatch',
          timestamp: DateTime.now(),
          messageType: 'system',
        );
        _messages.add(priceMessage);
        // Schedule notifyListeners to avoid calling during build
        Future.microtask(() => notifyListeners());
        return true;
      } else {
        // Error fetching price
        final errorMessage = ChatMessage(
          walletAddress: 'SYSTEM',
          nickname: 'BTCS Price Bot',
          message: '❌ Unable to fetch current price. Please try again later.',
          timestamp: DateTime.now(),
          messageType: 'system',
        );
        _messages.add(errorMessage);
        // Schedule notifyListeners to avoid calling during build
        Future.microtask(() => notifyListeners());
        return false;
      }
    }

    return await _chatService.sendMessage(message);
  }

  /// Send typing indicator
  void sendTypingIndicator(bool typing) {
    _chatService.sendTypingIndicator(typing);
  }

  /// Load message history (limited to last 200 messages to prevent network overhead)
  Future<void> loadHistory() async {
    if (_isLoading) {
      debugPrint('Already loading history, skipping duplicate request');
      return;
    }

    // Prevent duplicate loads within 2 seconds
    if (_messages.isNotEmpty) {
      debugPrint('History already loaded, skipping duplicate request');
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      debugPrint('Fetching chat history from server...');
      // Load only the last 200 messages to prevent excessive network usage
      final history = await _chatService.fetchHistory(limit: 200);

      // Clear current messages and add history
      _messages.clear();
      _messages.addAll(history);

      debugPrint('Chat history loaded: ${history.length} messages (max 200)');
      notifyListeners();
    } catch (error) {
      debugPrint('Error loading history: $error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load more messages (pagination)
  Future<void> loadMore() async {
    if (_isLoading) return;

    _isLoading = true;
    notifyListeners();

    try {
      final offset = _messages.length;
      final moreMessages = await _chatService.fetchHistory(
        limit: 50,
        offset: offset,
      );

      if (moreMessages.isNotEmpty) {
        // Insert at beginning (older messages)
        _messages.insertAll(0, moreMessages);
        notifyListeners();
      }
    } catch (error) {
      debugPrint('Error loading more messages: $error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Set user nickname
  Future<bool> setNickname(String nickname) async {
    if (_currentWalletAddress == null) {
      return false;
    }

    final success = await _chatService.setNickname(nickname);
    if (success) {
      _currentNickname = nickname;
      notifyListeners();

      // Reconnect with new nickname
      disconnect();
      await connect(_currentWalletAddress!, nickname: nickname);
    }
    return success;
  }

  /// Mark chat as opened (reset unread count and clear notifications)
  void markChatAsOpened() {
    _isChatOpen = true;
    _unreadCount = 0;
    _notificationService.clearNotifications();
    notifyListeners();
  }

  /// Mark chat as closed
  void markChatAsClosed() {
    _isChatOpen = false;
    notifyListeners();
  }

  /// Clear all messages
  void clearMessages() {
    _messages.clear();
    notifyListeners();
  }

  /// Check if message is from current user
  bool isMyMessage(ChatMessage message) {
    return message.walletAddress == _currentWalletAddress;
  }

  /// Get display name for a message
  String getDisplayName(ChatMessage message) {
    if (message.isSystem) {
      return 'System';
    }

    // Show actual username for all messages (including own messages)
    final nickname = message.nickname ?? '${message.walletAddress.substring(0, 8)}...';

    // Add @ symbol before username
    return '@$nickname';
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _connectionSubscription?.cancel();
    _chatService.dispose();
    super.dispose();
  }
}
