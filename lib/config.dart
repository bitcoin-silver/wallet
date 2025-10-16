class Config {
  static const String addressPrefix = 'bs';
  static const int networkPrefix = 0x80;

  // RPC credentials are managed through RpcConfigService and secure storage
  // Set via environment variables during build:
  // flutter build --dart-define=RPC_URL=... --dart-define=RPC_USER=... --dart-define=RPC_PASSWORD=...
  static const String rpcUrl = String.fromEnvironment('RPC_URL', defaultValue: '');
  static const String rpcUser = String.fromEnvironment('RPC_USER', defaultValue: '');
  static const String rpcPassword = String.fromEnvironment('RPC_PASSWORD', defaultValue: '');

  static const String explorerUrl =
      'http://explorer.btcs.pools4mining.com:3001';
  static const String getAddressTxsEndpoint = '/ext/getaddresstxs';
  static const String getTxEndpoint = '/ext/gettx';

  static const String priceUrl = 'https://bitcoinsilver.top/api/';
}
