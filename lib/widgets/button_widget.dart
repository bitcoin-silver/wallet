import 'package:flutter/material.dart';

class ButtonWidget extends StatefulWidget {
  final String? text;
  final IconData? icon;
  final bool isCompact;
  final bool isPrimary;
  final VoidCallback? onPressed;

  const ButtonWidget({
    super.key,
    this.text,
    this.icon,
    this.isCompact = false,
    this.isPrimary = true,
    required this.onPressed,
  });

  @override
  State<ButtonWidget> createState() => _ButtonWidgetState();
}

class _ButtonWidgetState extends State<ButtonWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onPressed != null) {
      setState(() => _isPressed = true);
      _controller.forward();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDisabled = widget.onPressed == null;

    if (widget.isCompact && widget.icon != null) {
      return ScaleTransition(
        scale: _scaleAnimation,
        child: GestureDetector(
          onTapDown: _handleTapDown,
          onTapUp: _handleTapUp,
          onTapCancel: _handleTapCancel,
          onTap: widget.onPressed,
          child: Container(
            decoration: BoxDecoration(
              gradient: isDisabled
                  ? null
                  : (widget.isPrimary
                      ? LinearGradient(
                          colors: [
                            const Color(0xFF2A2A2A),
                            const Color(0xFF1A1A1A),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : LinearGradient(
                          colors: [
                            Colors.white,
                            const Color(0xFFC0C0C0),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )),
              color: isDisabled
                  ? (widget.isPrimary
                          ? const Color.fromARGB(255, 25, 25, 25)
                          : Colors.white)
                      .withValues(alpha: 0.5)
                  : null,
              borderRadius: BorderRadius.circular(12),
              boxShadow: isDisabled || _isPressed
                  ? null
                  : [
                      BoxShadow(
                        color: (widget.isPrimary
                                ? const Color(0xFF00E5FF)
                                : const Color(0xFFC0C0C0))
                            .withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 0,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: IconButton(
              icon: Icon(
                widget.icon,
                color: isDisabled
                    ? (widget.isPrimary ? Colors.white : Colors.black)
                        .withValues(alpha: 0.5)
                    : (widget.isPrimary ? Colors.cyanAccent : Colors.black),
              ),
              onPressed: widget.onPressed,
            ),
          ),
        ),
      );
    }

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        child: Container(
          decoration: BoxDecoration(
            gradient: isDisabled
                ? null
                : (widget.isPrimary
                    ? LinearGradient(
                        colors: [
                          const Color(0xFF2A2A2A),
                          const Color(0xFF1A1A1A),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : LinearGradient(
                        colors: [
                          Colors.white,
                          const Color(0xFFC0C0C0),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )),
            color: isDisabled
                ? (widget.isPrimary
                        ? const Color.fromARGB(255, 25, 25, 25)
                        : Colors.white)
                    .withValues(alpha: 0.5)
                : null,
            borderRadius: BorderRadius.circular(12),
            border: !isDisabled && !widget.isPrimary
                ? Border.all(
                    color: const Color(0xFFC0C0C0).withValues(alpha: 0.3),
                    width: 1,
                  )
                : null,
            boxShadow: isDisabled || _isPressed
                ? null
                : [
                    BoxShadow(
                      color: (widget.isPrimary
                              ? const Color(0xFF00E5FF)
                              : const Color(0xFFC0C0C0))
                          .withValues(alpha: 0.3),
                      blurRadius: 16,
                      spreadRadius: 0,
                      offset: const Offset(0, 4),
                    ),
                    if (_isPressed)
                      BoxShadow(
                        color: (widget.isPrimary
                                ? const Color(0xFF00E5FF)
                                : const Color(0xFFC0C0C0))
                            .withValues(alpha: 0.5),
                        blurRadius: 24,
                        spreadRadius: -2,
                      ),
                  ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              splashColor: (widget.isPrimary
                      ? Colors.cyanAccent
                      : const Color(0xFFC0C0C0))
                  .withValues(alpha: 0.2),
              highlightColor: (widget.isPrimary
                      ? Colors.cyanAccent
                      : const Color(0xFFC0C0C0))
                  .withValues(alpha: 0.1),
              onTap: widget.onPressed,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Icon(
                          widget.icon,
                          size: 20,
                          color: isDisabled
                              ? (widget.isPrimary ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.5)
                              : (widget.isPrimary
                                  ? Colors.cyanAccent
                                  : Colors.black),
                        ),
                      ),
                    Text(
                      (widget.text ?? 'Button').toUpperCase(),
                      style: TextStyle(
                        color: isDisabled
                            ? (widget.isPrimary ? Colors.white : Colors.black)
                                .withValues(alpha: 0.5)
                            : (widget.isPrimary ? Colors.white : Colors.black),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}