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
- **Local Transaction Signing (No Node Key Exposure)**: Transactions are built and signed in-app using local keys, then broadcast as raw hex.
- **Seed + WIF Wallet Modes**: Users can create/use both mnemonic-based and WIF-based wallets.
- **Advanced Send / Coin Control**: Select specific confirmed UTXOs, paginate inputs, estimate fees, and preview net send amount.
- **Send and Receive**: Seamless BTCS transfers for both legacy and SegWit destination types.
- **BTCS Address Compatibility**: Supports BTCS Bech32 (`bs1...`) and legacy Base58 address handling in signer and send flow.
- **Address Validation Improvements**: Debounced validation, scanner/address-book parity, and resilient fallback validation for BTCS RPC edge cases.
- **QR Code Scanning**: Supports BIP21 URI format for easy transfers.
- **Transaction Tracking**: Real-time history with smart confirmation tracking and pending-state management.
- **Smart Pending Handling**: Tracks local pending spends, avoids double-spend UTXO reuse, and keeps balances accurate during mempool transitions.
- **Biometric Security**: Protect your wallet and recovery phrase with fingerprint or face recognition.
- **Secure Storage**: Sensitive keys and mnemonics are stored in encrypted secure storage.

## Recent Updates

- Upgraded to Flutter 3.44.4 • channel stable
- Upgraded to Android Gradle Plugin (AGP) 9.6.0
- Upgraded to Kotlin 2.4.0
- Fee Estimation Hardening:
  - Handles `estimatesmartfee` failures explicitly (RPC errors, missing `feerate`, and `feerate: -1` / no estimate).
  - Adds send-time manual fee entry fallback when estimation is unavailable.
  - Shows fee estimation status on Send screen with loading state and warning indicator.
  - Blocks signing/broadcast until a valid fee rate is provided (estimated or manual).
  - Fee-bump retry dialog only runs for transactions that started from estimator-provided fee rates.
- Manual Fee UX Improvements:
  - Unit toggle for `sat/vB` and `BTCS/kvB` with conversion.
  - Network-condition presets tuned to current conditions:
    - Low: `0.085 BTCS/kvB`
    - High: `0.10 BTCS/kvB`
- Performance improvements and dependency updates.

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

The wallet connects to the public RPC proxy at `https://bitcoinsilver.eu/btcs-rpc` by default (no authentication required).

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
- Current Google Play version 5.5
```

<a href="https://play.google.com/store/apps/details?id=top.bitcoinsilver.wallet2025&pli=1">
    <img src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" alt="Get it on Google Play" height="60">
</a>

## License

MIT
