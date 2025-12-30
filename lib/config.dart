class Config {
  static const String addressPrefix = 'bs';
  static const int networkPrefix = 0x80;

  // RPC credentials are managed through RpcConfigService and secure storage
  // Set via environment variables during build:
  // flutter build --dart-define-from-file=dart_defines.json
  // Or: flutter build --dart-define=RPC_URL=... --dart-define=RPC_USER=... --dart-define=RPC_PASSWORD=...
  static const String rpcUrl = String.fromEnvironment('RPC_URL', defaultValue: '');
  static const String rpcUser = String.fromEnvironment('RPC_USER', defaultValue: '');
  static const String rpcPassword = String.fromEnvironment('RPC_PASSWORD', defaultValue: '');

  static const String explorerUrl =
      'https://explorer.bitcoinsilver.top';
  static const String getAddressTxsEndpoint = '/ext/getaddress';
  static const String getTxEndpoint = '/ext/gettx';

  // LiveCoinWatch API Configuration (Price Data Source)
  static const String liveCoinWatchUrl = 'https://api.livecoinwatch.com/coins/single';
  static const String liveCoinWatchApiKey = '4ec13b1b-7248-4d53-94a2-940017952f82';
  static const String btcsCode = '____BTCS';

  // Backend API Configuration (for chat and other features)
  static const String apiBaseUrl = 'https://btcs-vps13.duckdns.org';
  static const String apiKey = String.fromEnvironment('NOTIFICATION_API_KEY', defaultValue: '');
}
