# Bitcoin Silver Android Wallet 

<p align="center">
  <img src="assets/logo.png" alt="S256 Wallet" width="430">
</p>

<p align="center">
  <strong>Mobile wallet for BitcoinSilver (BTCS)</strong><br>
  Built with Flutter for Android & iOS
</p>

<p align="center">
  <a href="https://bitcoinsilver.top/">Website</a> •
  <a href="https://explorer.bitcoinsilver.top/">Explorer</a>
</p>

## Features

- **BIP39 Seed Phrase Support**: Create or restore wallets using 12 or 24-word recovery phrases.
- **Cross-Platform Compatibility**: Uses standard derivation path `m/44'/0'/0'/0/0` (same as Web Wallet 2.2).
- **Advanced Recovery**: Support for raw private key (WIF) recovery and generation.
- **Send and Receive**: Seamless BTCS transfers.
- **QR Code Scanning**: Supports BIP21 URI format for easy payments.
- **Transaction Tracking**: Real-time history with smart confirmation tracking.
- **Biometric Security**: Protect your wallet and recovery phrase with fingerprint or face recognition.
- **Secure Storage**: Sensitive keys and mnemonics are stored in encrypted secure storage.

## Quick Start

```bash
# Install dependencies
flutter pub get

# Run in development (uses public RPC)
flutter run

# Build APK
flutter build apk

# Build with custom RPC
flutter build apk --release --obfuscate --split-debug-info=build/app/outputs/symbols --dart-define-from-file=dart_defines.json
```

## Configuration

The wallet connects to the public RPC proxy at `https://btcs-vps13.duckdns.org/btcs-rpc` by default (no authentication required).

For custom RPC node, create `dart_defines.json`:
```json
{
  "RPC_URL": "http://your-rpc:port",
  "RPC_USER": "your_user",
  "RPC_PASSWORD": "your_password"
}
```

## Build for Production

```bash
# Android APK
flutter build apk --release --dart-define-from-file=dart_defines.json

# Android App Bundle (Play Store)
flutter build appbundle --release --obfuscate \
  --split-debug-info=build/app/outputs/symbols \
  --dart-define-from-file=dart_defines.json

# iOS
flutter build ios --release --dart-define-from-file=dart_defines.json
```

Output locations:
- APK: `build/app/outputs/flutter-apk/app-release.apk`
- AAB: `build/app/outputs/bundle/release/app-release.aab`

## Security

- Private keys stored in encrypted secure storage (Keychain/KeyStore)
- Optional biometric authentication
- RPC credentials injected at build time, never hardcoded
- No personal data collected

**Never commit `dart_defines.json` or `.env` to version control.**

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -m 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

For bugs or feature requests, please open an issue.

```bash
- Current Google Play version 5.2
```
<a href="https://play.google.com/store/apps/details?id=top.bitcoinsilver.wallet2025&pli=1">
    <img src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" alt="Get it on Google Play" height="60">
</a>

## License

MIT
