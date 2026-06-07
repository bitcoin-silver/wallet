// ================================================================================
// BTCS MESSENGER - CHAT SERVICE
// ================================================================================
// Created: 2025-11-11
// Purpose: WebSocket connection management for real-time chat
// ================================================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

class ChatMessage {
  final int? id;
  final String walletAddress;
  final String? nickname;
  final String message;
  final DateTime timestamp;
  final String messageType;
  final String? replyToId; // ID of the message being replied to
  final String? replyToText; // Snippet of the message being replied to
  final String? replyToUser; // User being replied to

  ChatMessage({
    this.id,
    required this.walletAddress,
    this.nickname,
    required this.message,
    required this.timestamp,
    this.messageType = 'user',
    this.replyToId,
    this.replyToText,
    this.replyToUser,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'],
      walletAddress: json['wallet_address'] ?? '',
      nickname: json['nickname'],
      message: json['message'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
      messageType: json['message_type'] ?? 'user',
      replyToId: json['reply_to_id']?.toString(),
      replyToText: json['reply_to_text'],
      replyToUser: json['reply_to_user'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'wallet_address': walletAddress,
      if (nickname != null) 'nickname': nickname,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'message_type': messageType,
      if (replyToId != null) 'reply_to_id': replyToId,
      if (replyToText != null) 'reply_to_text': replyToText,
      if (replyToUser != null) 'reply_to_user': replyToUser,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessage &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          walletAddress == other.walletAddress &&
          message == other.message &&
          timestamp == other.timestamp;

  @override
  int get hashCode =>
      id.hashCode ^
      walletAddress.hashCode ^
      message.hashCode ^
      timestamp.hashCode;

  bool get isSystem => messageType == 'system';
  bool get isUser => messageType == 'user';
}

class ChatService {
  WebSocketChannel? _channel;
  final _messagesController = StreamController<ChatMessage>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusMessageController = StreamController<String>.broadcast();
  final _userCountController = StreamController<int>.broadcast();
  final _serverSystemMessageController = StreamController<String?>.broadcast();
  final _historyController = StreamController<List<ChatMessage>>.broadcast();

  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isConnecting = false;
  bool _isConnected = false;
  int _reconnectAttempts = 0;
  int _userCount = 0;
  String? _serverSystemMessage;
  static const int _maxReconnectAttempts = 10;
  static const Duration _reconnectDelay = Duration(seconds: 3);

  String? _walletAddress;
  String? _nickname;

  // Streams
  Stream<ChatMessage> get messages => _messagesController.stream;
  Stream<bool> get connectionStatus => _connectionController.stream;
  Stream<Map<String, dynamic>> get typingStatus => _typingController.stream;
  Stream<String> get statusMessage => _statusMessageController.stream;
  Stream<int> get userCountStream => _userCountController.stream;
  Stream<String?> get serverSystemMessage => _serverSystemMessageController.stream;
  Stream<List<ChatMessage>> get historyMessages => _historyController.stream;

  bool get isConnected => _isConnected;
  int get userCount => _userCount;

  /// Initialize and connect to WebSocket
  Future<void> connect(String walletAddress, {String? nickname}) async {
    if (_isConnecting || _isConnected) {
      debugPrint('Already connected or connecting');
      return;
    }

    _walletAddress = walletAddress;
    _nickname = nickname;
    _isConnecting = true;
    _statusMessageController.add('Connecting...');

    try {
      // WebSocket URL (wss for production, ws for local dev)
      final wsUrl = '${Config.apiBaseUrl.replaceFirst('http', 'ws')}/ws';
      debugPrint('Connecting to WebSocket: $wsUrl');

      // Create connection
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Wait for connection to be ready with timeout
      await _channel!.ready.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _channel?.sink.close();
          _channel = null;
          throw TimeoutException('WebSocket connection timeout after 10 seconds');
        },
      );

      // Listen to messages
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDisconnect,
        cancelOnError: false,
      );

      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _connectionController.add(true);
      _statusMessageController.add('Connected');
      
      debugPrint('DEBUG_WS: 🚀 WebSocket connected and ready');

      // Send authentication message
      _sendAuth();

      // Start ping timer to keep connection alive
      _startPingTimer();

      debugPrint('WebSocket connected successfully');
    } catch (error) {
      debugPrint('WebSocket connection error: $error');
      _isConnecting = false;
      _isConnected = false;
      _channel?.sink.close();
      _channel = null;
      _connectionController.add(false);

      // Emit user-friendly error message
      if (_reconnectAttempts < _maxReconnectAttempts) {
        _statusMessageController.add('Connection failed, retrying...');
      } else {
        _statusMessageController.add('Unable to connect');
      }

      _scheduleReconnect();
    }
  }

  /// Send authentication message
  void _sendAuth() {
    if (_channel == null) return;

    final authMessage = {
      'type': 'auth',
      'wallet_address': _walletAddress,
      'chat_secret': Config.chatSecret,
      if (_nickname != null) 'nickname': _nickname,
    };

    debugPrint('DEBUG_WS: 📤 Sending Auth: ${jsonEncode(authMessage)}');
    _channel!.sink.add(jsonEncode(authMessage));
  }

  /// Handle incoming WebSocket messages
  void _onMessage(dynamic data) {
    debugPrint('DEBUG_WS: 📥 Incoming WebSocket: $data');
    try {
      final json = jsonDecode(data.toString());
      final type = json['type'];

      switch (type) {
        case 'message':
          final message = ChatMessage.fromJson(json);
          _messagesController.add(message);
          break;

        case 'system':
          if (json['user_count'] != null) {
            _userCount = json['user_count'];
            _userCountController.add(_userCount);
          }
          
          final message = ChatMessage(
            walletAddress: 'SYSTEM',
            nickname: 'System',
            message: json['message'],
            timestamp: DateTime.parse(json['timestamp']),
            messageType: 'system',
          );
          _messagesController.add(message);
          break;

        case 'typing':
          _typingController.add({
            'wallet_address': json['wallet_address'],
            'nickname': json['nickname'],
            'typing': json['typing'],
          });
          break;

        case 'auth_success':
          debugPrint('DEBUG_WS: ✅ Auth Success: ${json['message']}');
          if (json['activeUsers'] != null) {
            _userCount = json['activeUsers'];
            _userCountController.add(_userCount);
          }
          break;

        case 'pong':
          // Ping-pong successful
          if (json['system_message'] != null) {
            _serverSystemMessage = json['system_message'];
            _serverSystemMessageController.add(_serverSystemMessage);
          } else if (json['system_message'] == null) {
            _serverSystemMessage = null;
            _serverSystemMessageController.add(null);
          }
          break;

        case 'error':
          debugPrint('DEBUG_WS: ❌ Server error: ${json['message']}. Full JSON: $json');
          break;

        case 'history':
          final messages = (json['messages'] as List)
              .map((m) => ChatMessage.fromJson(m))
              .toList();
          
          debugPrint('DEBUG_WS: 📥 Received history batch of ${messages.length} messages. Sending to history stream.');
          _historyController.add(messages);
          break;

        default:
          debugPrint('DEBUG_WS: ❓ Unknown message type: $type. Full message: $json');
      }
    } catch (error) {
      debugPrint('DEBUG_WS: 💀 Error parsing WebSocket message: $error');
    }
  }

  /// Handle WebSocket errors
  void _onError(Object error) {
    debugPrint('WebSocket error: $error');
    _isConnected = false;
    _connectionController.add(false);
    _scheduleReconnect();
  }

  /// Handle WebSocket disconnection
  void _onDisconnect() {
    debugPrint('WebSocket disconnected');
    _isConnected = false;
    _connectionController.add(false);
    _pingTimer?.cancel();
    _serverSystemMessageController.add(null);
    _scheduleReconnect();
  }

  /// Schedule reconnection with exponential backoff
  void _scheduleReconnect() {
    if (_reconnectTimer != null && _reconnectTimer!.isActive) {
      return; // Already scheduled
    }

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('Max reconnect attempts reached');
      _statusMessageController.add('Unable to connect');
      return;
    }

    _reconnectAttempts++;
    final delay = _reconnectDelay * _reconnectAttempts;

    debugPrint('Reconnecting in ${delay.inSeconds} seconds (attempt $_reconnectAttempts)');
    _statusMessageController.add('Retrying... ($_reconnectAttempts/$_maxReconnectAttempts)');

    _reconnectTimer = Timer(delay, () {
      if (_walletAddress != null && !_isConnected) {
        connect(_walletAddress!, nickname: _nickname);
      }
    });
  }

  /// Start ping timer to keep connection alive
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (_isConnected && _channel != null) {
        try {
          debugPrint('DEBUG_WS: 📤 Sending Ping');
          _channel!.sink.add(jsonEncode({
            'type': 'ping',
            'chat_secret': Config.chatSecret,
          }));
        } catch (error) {
          debugPrint('DEBUG_WS: 💀 Ping error: $error');
          // If ping fails, the connection is likely dead
          _onDisconnect();
        }
      }
    });
  }

  /// Send a chat message
  Future<bool> sendMessage(String message, {ChatMessage? replyTo}) async {
    if (!_isConnected || _channel == null) {
      debugPrint('Not connected to WebSocket');
      return false;
    }

    if (message.trim().isEmpty || message.length > 500) {
      debugPrint('Invalid message length');
      return false;
    }

    try {
      final messageData = {
        'type': 'message',
        'wallet_address': _walletAddress,
        'chat_secret': Config.chatSecret,
        if (_nickname != null) 'nickname': _nickname,
        'message': message.trim(),
        if (replyTo != null) ...{
          'reply_to_id': replyTo.id?.toString(),
          'reply_to_text': replyTo.message.length > 50 ? '${replyTo.message.substring(0, 47)}...' : replyTo.message,
          'reply_to_user': replyTo.nickname ?? replyTo.walletAddress.substring(0, 8),
        },
      };

      debugPrint('DEBUG_WS: 📤 Sending Message: ${jsonEncode(messageData)}');
      _channel!.sink.add(jsonEncode(messageData));
      return true;
    } catch (error) {
      debugPrint('DEBUG_WS: 💀 Error sending message: $error');
      return false;
    }
  }

  /// Send typing indicator
  void sendTypingIndicator(bool typing) {
    if (!_isConnected || _channel == null) return;

    try {
      final typingData = {
        'type': 'typing',
        'wallet_address': _walletAddress,
        'chat_secret': Config.chatSecret,
        if (_nickname != null) 'nickname': _nickname,
        'typing': typing,
      };

      _channel!.sink.add(jsonEncode(typingData));
    } catch (error) {
      debugPrint('Error sending typing indicator: $error');
    }
  }

  /// Request message history
  void requestHistory({int limit = 100, int offset = 0}) {
    if (!_isConnected || _channel == null) return;

    try {
      final historyRequest = {
        'type': 'history',
        'chat_secret': Config.chatSecret,
        'limit': limit,
        'offset': offset,
      };

      _channel!.sink.add(jsonEncode(historyRequest));
    } catch (error) {
      debugPrint('Error requesting history: $error');
    }
  }

  /// Fetch message history from REST API
  Future<List<ChatMessage>> fetchHistory({int limit = 100, int offset = 0}) async {
    try {
      final url = '${Config.apiBaseUrl}/api/chat/history?limit=$limit&offset=$offset';
      debugPrint('Fetching chat history from: $url');
      debugPrint('API Key length: ${Config.apiKey.length}');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'X-API-Key': Config.apiKey,
          'X-Chat-Secret': Config.chatSecret,
        },
      ).timeout(
        Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Chat history request timeout after 10 seconds');
        },
      );

      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('✅ History response received');
        final data = jsonDecode(response.body);
        if (data['success']) {
          final messages = (data['messages'] as List)
              .map((m) => ChatMessage.fromJson(m))
              .toList();
          debugPrint('Loaded ${messages.length} messages from history');
          return messages;
        }
      } else if (response.statusCode == 401) {
        debugPrint('⚠️ API Key authentication failed! Check dart_defines.json');
      }
      return [];
    } catch (error) {
      debugPrint('❌ Error fetching history: $error');
      return [];
    }
  }

  /// Set user nickname
  Future<bool> setNickname(String nickname, {String? walletAddress}) async {
    try {
      final address = walletAddress ?? _walletAddress;
      if (address == null) {
        debugPrint('Error setting nickname: No wallet address available');
        return false;
      }

      final url = '${Config.apiBaseUrl}/api/chat/set-nickname';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': Config.apiKey,
          'X-Chat-Secret': Config.chatSecret,
        },
        body: jsonEncode({
          'wallet_address': address,
          'nickname': nickname,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          _nickname = nickname;
          return true;
        }
      }
      return false;
    } catch (error) {
      debugPrint('Error setting nickname: $error');
      return false;
    }
  }

  /// Get user nickname
  Future<String?> getNickname(String address) async {
    try {
      final url = '${Config.apiBaseUrl}/api/chat/nickname/$address';
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'X-API-Key': Config.apiKey,
          'X-Chat-Secret': Config.chatSecret,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          return data['nickname'];
        }
      }
      return null;
    } catch (error) {
      debugPrint('Error getting nickname: $error');
      return null;
    }
  }

  /// Get current BTCS price
  Future<String?> getCurrentPrice() async {
    try {
      final url = '${Config.apiBaseUrl}/api/price/current';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          final price = (data['price'] as num).toDouble();
          // Format price nicely
          final formattedPrice = price < 0.01
              ? price.toStringAsFixed(8)
              : price < 1
                  ? price.toStringAsFixed(6)
                  : price.toStringAsFixed(4);
          return '\$$formattedPrice';
        }
      }
      return null;
    } catch (error) {
      debugPrint('Error getting price: $error');
      return null;
    }
  }

  /// Disconnect and cleanup
  void disconnect() {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _isConnected = false;
    _isConnecting = false;
    _connectionController.add(false);
    debugPrint('WebSocket disconnected manually');
  }

  /// Dispose resources
  void dispose() {
    try {
      disconnect();
    } catch (e) {
      debugPrint('⚠️ Error during disconnect: $e');
    } finally {
      // Always close stream controllers, even if disconnect fails
      try {
        if (!_messagesController.isClosed) {
          _messagesController.close();
        }
      } catch (e) {
        debugPrint('⚠️ Error closing messagesController: $e');
      }

      try {
        if (!_connectionController.isClosed) {
          _connectionController.close();
        }
      } catch (e) {
        debugPrint('⚠️ Error closing connectionController: $e');
      }

      try {
        if (!_typingController.isClosed) {
          _typingController.close();
        }
      } catch (e) {
        debugPrint('⚠️ Error closing typingController: $e');
      }

      try {
        if (!_statusMessageController.isClosed) {
          _statusMessageController.close();
        }
      } catch (e) {
        debugPrint('⚠️ Error closing statusMessageController: $e');
      }

      try {
        if (!_userCountController.isClosed) {
          _userCountController.close();
        }
      } catch (e) {
        debugPrint('⚠️ Error closing userCountController: $e');
      }

      try {
        if (!_historyController.isClosed) {
          _historyController.close();
        }
      } catch (e) {
        debugPrint('⚠️ Error closing historyController: $e');
      }
    }
  }
}
