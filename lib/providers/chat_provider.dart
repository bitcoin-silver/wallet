// ================================================================================
// BTCS MESSENGER - CHAT PROVIDER
// ================================================================================
// Created: 2025-11-11
// Purpose: State management for chat functionality
// ================================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../services/chat_notification_service.dart';

class ChatProvider with ChangeNotifier, WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('ChatProvider: App resumed, checking connection and refreshing messages...');
      
      // If we have an address, try to reconnect if disconnected
      if (_currentWalletAddress != null) {
        // Always refresh history on resume to get missed messages from REST API
        loadHistory(forceRefresh: true);

        if (!_isConnected) {
          debugPrint('ChatProvider: Reconnecting WebSocket on resume...');
          connect(_currentWalletAddress!, nickname: _currentNickname);
        }
      }
    }
  }

  void _initialize() {
    // Initialize notification service
    _notificationService.initialize();

    // Listen to message stream
    _messageSubscription = _chatService.messages.listen((message) {
      // Avoid duplicates by checking ID
      if (message.id != null && _messages.any((m) => m.id == message.id)) {
        debugPrint('ChatProvider: Skipping duplicate message with ID ${message.id}');
        return;
      }

      // With reverse: true in ListView, newest message should be at index 0
      _messages.insert(0, message);

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

      // Always request history when connected to ensure we have latest messages
      if (connected) {
        loadHistory(forceRefresh: true);
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
      debugPrint('ChatProvider: Fetched nickname from server: $_currentNickname');
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
  Future<void> loadHistory({bool forceRefresh = false}) async {
    if (_isLoading) {
      debugPrint('Already loading history, skipping duplicate request');
      return;
    }

    // Prevent duplicate loads unless forced
    if (!forceRefresh && _messages.isNotEmpty) {
      debugPrint('History already loaded, skipping duplicate request');
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      debugPrint('Fetching chat history from server...');
      // Load only the last 200 messages to prevent excessive network usage
      final history = await _chatService.fetchHistory(limit: 200);

      if (history.isEmpty) return;

      // Intelligent merging:
      // 1. Create a map of existing message IDs for fast lookup
      final existingIds = _messages
          .where((m) => m.id != null)
          .map((m) => m.id!)
          .toSet();

      // 2. Filter history to only include messages we don't already have
      final newMessages = history.where((m) => m.id == null || !existingIds.contains(m.id)).toList();

      if (newMessages.isNotEmpty) {
        // 3. Add new messages and sort by timestamp (newest first for reverse: true)
        _messages.addAll(newMessages);
        _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        // 4. Keep only last 300 messages to manage memory
        if (_messages.length > 300) {
          _messages.removeRange(300, _messages.length);
        }
        
        debugPrint('Chat history merged: ${newMessages.length} new messages added');
      } else {
        debugPrint('Chat history: No new messages to add');
      }
      
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
        // Append at the end (older messages appear at the top of the scrolled list with reverse: true)
        _messages.addAll(moreMessages);
        
        // Ensure they are still sorted correctly (newest first)
        _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
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
    WidgetsBinding.instance.removeObserver(this);
    _messageSubscription?.cancel();
    _connectionSubscription?.cancel();
    _chatService.dispose();
    super.dispose();
  }
}
