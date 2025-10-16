import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerView extends StatefulWidget {
  const ScannerView({super.key});

  @override
  State<ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<ScannerView> with WidgetsBindingObserver {
  late final MobileScannerController controller;
  bool hasScanned = false;

  @override
  void initState() {
    super.initState();
    // Initialize controller with better configuration
    controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
      formats: [BarcodeFormat.qrCode], // Only scan QR codes for better performance
      returnImage: false, // Set to true if you need the scanned image
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle to properly manage camera
    // Check if controller is running before managing lifecycle
    if (!controller.value.isInitialized) return;

    switch (state) {
      case AppLifecycleState.paused:
        controller.stop();
        break;
      case AppLifecycleState.resumed:
        controller.start();
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  void _handleDetection(BarcodeCapture capture) {
    // Prevent multiple scans
    if (hasScanned) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      setState(() {
        hasScanned = true;
      });

      // Haptic feedback for better UX
      HapticFeedback.mediumImpact();

      // Return the scanned value
      Navigator.pop(context, barcodes.first.rawValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanArea = MediaQuery.of(context).size.width * 0.8;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera View
          MobileScanner(
            controller: controller,
            onDetect: _handleDetection,
            errorBuilder: (context, error) {
              return _buildErrorWidget(error);
            },
            overlayBuilder: (context, constraints) {
              return _buildOverlay(context, scanArea);
            },
          ),

          // Custom UI Elements
          SafeArea(
            child: Column(
              children: [
                // Header with close and torch buttons
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Close button
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 30,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),

                      // Torch toggle
                      ValueListenableBuilder(
                        valueListenable: controller,
                        builder: (context, state, child) {
                          final torchEnabled = state.torchState == TorchState.on;
                          return IconButton(
                            icon: Icon(
                              torchEnabled ? Icons.flash_on : Icons.flash_off,
                              color: Colors.white,
                              size: 28,
                            ),
                            onPressed: () => controller.toggleTorch(),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Instructions
                Padding(
                  padding: const EdgeInsets.only(bottom: 100.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Align QR code within the frame',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay(BuildContext context, double scanArea) {
    return Stack(
      children: [
        // Dark overlay with cutout
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withOpacity(0.5),
            BlendMode.srcOut,
          ),
          child: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.black,
                  backgroundBlendMode: BlendMode.dstOut,
                ),
              ),
              Center(
                child: Container(
                  width: scanArea,
                  height: scanArea,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Scanning frame with corners
        Center(
          child: SizedBox(
            width: scanArea,
            height: scanArea,
            child: CustomPaint(
              painter: ScannerOverlayPainter(
                borderColor: Colors.white,
                borderWidth: 3,
                cornerLength: 30,
                cornerRadius: 16,
                animationValue: hasScanned ? 1.0 : 0.0,
              ),
            ),
          ),
        ),

        // Scanning animation line
        if (!hasScanned)
          Center(
            child: SizedBox(
              width: scanArea,
              height: scanArea,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(seconds: 2),
                curve: Curves.easeInOutSine,
                onEnd: () {
                  // Restart animation
                  if (mounted && !hasScanned) {
                    setState(() {});
                  }
                },
                builder: (context, value, child) {
                  return Align(
                    alignment: Alignment(0, -1 + (value * 2)),
                    child: Container(
                      width: scanArea * 0.9,
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.white.withOpacity(0.8),
                            Colors.transparent,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.5),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildErrorWidget(MobileScannerException error) {
    String errorMessage;
    IconData errorIcon;

    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        errorMessage = 'Camera permission denied.\nPlease enable it in settings.';
        errorIcon = Icons.camera_alt_outlined;
        break;
      case MobileScannerErrorCode.unsupported:
        errorMessage = 'QR scanning not supported on this device.';
        errorIcon = Icons.error_outline;
        break;
      default:
        errorMessage = 'An error occurred while scanning.\nPlease try again.';
        errorIcon = Icons.warning_amber_rounded;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            errorIcon,
            size: 80,
            color: Colors.white54,
          ),
          const SizedBox(height: 24),
          Text(
            errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
                // Open app settings
                controller.start();
              } else {
                Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.settings),
            label: Text(
              error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? 'Open Settings'
                  : 'Go Back',
            ),
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.black,
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter for the scanner overlay corners
class ScannerOverlayPainter extends CustomPainter {
  final Color borderColor;
  final double borderWidth;
  final double cornerLength;
  final double cornerRadius;
  final double animationValue;

  ScannerOverlayPainter({
    required this.borderColor,
    required this.borderWidth,
    required this.cornerLength,
    required this.cornerRadius,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = animationValue > 0 ? Colors.green : borderColor
      ..strokeWidth = borderWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    // Top-left corner
    path.moveTo(0, cornerLength);
    path.lineTo(0, cornerRadius);
    path.quadraticBezierTo(0, 0, cornerRadius, 0);
    path.lineTo(cornerLength, 0);

    // Top-right corner
    path.moveTo(size.width - cornerLength, 0);
    path.lineTo(size.width - cornerRadius, 0);
    path.quadraticBezierTo(size.width, 0, size.width, cornerRadius);
    path.lineTo(size.width, cornerLength);

    // Bottom-right corner
    path.moveTo(size.width, size.height - cornerLength);
    path.lineTo(size.width, size.height - cornerRadius);
    path.quadraticBezierTo(
      size.width,
      size.height,
      size.width - cornerRadius,
      size.height,
    );
    path.lineTo(size.width - cornerLength, size.height);

    // Bottom-left corner
    path.moveTo(cornerLength, size.height);
    path.lineTo(cornerRadius, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - cornerRadius);
    path.lineTo(0, size.height - cornerLength);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}