import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bitcoinsilver_wallet/services/biometric_service.dart';
import 'package:bitcoinsilver_wallet/views/home_view.dart';
import 'package:bitcoinsilver_wallet/widgets/app_background.dart';

class BiometricGate extends StatefulWidget {
  const BiometricGate({super.key});

  @override
  State<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends State<BiometricGate> with WidgetsBindingObserver {
  final BiometricService _biometricService = BiometricService();
  bool _isAuthenticated = false;
  bool _isAuthenticating = true;
  bool _isInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authenticate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Track when app goes to background (only paused, not inactive)
    if (state == AppLifecycleState.paused) {
      _isInBackground = true;
    }

    // Re-authenticate only when app resumes from actual background
    // Skip if we're still authenticating or not yet authenticated
    if (state == AppLifecycleState.resumed &&
        _isInBackground &&
        _isAuthenticated &&
        !_isAuthenticating) {
      _isInBackground = false;
      setState(() {
        _isAuthenticated = false;
        _isAuthenticating = true;
      });
      _authenticate();
    } else if (state == AppLifecycleState.resumed && !_isAuthenticated) {
      // Reset background flag if resuming before authentication complete
      _isInBackground = false;
    }
  }

  Future<void> _authenticate() async {
    try {
      // First check if biometric is enabled
      final isEnabled = await _biometricService.isBiometricEnabled();

      if (!isEnabled) {
        // Not enabled, allow access
        if (mounted) {
          setState(() {
            _isAuthenticated = true;
            _isAuthenticating = false;
          });
        }
        return;
      }

      // Check if biometric is actually available on device
      final isAvailable = await _biometricService.isBiometricAvailable();

      if (!isAvailable) {
        // Biometric enabled but not available right now (timing issue or device change)
        // Allow access without changing stored preference - user can disable in Settings
        if (mounted) {
          setState(() {
            _isAuthenticated = true;
            _isAuthenticating = false;
          });
          // Show message after frame is built
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Biometric authentication unavailable - you can disable it in Settings'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 4),
                ),
              );
            }
          });
        }
        return;
      }

      // Now try to authenticate
      final authenticated = await _biometricService.authenticate(
        localizedReason: 'Authenticate to access your wallet',
      );

      if (mounted) {
        setState(() {
          _isAuthenticated = authenticated;
          _isAuthenticating = false;
        });
      }
    } catch (e) {
      // If there's an error, show failed state
      if (mounted) {
        setState(() {
          _isAuthenticated = false;
          _isAuthenticating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isAuthenticating) {
      return Scaffold(
        body: AppBackground(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.fingerprint,
                  size: 80,
                  color: const Color(0xFFC0C0C0).withValues(alpha: 0.5),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Authenticating...',
                  style: TextStyle(color: Colors.white54, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isAuthenticated) {
      return Scaffold(
        body: AppBackground(
          child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 80,
                color: Colors.red,
              ),
              const SizedBox(height: 24),
              const Text(
                'Authentication Failed',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 12),
              const Text(
                'Unable to authenticate',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _isAuthenticating = true;
                  });
                  _authenticate();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => SystemNavigator.pop(),
                child: const Text(
                  'Exit App',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
        ),
      );
    }

    return const HomeView();
  }
}
