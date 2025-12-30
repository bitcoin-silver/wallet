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

  ChatMessage({
    this.id,
    required this.walletAddress,
    this.nickname,
    required this.message,
    required this.timestamp,
    this.messageType = 'user',
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'],
      walletAddress: json['wallet_address'] ?? '',
      nickname: json['nickname'],
      message: json['message'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
      messageType: json['message_type'] ?? 'user',
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
    };
  }

  bool get isSystem => messageType == 'system';
  bool get isUser => messageType == 'user';
}

class ChatService {
  WebSocketChannel? _channel;
  final _messagesController = StreamController<ChatMessage>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusMessageController = StreamController<String>.broadcast();

  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isConnecting = false;
  bool _isConnected = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _reconnectDelay = Duration(seconds: 3);

  String? _walletAddress;
  String? _nickname;

  // Streams
  Stream<ChatMessage> get messages => _messagesController.stream;
  Stream<bool> get connectionStatus => _connectionController.stream;
  Stream<Map<String, dynamic>> get typingStatus => _typingController.stream;
  Stream<String> get statusMessage => _statusMessageController.stream;

  bool get isConnected => _isConnected;

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

      // Send authentication message
      _sendAuth();

      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _connectionController.add(true);
      _statusMessageController.add('Connected');

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
      if (_nickname != null) 'nickname': _nickname,
    };

    _channel!.sink.add(jsonEncode(authMessage));
  }

  /// Handle incoming WebSocket messages
  void _onMessage(dynamic data) {
    try {
      final json = jsonDecode(data.toString());
      final type = json['type'];

      switch (type) {
        case 'message':
          final message = ChatMessage.fromJson(json);
          _messagesController.add(message);
          break;

        case 'system':
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
          debugPrint('Authentication successful: ${json['message']}');
          debugPrint('Active users: ${json['activeUsers']}');
          break;

        case 'error':
          debugPrint('Server error: ${json['message']}');
          break;

        case 'history':
          final messages = (json['messages'] as List)
              .map((m) => ChatMessage.fromJson(m))
              .toList();
          for (var message in messages) {
            _messagesController.add(message);
          }
          break;

        default:
          debugPrint('Unknown message type: $type');
      }
    } catch (error) {
      debugPrint('Error parsing WebSocket message: $error');
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
          _channel!.sink.add(jsonEncode({'type': 'ping'}));
        } catch (error) {
          debugPrint('Ping error: $error');
        }
      }
    });
  }

  /// Send a chat message
  Future<bool> sendMessage(String message) async {
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
        if (_nickname != null) 'nickname': _nickname,
        'message': message.trim(),
      };

      _channel!.sink.add(jsonEncode(messageData));
      return true;
    } catch (error) {
      debugPrint('Error sending message: $error');
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
  Future<bool> setNickname(String nickname) async {
    try {
      final url = '${Config.apiBaseUrl}/api/chat/set-nickname';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': Config.apiKey,
        },
        body: jsonEncode({
          'wallet_address': _walletAddress,
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
          final price = data['price'] as double;
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
    }
  }
}
