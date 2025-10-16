import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bitcoinsilver_wallet/config.dart';

class RpcConfigService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _rpcUrlKey = 'rpc_url';
  static const String _rpcUserKey = 'rpc_user';
  static const String _rpcPasswordKey = 'rpc_password';

  // Initialize RPC credentials - should be called once on first app launch
  Future<void> initializeRpcCredentials() async {
    // Check if credentials are already stored
    final existingUrl = await _storage.read(key: _rpcUrlKey);

    if (existingUrl == null) {
      // First time - check if environment variables were provided
      if (Config.rpcUrl.isNotEmpty &&
          Config.rpcUser.isNotEmpty &&
          Config.rpcPassword.isNotEmpty) {
        // Store credentials from environment variables
        await _storage.write(key: _rpcUrlKey, value: Config.rpcUrl);
        await _storage.write(key: _rpcUserKey, value: Config.rpcUser);
        await _storage.write(key: _rpcPasswordKey, value: Config.rpcPassword);
      }
      // If environment variables not set, credentials must be configured manually
      // via updateRpcCredentials() or through a setup UI
    }
  }

  // Check if RPC credentials are configured
  Future<bool> areCredentialsConfigured() async {
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
  Future<String> getRpcUrl() async {
    final url = await _storage.read(key: _rpcUrlKey);
    if (url != null && url.isNotEmpty) return url;
    if (Config.rpcUrl.isNotEmpty) return Config.rpcUrl;
    throw Exception('RPC URL not configured');
  }

  // Get RPC User
  Future<String> getRpcUser() async {
    final user = await _storage.read(key: _rpcUserKey);
    if (user != null && user.isNotEmpty) return user;
    if (Config.rpcUser.isNotEmpty) return Config.rpcUser;
    throw Exception('RPC User not configured');
  }

  // Get RPC Password
  Future<String> getRpcPassword() async {
    final password = await _storage.read(key: _rpcPasswordKey);
    if (password != null && password.isNotEmpty) return password;
    if (Config.rpcPassword.isNotEmpty) return Config.rpcPassword;
    throw Exception('RPC Password not configured');
  }

  // Update RPC credentials (for advanced users who want to use their own node)
  Future<void> updateRpcCredentials({
    required String url,
    required String user,
    required String password,
  }) async {
    await _storage.write(key: _rpcUrlKey, value: url);
    await _storage.write(key: _rpcUserKey, value: user);
    await _storage.write(key: _rpcPasswordKey, value: password);
  }

  // Clear RPC credentials (reset to defaults)
  Future<void> clearRpcCredentials() async {
    await _storage.delete(key: _rpcUrlKey);
    await _storage.delete(key: _rpcUserKey);
    await _storage.delete(key: _rpcPasswordKey);
  }

  // Check if custom RPC credentials are set
  Future<bool> hasCustomCredentials() async {
    final url = await _storage.read(key: _rpcUrlKey);
    return url != null;
  }
}
