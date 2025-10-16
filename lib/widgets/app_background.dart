import 'package:flutter/material.dart';

class AppBackground extends StatelessWidget {
  final Widget child;
  final bool showGradient;

  const AppBackground({
    super.key,
    required this.child,
    this.showGradient = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // Fallback color in case the image asset fails to load
        color: const Color(0xFF0A0A0A),
        // Use the gradient ONLY if showGradient is explicitly true
        gradient: showGradient
            ? LinearGradient(
          colors: [
            const Color(0xFF0A0A0A), // Deep black
            const Color(0xFF1A1A1A), // Dark gray
            const Color(0xFF2A2A2A), // Medium dark gray
            const Color(0xFF3A3A3A), // Light gray
            const Color(0xFF4A4A4A), // Very light gray
          ],
          stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        )
            : null,
        // Show the image by default (when showGradient is false)
        image: !showGradient
            ? DecorationImage(
          // IMPORTANT: Make sure this path is correct!
          image: const AssetImage("assets/background.jpg"),
          // This ensures the image covers the entire screen
          fit: BoxFit.cover,
        )
            : null,
      ),
      child: child,
    );
  }
}

class SilverAccentGradient extends StatelessWidget {
  final Widget child;

  const SilverAccentGradient({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFC0C0C0).withOpacity(0.1), // Silver
            Colors.transparent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: child,
    );
  }
}
