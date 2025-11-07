import 'package:flutter/material.dart';

class AppBackground extends StatelessWidget {
  final Widget child;
  final bool showGradient;
  final bool enableSilverAccent;

  const AppBackground({
    super.key,
    required this.child,
    this.showGradient = true,
    this.enableSilverAccent = true,
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
            const Color(0xFF4A4A4A), // Light gray at top
            const Color(0xFF3A3A3A), // Medium gray
            const Color(0xFF2A2A2A), // Dark gray
            const Color(0xFF1A1A1A), // Darker
            const Color(0xFF0A0A0A), // Deep black at bottom
          ],
          stops: const [0.0, 0.2, 0.4, 0.7, 1.0],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        )
            : null,
        // Show the image by default (when showGradient is false)
        image: !showGradient
            ? DecorationImage(
          image: const AssetImage("assets/background.jpg"),
          fit: BoxFit.cover,
          colorFilter: enableSilverAccent
              ? ColorFilter.mode(
            const Color(0xFFC0C0C0).withOpacity(0.05),
            BlendMode.lighten,
          )
              : null,
        )
            : null,
      ),
      child: enableSilverAccent
          ? Stack(
        children: [
          // Animated silver shimmer effect in the background
          Positioned.fill(
            child: CustomPaint(
              painter: SilverShimmerPainter(),
            ),
          ),
          // Main content
          child,
        ],
      )
          : child,
    );
  }
}

// Custom painter for silver shimmer effect
class SilverShimmerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Top center silver glow - more prominent
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFFFFF).withOpacity(0.12), // Bright white
          const Color(0xFFC0C0C0).withOpacity(0.08), // Silver
          const Color(0xFFC0C0C0).withOpacity(0.04),
          Colors.transparent,
        ],
        stops: const [0.0, 0.3, 0.6, 1.0],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.5, 0),
        radius: size.width * 0.7,
      ));

    canvas.drawCircle(
      Offset(size.width * 0.5, 0),
      size.width * 0.7,
      paint,
    );

    // Top left accent
    final paint2 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFC0C0C0).withOpacity(0.1),
          const Color(0xFFC0C0C0).withOpacity(0.05),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(
        center: Offset(0, size.height * 0.2),
        radius: size.width * 0.4,
      ));

    canvas.drawCircle(
      Offset(0, size.height * 0.2),
      size.width * 0.4,
      paint2,
    );

    // Top right accent
    final paint3 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF00E5FF).withOpacity(0.08), // Cyan accent
          const Color(0xFFC0C0C0).withOpacity(0.04),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width, size.height * 0.15),
        radius: size.width * 0.5,
      ));

    canvas.drawCircle(
      Offset(size.width, size.height * 0.15),
      size.width * 0.5,
      paint3,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SilverAccentGradient extends StatelessWidget {
  final Widget child;
  final double intensity;

  const SilverAccentGradient({
    super.key,
    required this.child,
    this.intensity = 0.1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFC0C0C0).withOpacity(intensity), // Silver
            const Color(0xFF00E5FF).withOpacity(intensity * 0.3), // Cyan hint
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

// Silver-themed card decoration
class SilverCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final bool enableShimmer;

  const SilverCard({
    super.key,
    required this.child,
    this.padding,
    this.enableShimmer = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1A1A),
            const Color(0xFF1A1A1A).withBlue(15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFC0C0C0).withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFC0C0C0).withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: enableShimmer
          ? ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          colors: [
            Colors.white.withOpacity(0.8),
            const Color(0xFFC0C0C0),
            Colors.white.withOpacity(0.8),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(bounds),
        child: child,
      )
          : child,
    );
  }
}

// Silver-themed animated border
class SilverBorder extends StatefulWidget {
  final Widget child;
  final double borderWidth;
  final BorderRadius? borderRadius;

  const SilverBorder({
    super.key,
    required this.child,
    this.borderWidth = 2,
    this.borderRadius,
  });

  @override
  State<SilverBorder> createState() => _SilverBorderState();
}

class _SilverBorderState extends State<SilverBorder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
            gradient: SweepGradient(
              colors: [
                const Color(0xFFC0C0C0).withOpacity(0.8),
                const Color(0xFF00E5FF).withOpacity(0.6),
                const Color(0xFFC0C0C0).withOpacity(0.8),
                const Color(0xFF00E5FF).withOpacity(0.6),
                const Color(0xFFC0C0C0).withOpacity(0.8),
              ],
              stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
              transform: GradientRotation(_controller.value * 2 * 3.14159),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(widget.borderWidth),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0A),
                borderRadius: widget.borderRadius ?? BorderRadius.circular(10),
              ),
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}
