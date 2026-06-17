// ================================================================================
// BTCS MESSENGER - CHAT VIEW
// ================================================================================
// Created: 2025-11-11
// Purpose: Beautiful chat UI with real-time messaging
// ================================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../home/addressbook_view.dart';
import 'dart:async';
import 'dart:ui' as ui;

class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double speed;

  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.speed = 40.0,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _textWidth = 0;
  double _textHeight = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _controller.addStatusListener(_handleStatusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _handleStatusChange(AnimationStatus status) async {
    if (status == AnimationStatus.completed) {
      // Wait 10 seconds at the end of the scroll
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        _controller.forward(from: 0.0);
      }
    }
  }

  @override
  void didUpdateWidget(MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _measure();
    }
  }

  /// Measures the text dimensions.
  void _measure() {
    if (!mounted) return;

    final textScaler = MediaQuery.textScalerOf(context);
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: ui.TextDirection.ltr,
      textScaler: textScaler,
    )..layout();

    if (mounted) {
      setState(() {
        _textWidth = painter.width;
        _textHeight = painter.height;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatusChange);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerWidth = constraints.maxWidth;
        final shouldScroll = _textWidth > containerWidth;

        if (!shouldScroll || _textWidth <= 0) {
          if (_controller.isAnimating) _controller.stop();
          return Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        // Total distance to travel: from right of container to fully off-screen left
        // Added 100px buffer to ensure it's completely gone before the 10s pause
        final totalDistance = containerWidth + _textWidth + 100;
        final duration = Duration(
          milliseconds: (totalDistance / widget.speed * 1000).toInt(),
        );

        if (_controller.duration != duration) {
          _controller.duration = duration;
        }

        if (!_controller.isAnimating && _controller.status != AnimationStatus.completed) {
          _controller.forward();
        }

        return SizedBox(
          height: _textHeight,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, __) {
                // Starts at containerWidth, ends at -(_textWidth + 100)
                final xOffset = containerWidth - (_controller.value * totalDistance);
                return OverflowBox(
                  maxWidth: double.infinity,
                  maxHeight: _textHeight,
                  alignment: Alignment.centerLeft,
                  child: Transform.translate(
                    offset: Offset(xOffset, 0),
                    child: Text(
                      widget.text,
                      style: widget.style,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class ChatView extends StatefulWidget {
  final bool showBackButton;
  const ChatView({super.key, this.showBackButton = true});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();
  Timer? _typingTimer;
  bool _isTyping = false;
  bool _showScrollButton = false;
  ChatProvider? _chatProvider;
  ChatMessage? _replyToMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize chat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeChat();
    });

    // Listen to scroll position
    _scrollController.addListener(_onScroll);

    // Listen to focus changes to handle keyboard
    _messageFocusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    _typingTimer?.cancel();

    // Schedule markChatAsClosed to run after dispose completes
    Future.microtask(() {
      _chatProvider?.markChatAsClosed();
    });

    super.dispose();
  }

  void _onFocusChange() {
    // System handles scrolling naturally when focus changes
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatProvider ??= Provider.of<ChatProvider>(context, listen: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('ChatView: App resumed, re-initializing chat...');
      _initializeChat();
    }
  }

  void _initializeChat() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final addressbookProvider = Provider.of<AddressbookProvider>(context, listen: false);

    if (walletProvider.address == null) {
      return;
    }

    final walletAddress = walletProvider.address!;

    // 1. Try to find nickname locally first
    String? nickname;
    try {
      final addressbookEntry = await addressbookProvider.searchByAddress(walletAddress);
      if (addressbookEntry != null && addressbookEntry.username.isNotEmpty) {
        nickname = addressbookEntry.username;
        debugPrint('✅ Found nickname locally: $nickname');
      }
    } catch (e) {
      debugPrint('⚠️ Error checking local addressbook: $e');
    }

    // 2. Connect (this will try to fetch nickname from server if nickname is null)
    if (!chatProvider.isConnected) {
      await chatProvider.connect(walletAddress, nickname: nickname);
    }

    // 3. Check if we finally have a nickname
    if (chatProvider.currentNickname == null || chatProvider.currentNickname!.isEmpty) {
      // Still no nickname, maybe it's in the addressbook backend but not local?
      // (This is redundant if searchByAddress already checked backend, but let's be sure)
      if (mounted) {
        // Delay slightly to ensure transition is complete and view is focused
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _showUsernamePrompt();
        });
        return;
      }
    }

    // Reload chat history
    await chatProvider.loadHistory(forceRefresh: true);

    if (mounted) {
      chatProvider.markChatAsOpened();
    }
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
              
              if (widget.showBackButton && Navigator.of(context).canPop()) {
                // If we were pushed (standalone), replace with address book
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddressbookView(),
                  ),
                );
              } else {
                // If we are in tab mode, just push address book on top
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddressbookView(),
                  ),
                );
              }
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
    // With reverse: true, position.pixels is distance from bottom
    final isAtBottom = _scrollController.position.pixels <= 100;

    if (_showScrollButton != !isAtBottom) {
      setState(() {
        _showScrollButton = !isAtBottom;
      });
    }

    // Load more messages when scrolling to top (maxScrollExtent with reverse: true)
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 100) {
      _loadMoreMessages();
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;

    _scrollController.animateTo(
      0,
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
    chatProvider.sendMessage(text, replyTo: _replyToMessage);

    _messageController.clear();
    setState(() {
      _replyToMessage = null;
    });
    _stopTyping();

    // Scroll to bottom (0) after sending message
    Future.delayed(Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
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
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true, // System handles push-up naturally
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _buildMessagesList(),
              ),
              _buildMessageInput(),
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
              // Back button (only shown if requested and can pop)
              if (widget.showBackButton && Navigator.of(context).canPop())
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              if (widget.showBackButton && Navigator.of(context).canPop())
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
                        '💬 BTCS Messenger',
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
                        if (chatProvider.isConnected) ...[
                          const SizedBox(width: 12),
                          Container(
                            width: 1,
                            height: 12,
                            color: Colors.white24,
                          ),
                          const SizedBox(width: 12),
                          const Icon(
                            Icons.people_outline,
                            size: 14,
                            color: Colors.cyanAccent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${chatProvider.userCount} Online',
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (chatProvider.latestSystemMessage != null) ...[
                            const SizedBox(width: 12),
                            Container(
                              width: 1,
                              height: 12,
                              color: Colors.white24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                chatProvider.latestSystemMessage!,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                    if (chatProvider.serverSystemMessage != null)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.cyanAccent.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.campaign,
                              size: 16,
                              color: Colors.cyanAccent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: MarqueeText(
                                text: chatProvider.serverSystemMessage!,
                                style: const TextStyle(
                                  color: Colors.cyanAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
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

        // Initial scroll is handled automatically by reverse: true in ListView.
        // The newest message (index 0) is at the bottom.

        return Stack(
          children: [
            ListView.builder(
              controller: _scrollController,
              reverse: true,
              padding: const EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16,
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
                        '👤$displayName',
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
                // Reply preview if applicable
                if (message.replyToText != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border(
                        left: BorderSide(
                          color: Colors.cyanAccent.withValues(alpha: 0.5),
                          width: 3,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.replyToUser ?? 'User',
                          style: TextStyle(
                            color: Colors.cyanAccent.withValues(alpha: 0.7),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          message.replyToText!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                // Message bubble with options (copy/save)
                GestureDetector(
                  onHorizontalDragEnd: (details) {
                    // Swipe right to reply (positive velocity)
                    if (details.primaryVelocity != null && details.primaryVelocity! > 500) {
                      if (!message.isSystem) {
                        setState(() {
                          _replyToMessage = message;
                        });
                        _messageFocusNode.requestFocus();
                      }
                    }
                  },
                  onLongPress: () => _showMessageOptions(message, displayName, isMyMessage),
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
      child: GestureDetector(
        onLongPress: () => _showMessageOptions(message, 'System', false),
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

  Widget _buildMessageInput() {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, child) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Typing indicator
            if (chatProvider.typingUsers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.cyanAccent.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${chatProvider.typingUsers.values.join(", ")} ${chatProvider.typingUsers.length == 1 ? "is" : "are"} typing...',
                        style: TextStyle(
                          color: Colors.cyanAccent.withValues(alpha: 0.6),
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Reply Preview Bar
            if (_replyToMessage != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withValues(alpha: 0.1),
                  border: Border(
                    top: BorderSide(
                      color: Colors.cyanAccent.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.reply, color: Colors.cyanAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Replying to ${_replyToMessage!.nickname ?? _replyToMessage!.walletAddress.substring(0, 8)}',
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _replyToMessage!.message,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20, color: Colors.white54),
                      onPressed: () => setState(() => _replyToMessage = null),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
            ),
          ],
        );
      },
    );
  }

  void _showMessageOptions(ChatMessage message, String displayName, bool isMyMessage) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(
            color: Colors.cyanAccent.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.cyanAccent),
              title: const Text('Copy Message', style: TextStyle(color: Colors.white)),
              onTap: () {
                Clipboard.setData(ClipboardData(text: message.message));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Message copied to clipboard'),
                    backgroundColor: Colors.cyanAccent.withValues(alpha: 0.8),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            if (!message.isSystem)
              ListTile(
                leading: const Icon(Icons.reply, color: Colors.cyanAccent),
                title: const Text('Reply', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _replyToMessage = message;
                  });
                  _messageFocusNode.requestFocus();
                },
              ),
            if (!isMyMessage && !message.isSystem)
              ListTile(
                leading: const Icon(Icons.person_add, color: Colors.cyanAccent),
                title: const Text('Add to Address Book', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showAddToAddressBookDialog(message, displayName);
                },
              ),
            const SizedBox(height: 20),
          ],
        ),
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

              // Strip @ symbol if present
              final cleanUsername = displayName.startsWith('@') 
                  ? displayName.substring(1) 
                  : displayName;

              // Create address book entry
              final entry = AddressbookEntry(
                username: cleanUsername,
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
    // Convert UTC timestamp from server to local time for correct "X mins ago" calculation
    final localTimestamp = timestamp.toLocal();
    final now = DateTime.now();
    final difference = now.difference(localTimestamp);

    if (difference.inDays > 0) {
      return DateFormat('MMM d, HH:mm').format(localTimestamp);
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
