import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BiometricService {
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _biometricEnabledKey = 'biometric_enabled';

  // Check if device supports biometrics
  Future<bool> isDeviceSupported() async {
    try {
      return await _localAuth.isDeviceSupported();
    } catch (e) {
      return false;
    }
  }

  // Check if biometrics are available (device supports AND user has enrolled)
  Future<bool> isBiometricAvailable() async {
    try {
      final isSupported = await _localAuth.isDeviceSupported();
      if (!isSupported) return false;

      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      return canCheckBiometrics;
    } catch (e) {
      return false;
    }
  }

  // Get available biometric types
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  // Check if biometric authentication is enabled by user
  Future<bool> isBiometricEnabled() async {
    final enabled = await _storage.read(key: _biometricEnabledKey);
    return enabled == 'true';
  }

  // Enable biometric authentication
  Future<void> enableBiometric() async {
    await _storage.write(key: _biometricEnabledKey, value: 'true');
  }

  // Disable biometric authentication
  Future<void> disableBiometric() async {
    await _storage.write(key: _biometricEnabledKey, value: 'false');
  }

  // Authenticate with biometrics
  Future<bool> authenticate({
    String localizedReason = 'Please authenticate to continue',
    bool useErrorDialogs = true,
    bool stickyAuth = true,
  }) async {
    try {
      final isEnabled = await isBiometricEnabled();
      if (!isEnabled) {
        // Biometric not enabled, allow access
        return true;
      }

      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        // Biometric not available, allow access
        return true;
      }

      final result = await _localAuth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,  // Allow PIN/password/pattern fallback
          sensitiveTransaction: true,
        ),
      );
      return result;
    } on PlatformException catch (e) {
      // Handle specific errors
      if (e.code == 'NotAvailable' || e.code == 'NotEnrolled') {
        // Biometric not available, allow access
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Stop authentication
  Future<void> stopAuthentication() async {
    try {
      await _localAuth.stopAuthentication();
    } catch (e) {
      // Ignore errors
    }
  }

  // Get biometric type name for display
  String getBiometricTypeName(List<BiometricType> types) {
    if (types.isEmpty) return 'Biometric';

    if (types.contains(BiometricType.face)) {
      return 'Face ID';
    } else if (types.contains(BiometricType.fingerprint)) {
      return 'Fingerprint';
    } else if (types.contains(BiometricType.iris)) {
      return 'Iris';
    } else if (types.contains(BiometricType.strong)) {
      return 'Biometric';
    }

    return 'Biometric';
  }
}
