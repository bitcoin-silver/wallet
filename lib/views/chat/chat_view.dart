// ================================================================================
// BTCS MESSENGER - CHAT VIEW
// ================================================================================
// Created: 2025-11-11
// Purpose: Beautiful chat UI with real-time messaging
// ================================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/chat_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../providers/addressbook_provider.dart';
import '../../services/chat_service.dart';
import '../../widgets/app_background.dart';
import '../../models/addressbook_entry.dart';
import 'dart:async';

class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();
  Timer? _typingTimer;
  bool _isTyping = false;
  bool _showScrollButton = false;
  ChatProvider? _chatProvider;
  bool _initialScrollDone = false;
  double _previousKeyboardHeight = 0;

  @override
  void initState() {
    super.initState();

    // Initialize chat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeChat();
    });

    // Listen to scroll position
    _scrollController.addListener(_onScroll);

    // Listen to focus changes to handle keyboard
    _messageFocusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    // When focus changes, scroll to bottom after a short delay
    // to allow keyboard animation to complete
    if (_messageFocusNode.hasFocus) {
      Future.delayed(Duration(milliseconds: 300), () {
        if (mounted && _scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Store reference to ChatProvider for safe access in dispose
    _chatProvider ??= Provider.of<ChatProvider>(context, listen: false);
  }

  void _initializeChat() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final addressbookProvider = Provider.of<AddressbookProvider>(context, listen: false);

    if (walletProvider.address == null) {
      return;
    }

    // Check if user has a username in addressbook
    try {
      final addressbookEntry = await addressbookProvider.searchByAddress(walletProvider.address!);

      if (addressbookEntry != null && addressbookEntry.username.isNotEmpty) {
        // User has a username - connect with it
        if (!chatProvider.isConnected) {
          await chatProvider.connect(
            walletProvider.address!,
            nickname: addressbookEntry.username,
          );
        }

        // Reload chat history when entering chat
        await chatProvider.loadHistory();
      } else {
        // User doesn't have a username - prompt to register
        if (mounted) {
          _showUsernamePrompt();
          return;
        }
      }
    } catch (e) {
      // Error checking username - might not be registered
      if (mounted) {
        _showUsernamePrompt();
        return;
      }
    }

    // Use microtask to avoid calling setState during build
    if (mounted) {
      Future.microtask(() {
        if (mounted) {
          chatProvider.markChatAsOpened();
          // Scroll to bottom after marking chat as opened
          _performInitialScroll();
        }
      });
    }
  }

  // Perform initial scroll to bottom after messages are loaded
  void _performInitialScroll() {
    if (_initialScrollDone) return;

    // Wait for the list to be fully built, then scroll
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      // Try scrolling after a short delay to ensure layout is complete
      Future.delayed(Duration(milliseconds: 100), () {
        if (!mounted || !_scrollController.hasClients) return;

        try {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          _initialScrollDone = true;
          debugPrint('✅ Initial scroll to bottom completed');
        } catch (e) {
          debugPrint('⚠️ Scroll error: $e');
        }
      });
    });
  }

  void _showUsernamePrompt() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Colors.cyanAccent.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Colors.white, Color(0xFFC0C0C0)],
          ).createShader(bounds),
          child: const Text(
            'Username Required',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'To use the messenger, you need to register a username first.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Go to Address Book and register your username, then come back to chat.',
              style: TextStyle(
                color: Colors.cyanAccent.withValues(alpha: 0.8),
                fontSize: 13,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Close chat view
            },
            child: const Text(
              'GO TO ADDRESS BOOK',
              style: TextStyle(
                color: Colors.cyanAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onScroll() {
    // Show scroll-to-bottom button if not at bottom
    final isAtBottom = _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100;

    if (_showScrollButton != !isAtBottom) {
      setState(() {
        _showScrollButton = !isAtBottom;
      });
    }

    // Load more messages when scrolling to top
    if (_scrollController.position.pixels <= 100) {
      _loadMoreMessages();
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;

    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _loadMoreMessages() {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    if (!chatProvider.isLoading) {
      chatProvider.loadMore();
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    chatProvider.sendMessage(text);

    _messageController.clear();
    _stopTyping();

    // Scroll to bottom after sending message
    Future.delayed(Duration(milliseconds: 200), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTextChanged(String text) {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    if (text.isNotEmpty && !_isTyping) {
      _isTyping = true;
      chatProvider.sendTypingIndicator(true);
    }

    // Reset typing timer
    _typingTimer?.cancel();
    _typingTimer = Timer(Duration(seconds: 2), _stopTyping);
  }

  void _stopTyping() {
    if (_isTyping) {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      chatProvider.sendTypingIndicator(false);
      _isTyping = false;
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    _typingTimer?.cancel();

    // Schedule markChatAsClosed to run after dispose completes
    // This avoids calling notifyListeners during widget tree disposal
    Future.microtask(() {
      _chatProvider?.markChatAsClosed();
    });

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get keyboard height
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    // Detect keyboard visibility changes and auto-scroll
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (keyboardHeight != _previousKeyboardHeight) {
        _previousKeyboardHeight = keyboardHeight;

        // If keyboard is appearing (height > 0), scroll to bottom
        if (keyboardHeight > 0 && _scrollController.hasClients) {
          Future.delayed(Duration(milliseconds: 100), () {
            if (mounted && _scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          });
        }
      }
    });

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _buildMessagesList(),
              ),
              _buildMessageInput(keyboardHeight),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF1A1A1A).withValues(alpha: 0.9),
                const Color(0xFF1A1A1A).withValues(alpha: 0.7),
              ],
            ),
            border: Border(
              bottom: BorderSide(
                color: const Color(0xFFC0C0C0).withValues(alpha: 0.2),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Back button
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 12),
              // Chat info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Colors.white, Color(0xFFC0C0C0)],
                      ).createShader(bounds),
                      child: const Text(
                        'BTCS Messenger',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: chatProvider.isConnected
                                ? Colors.cyanAccent
                                : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          chatProvider.isConnected
                              ? 'Connected'
                              : 'Connecting...',
                          style: TextStyle(
                            color: chatProvider.isConnected
                                ? Colors.cyanAccent
                                : Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessagesList() {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, child) {
        if (chatProvider.isLoading && chatProvider.messages.isEmpty) {
          return Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
            ),
          );
        }

        if (chatProvider.messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 64,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'No messages yet',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Be the first to say something!',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        return Stack(
          children: [
            ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 80, // Extra padding to ensure last message is visible above input
              ),
              itemCount: chatProvider.messages.length,
              itemBuilder: (context, index) {
                final message = chatProvider.messages[index];
                return _buildMessageBubble(message, chatProvider);
              },
            ),
            // Scroll to bottom button
            if (_showScrollButton)
              Positioned(
                bottom: 16,
                right: 16,
                child: FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.cyanAccent,
                  onPressed: _scrollToBottom,
                  child: const Icon(
                    Icons.arrow_downward,
                    color: Colors.black,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message, ChatProvider chatProvider) {
    final isMyMessage = chatProvider.isMyMessage(message);
    final displayName = chatProvider.getDisplayName(message);

    if (message.isSystem) {
      return _buildSystemMessage(message);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMyMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMyMessage) _buildAvatar(displayName),
          if (!isMyMessage) const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMyMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Name and timestamp
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
                        style: TextStyle(
                          color: isMyMessage
                              ? Colors.cyanAccent
                              : const Color(0xFFC0C0C0),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(message.timestamp),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                // Message bubble with long-press to save to address book
                GestureDetector(
                  onLongPress: !isMyMessage
                      ? () => _showAddToAddressBookDialog(message, displayName)
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isMyMessage
                            ? [
                                const Color(0xFF00E5FF).withValues(alpha: 0.3),
                                const Color(0xFF00E5FF).withValues(alpha: 0.2),
                              ]
                            : [
                                const Color(0xFF2A2A2A),
                                const Color(0xFF1A1A1A),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isMyMessage
                            ? Colors.cyanAccent.withValues(alpha: 0.3)
                            : const Color(0xFFC0C0C0).withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Linkify(
                      onOpen: (link) async {
                        final uri = Uri.parse(link.url);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      text: message.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.4,
                      ),
                      linkStyle: TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 15,
                        height: 1.4,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isMyMessage) const SizedBox(width: 8),
          if (isMyMessage) _buildAvatar(displayName),
        ],
      ),
    );
  }

  Widget _buildSystemMessage(ChatMessage message) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.cyanAccent.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Linkify(
          onOpen: (link) async {
            final uri = Uri.parse(link.url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );
            }
          },
          text: message.message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 15,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w500,
          ),
          linkStyle: TextStyle(
            color: Colors.cyanAccent.withValues(alpha: 0.9),
            fontSize: 15,
            fontStyle: FontStyle.italic,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String name) {
    // Skip @ symbol if present for avatar letter
    final avatarLetter = name.startsWith('@') ? name[1].toUpperCase() : name[0].toUpperCase();

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            Colors.cyanAccent.withValues(alpha: 0.3),
            Colors.cyanAccent.withValues(alpha: 0.1),
          ],
        ),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.cyanAccent.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Center(
        child: Text(
          avatarLetter,
          style: const TextStyle(
            color: Colors.cyanAccent,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput(double keyboardHeight) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 100),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1A1A).withValues(alpha: 0.9),
            const Color(0xFF1A1A1A).withValues(alpha: 0.7),
          ],
        ),
        border: Border(
          top: BorderSide(
            color: const Color(0xFFC0C0C0).withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Text input
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFFC0C0C0).withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _messageController,
                focusNode: _messageFocusNode,
                onChanged: _onTextChanged,
                onSubmitted: (_) => _sendMessage(),
                style: const TextStyle(color: Colors.white),
                maxLength: 500,
                buildCounter: (context,
                    {required currentLength, required isFocused, maxLength}) {
                  return null; // Hide counter
                },
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Send button
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF00E5FF),
                  Colors.cyanAccent,
                ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.black),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddToAddressBookDialog(ChatMessage message, String displayName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Colors.cyanAccent.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        title: Row(
          children: [
            Icon(Icons.person_add, color: Colors.cyanAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Add to Address Book',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Save this user to your address book?',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.cyanAccent.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person, size: 16, color: Colors.cyanAccent),
                      const SizedBox(width: 8),
                      Text(
                        'Username:',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    displayName,
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.account_balance_wallet,
                          size: 16, color: Colors.cyanAccent),
                      const SizedBox(width: 8),
                      Text(
                        'Address:',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${message.walletAddress.substring(0, 20)}...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final addressbookProvider =
                  Provider.of<AddressbookProvider>(context, listen: false);

              // Create address book entry
              final entry = AddressbookEntry(
                username: displayName,
                address: message.walletAddress,
                isFavorite: true,
              );

              // Add to favorites (address book)
              await addressbookProvider.addToFavorites(entry);

              if (!context.mounted) return;
              Navigator.pop(context);

              // Show success message
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✓ $displayName added to Address Book'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text('Add'),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return DateFormat('MMM d, HH:mm').format(timestamp);
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
