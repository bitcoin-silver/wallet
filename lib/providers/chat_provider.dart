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
  final Set<int> _messageIds = {};
  bool _isConnected = false;
  bool _isLoading = false;
  String? _currentWalletAddress;
  String? _currentNickname;
  int _unreadCount = 0;
  int _userCount = 0;
  String? _latestSystemMessage;
  final Map<String, String> _typingUsers = {};
  final Map<String, Timer> _typingTimers = {};
  bool _isChatOpen = false;
  String? _serverSystemMessage;

  StreamSubscription? _messageSubscription;
  StreamSubscription? _historySubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _userCountSubscription;
  StreamSubscription? _serverSystemMessageSubscription;

  // Getters
  List<ChatMessage> get messages => _messages;
  bool get isConnected => _isConnected;
  bool get isLoading => _isLoading;
  String? get currentNickname => _currentNickname;
  int get unreadCount => _unreadCount;
  int get userCount => _userCount;
  String? get latestSystemMessage => _latestSystemMessage;
  Map<String, String> get typingUsers => _typingUsers;
  bool get isChatOpen => _isChatOpen;
  String? get serverSystemMessage => _serverSystemMessage;

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
      if (message.id != null && _messageIds.contains(message.id)) {
        return;
      }

      if (message.id != null) {
        _messageIds.add(message.id!);
      }

      // Filter out connection/disconnection messages to reduce clutter
      if (message.isSystem || message.messageType == 'error') {
        final msg = message.message.toLowerCase();

        // Check for legacy warning from server
        if (msg.contains('update') && (msg.contains('outdated') || msg.contains('version'))) {
          _latestSystemMessage = "⚠️ Please update your app to continue chatting!";
          Future.microtask(() => notifyListeners());
          return;
        }

        if (msg.contains('connected') ||
            msg.contains('disconnected') ||
            msg.contains('joined') ||
            msg.contains('left')) {
          debugPrint('ChatProvider: 🤫 Moving system message to header: ${message.message}');
          _latestSystemMessage = message.message;
          Future.microtask(() => notifyListeners());
          return;
        }
      }

      // With reverse: true in ListView, newest message should be at index 0
      _messages.insert(0, message);
      debugPrint('ChatProvider: 📥 Added message. Total: ${_messages.length}');

      // Handle notifications and unread count if chat is not open
      if (!_isChatOpen && message.walletAddress != _currentWalletAddress) {
        // ONLY notify for messages sent in the last 60 seconds to avoid history flooding
        // and check if it's not a system message
        final isRecent = DateTime.now().difference(message.timestamp).inSeconds.abs() < 60;

        if (!message.isSystem && isRecent) {
          _unreadCount++;
          final username = message.nickname ??
              '${message.walletAddress.substring(0, 8)}...';

          _notificationService.showMessageNotification(
            username: username,
            message: message.message,
            unreadCount: _unreadCount,
          );
        } else if (!message.isSystem) {
          // Still increment unread count for non-recent messages if they are new to us
          _unreadCount++;
        }
      }

      // Schedule notifyListeners to avoid calling during build
      Future.microtask(() => notifyListeners());
    });

    // Listen to history batch from WebSocket (as a fallback or update)
    _historySubscription = _chatService.historyMessages.listen((history) {
      _processHistoryBatch(history);
    });

    // Listen to user count
    _userCountSubscription = _chatService.userCountStream.listen((count) {
      _userCount = count;
      Future.microtask(() => notifyListeners());
    });

    _serverSystemMessageSubscription = _chatService.serverSystemMessage.listen((message) {
      _serverSystemMessage = message;
      Future.microtask(() => notifyListeners());
    });

    // Listen to typing status
    _chatService.typingStatus.listen((data) {
      final walletAddress = data['wallet_address'] as String;
      final nickname = data['nickname'] as String?;
      final isTyping = data['typing'] as bool;

      if (walletAddress == _currentWalletAddress) return;

      final displayName = nickname ?? '${walletAddress.substring(0, 8)}...';

      // Cancel existing timer for this user
      _typingTimers[walletAddress]?.cancel();

      if (isTyping) {
        _typingUsers[walletAddress] = displayName;
        // Auto-remove after 6 seconds of no updates
        _typingTimers[walletAddress] = Timer(const Duration(seconds: 6), () {
          _typingUsers.remove(walletAddress);
          _typingTimers.remove(walletAddress);
          notifyListeners();
        });
      } else {
        _typingUsers.remove(walletAddress);
        _typingTimers.remove(walletAddress);
      }
      notifyListeners();
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
  Future<bool> sendMessage(String message, {ChatMessage? replyTo}) async {
    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) {
      return false;
    }

    // Handle bot commands locally
    if (trimmedMessage.startsWith('/')) {
      final command = trimmedMessage.toLowerCase().split(' ')[0];
      
      switch (command) {
        case '/price':
          return _handlePriceCommand();
        case '/help':
          return _handleHelpCommand();
        case '/info':
          return _handleInfoCommand();
      }
    }

    return await _chatService.sendMessage(trimmedMessage, replyTo: replyTo);
  }

  Future<bool> _handlePriceCommand() async {
    final price = await _chatService.getCurrentPrice();
    final message = price != null
        ? '📊 Current BTCS Price: $price USD\nSource: LiveCoinWatch'
        : '❌ Unable to fetch current price. Please try again later.';
    
    _addLocalSystemMessage(message, 'BTCS Price Bot');
    return true;
  }

  Future<bool> _handleHelpCommand() async {
    const helpText = '🤖 **BTCS Messenger Help**\n\n'
        'Available Commands:\n'
        '• `/price` - Show current BTCS price\n'
        '• `/info` - About this messenger\n'
        '• `/help` - Show this menu\n\n'
        'Features:\n'
        '• **Reply**: Long-press any message and select "Reply"\n'
        '• **Copy**: Long-press to copy message text\n'
        '• **Add Contact**: Long-press a user\'s message to save them\n'
        '• **Online Count**: See how many users are active';

    _addLocalSystemMessage(helpText, 'BTCS Help Bot');
    return true;
  }

  Future<bool> _handleInfoCommand() async {
    const infoText = 'ℹ️ **About BTCS Messenger**\n\n'
        'A secure, real-time decentralized chat built for the Bitcoin Silver community.\n\n'
        '• **Security**: Messages are identified by wallet address.\n'
        '• **Privacy**: No central account required.\n'
        '• **Speed**: Powered by WebSocket technology.';

    _addLocalSystemMessage(infoText, 'BTCS Info Bot');
    return true;
  }

  void _addLocalSystemMessage(String text, String botName) {
    final botMessage = ChatMessage(
      walletAddress: 'SYSTEM',
      nickname: botName,
      message: text,
      timestamp: DateTime.now(),
      messageType: 'system',
    );
    _messages.insert(0, botMessage);
    if (botMessage.id != null) _messageIds.add(botMessage.id!);
    Future.microtask(() => notifyListeners());
  }

  /// Process a batch of history messages efficiently
  void _processHistoryBatch(List<ChatMessage> history) {
    if (history.isEmpty) return;
    
    // Filter history to only include messages we don't already have
    final newMessages = history.where((m) {
      final isDuplicate = m.id != null && _messageIds.contains(m.id);
      if (isDuplicate) return false;

      // Filter connection messages
      if (m.isSystem) {
        final msg = m.message.toLowerCase();
        return !(msg.contains('connected') ||
            msg.contains('disconnected') ||
            msg.contains('joined') ||
            msg.contains('left'));
      }

      return true;
    }).toList();

    if (newMessages.isNotEmpty) {
      // Add IDs to set
      for (var m in newMessages) {
        if (m.id != null) _messageIds.add(m.id!);
      }

      _messages.addAll(newMessages);
      _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      // Keep memory managed
      if (_messages.length > 300) {
        final toRemove = _messages.sublist(300);
        for (var m in toRemove) {
          if (m.id != null) _messageIds.remove(m.id);
        }
        _messages.removeRange(300, _messages.length);
      }
      
      debugPrint('ChatProvider: Processed batch of ${newMessages.length} messages. New total: ${_messages.length}');
      notifyListeners();
    }
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
      _processHistoryBatch(history);
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
      _processHistoryBatch(moreMessages);
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
    _historySubscription?.cancel();
    _connectionSubscription?.cancel();
    _userCountSubscription?.cancel();
    _serverSystemMessageSubscription?.cancel();
    _typingTimers.forEach((_, timer) => timer.cancel());
    _chatService.dispose();
    super.dispose();
  }
}
