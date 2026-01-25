import 'package:shared_preferences/shared_preferences.dart';
// import 'package:flutter_secure_storage/flutter_secure_storage.dart';  // Uncomment if you need secure storage migrations
import 'package:package_info_plus/package_info_plus.dart';

class MigrationService {
  static const String _versionKey = 'app_version';
  // static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  /// Check and run migrations if app version has changed
  static Future<void> checkAndMigrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final packageInfo = await PackageInfo.fromPlatform();

      final currentVersion = packageInfo.version;
      final storedVersion = prefs.getString(_versionKey);

      // First install or version changed
      if (storedVersion == null || storedVersion != currentVersion) {
        await _runMigrations(storedVersion, currentVersion);
        await prefs.setString(_versionKey, currentVersion);
      }
    } catch (e) {
      // Don't crash the app if migration fails - just continue
      // User may need to clear data manually in worst case
    }
  }

  static Future<void> _runMigrations(String? oldVersion, String newVersion) async {
    // final prefs = await SharedPreferences.getInstance();

    // First install - no migration needed
    if (oldVersion == null) {
      return;
    }

    // Migration logic based on version changes
    // Clear cached data for users upgrading from versions before 3.8.0 (RPC server changed)
    if (_isVersionLessThan(oldVersion, '3.8.0')) {
      await _migrateTo380();
    }
  }

  /// Migration to version 3.8.0 - RPC server changed
  static Future<void> _migrateTo380() async {
    final prefs = await SharedPreferences.getInstance();

    // Get all keys to clear blockchain/API related cache
    final keys = prefs.getKeys();

    // List of keys to preserve (DO NOT DELETE)
    final keysToPreserve = {
      _versionKey,                      // app_version
      'notifications_enabled',          // user settings
      'favorites',                      // address book favorites
      'recent_searches',                // address book searches
    };

    // Remove all other cached data (blockchain, transactions, balances, etc.)
    for (final key in keys) {
      if (!keysToPreserve.contains(key)) {
        await prefs.remove(key);
      }
    }

    // Note: Secure storage (wallet keys) is NOT affected - those are preserved
  }

  /// Compare version strings (simple comparison)
  static bool _isVersionLessThan(String version1, String version2) {
    try {
      // Strip build number (e.g., "3.8.0+1" -> "3.8.0")
      final v1Clean = version1.split('+').first.split('-').first;
      final v2Clean = version2.split('+').first.split('-').first;

      final v1Parts = v1Clean.split('.').map((s) => int.tryParse(s) ?? 0).toList();
      final v2Parts = v2Clean.split('.').map((s) => int.tryParse(s) ?? 0).toList();

      for (int i = 0; i < 3; i++) {
        final v1 = i < v1Parts.length ? v1Parts[i] : 0;
        final v2 = i < v2Parts.length ? v2Parts[i] : 0;

        if (v1 < v2) return true;
        if (v1 > v2) return false;
      }

      return false; // versions are equal
    } catch (e) {
      return false; // If parsing fails, assume no migration needed
    }
  }

  /// Force clear all app data (use with caution!)
  /// Only call this for major breaking changes
  static Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    // Note: Secure storage (wallet keys) is preserved
  }
}
