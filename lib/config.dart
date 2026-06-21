class Config {
  static const String addressPrefix = 'bs';
  static const int networkPrefix = 0x80;

  // RPC credentials are managed through RpcConfigService and secure storage
  static const String rpcUrl = String.fromEnvironment('RPC_URL', defaultValue: '');
  static const String rpcUser = String.fromEnvironment('RPC_USER', defaultValue: '');
  static const String rpcPassword = String.fromEnvironment('RPC_PASSWORD', defaultValue: '');

  static const String secondaryRpcUrl = String.fromEnvironment('SECONDARY_RPC_URL', defaultValue: '');
  static const String secondaryRpcUser = String.fromEnvironment('SECONDARY_RPC_USER', defaultValue: '');
  static const String secondaryRpcPassword = String.fromEnvironment('SECONDARY_RPC_PASSWORD', defaultValue: '');

  static const String explorerUrl = 'https://explorer.bitcoinsilver.top';
  static const String getAddressTxsEndpoint = '/ext/getaddress';
  static const String getTxEndpoint = '/ext/gettx';

  // LiveCoinWatch API Configuration (Price Data Source)
  static const String liveCoinWatchUrl = 'https://api.livecoinwatch.com/coins/single';
  static const String liveCoinWatchApiKey = String.fromEnvironment('LIVECOINWATCH_API_KEY', defaultValue: '');
  static const String btcsCode = '____BTCS';

  // Backend API Configuration (for chat and other features)
  static const String apiBaseUrl = 'https://bitcoinsilver.eu';
  static const String apiKey = String.fromEnvironment('NOTIFICATION_API_KEY', defaultValue: '');
  static const String chatSecret = String.fromEnvironment('CHAT_SECRET', defaultValue: '');
}
