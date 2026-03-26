import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bitcoinsilver_wallet/config.dart';

class RpcConfigService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _rpcUrlKey = 'rpc_url';
  static const String _rpcUserKey = 'rpc_user';
  static const String _rpcPasswordKey = 'rpc_password';
  static const String _secondaryRpcUrlKey = 'secondary_rpc_url';

  String? _activeRpcUrl;
  String? _activeRpcUser;
  String? _activeRpcPassword;

  // Initialize RPC credentials - should be called once on first app launch
  Future<void> initializeRpcCredentials() async {
    // Check if credentials are already stored
    final existingUrl = await _storage.read(key: _rpcUrlKey);

    if (existingUrl == null) {
      // First time - check if environment variables were provided for primary RPC
      if (Config.rpcUrl.isNotEmpty &&
          Config.rpcUser.isNotEmpty &&
          Config.rpcPassword.isNotEmpty) {
        // Store primary credentials from environment variables
        await _storage.write(key: _rpcUrlKey, value: Config.rpcUrl);
        await _storage.write(key: _rpcUserKey, value: Config.rpcUser);
        await _storage.write(key: _rpcPasswordKey, value: Config.rpcPassword);
      }
    }

    // Check and store secondary RPC URL if provided via environment and not already stored
    final existingSecondaryUrl = await _storage.read(key: _secondaryRpcUrlKey);
    if (existingSecondaryUrl == null && Config.secondaryRpcUrl.isNotEmpty) {
      await _storage.write(key: _secondaryRpcUrlKey, value: Config.secondaryRpcUrl);
    }
  }

  // Check if primary RPC credentials are configured
  Future<bool> primaryRpcCredentialsConfigured() async {
    final url = await _storage.read(key: _rpcUrlKey);
    final user = await _storage.read(key: _rpcUserKey);
    final password = await _storage.read(key: _rpcPasswordKey);

    return url != null &&
           url.isNotEmpty &&
           user != null &&
           user.isNotEmpty &&
           password != null &&
           password.isNotEmpty;
  }

  // Get RPC URL
  Future<String?> getRpcUrl() async {
    final url = await _storage.read(key: _rpcUrlKey);
    if (url != null && url.isNotEmpty) return url;
    if (Config.rpcUrl.isNotEmpty) return Config.rpcUrl;
    return null; // Return null if RPC URL not configured or not available
  }

  // Get RPC User
  Future<String?> getRpcUser() async {
    final user = await _storage.read(key: _rpcUserKey);
    if (user != null && user.isNotEmpty) return user;
    if (Config.rpcUser.isNotEmpty) return Config.rpcUser;
    return null; // Return null if RPC User not configured or not available
  }

  // Get RPC Password
  Future<String?> getRpcPassword() async {
    final password = await _storage.read(key: _rpcPasswordKey);
    if (password != null && password.isNotEmpty) return password;
    if (Config.rpcPassword.isNotEmpty) return Config.rpcPassword;
    return null; // Return null if RPC Password not configured or not available
  }

  // Get Secondary RPC URL
  Future<String?> getSecondaryRpcUrl() async {
    final url = await _storage.read(key: _secondaryRpcUrlKey);
    if (url != null && url.isNotEmpty) return url;
    if (Config.secondaryRpcUrl.isNotEmpty) return Config.secondaryRpcUrl;
    return null; // Return null if neither is configured
  }

  // Update RPC credentials (for advanced users who want to use their own node)
  Future<void> updateRpcCredentials({
    String? url,
    String? user,
    String? password,
  }) async {
    if (url != null) await _storage.write(key: _rpcUrlKey, value: url);
    if (user != null) await _storage.write(key: _rpcUserKey, value: user);
    if (password != null) await _storage.write(key: _rpcPasswordKey, value: password);
  }

  // Clear RPC credentials (reset to defaults)
  Future<void> clearRpcCredentials() async {
    await _storage.delete(key: _rpcUrlKey);
    await _storage.delete(key: _rpcUserKey);
    await _storage.delete(key: _rpcPasswordKey);
    await _storage.delete(key: _secondaryRpcUrlKey);
  }

  // Check if custom RPC credentials are set
  Future<bool> hasCustomCredentials() async {
    final url = await _storage.read(key: _rpcUrlKey);
    return url != null;
  }

  // Set the active RPC to the primary configuration
  Future<void> setActiveRpcPrimary() async {
    _activeRpcUrl = await getRpcUrl();
    _activeRpcUser = await getRpcUser();
    _activeRpcPassword = await getRpcPassword();
  }

  // Set the active RPC to the secondary configuration (unauthenticated)
  Future<void> setActiveRpcSecondary() async {
    _activeRpcUrl = await getSecondaryRpcUrl();
    _activeRpcUser = ''; // Secondary is unauthenticated
    _activeRpcPassword = ''; // Secondary is unauthenticated
  }

  // Get the currently active RPC URL
  String? getActiveRpcUrl() => _activeRpcUrl;

  // Get the currently active RPC User
  String? getActiveRpcUser() => _activeRpcUser;

  // Get the currently active RPC Password
  String? getActiveRpcPassword() => _activeRpcPassword;
}
