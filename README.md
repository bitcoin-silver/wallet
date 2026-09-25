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
- **QR Code Scanning**: Reads BIP21 payment requests (`bitcoinsilver:<address>?amount=..&message=..`) and fills in both the address and the amount.
- **Payment Requests**: Request an amount with a QR code or a shared message that includes a link for the [web wallet](https://bitcoinsilver.top/web-wallet/). Requests can also be pasted into the Send screen.
- **Address Book**: Labelled contacts with `.btcs` import/export, compatible with the web wallet.
- **Transaction Tracking**: Real-time history with smart confirmation tracking and pending-state management.
- **Smart Pending Handling**: Tracks local pending spends, avoids double-spend UTXO reuse, and keeps balances accurate during mempool transitions.
- **Biometric Security**: Protect your wallet and recovery phrase with fingerprint or face recognition.
- **Secure Storage**: Sensitive keys and mnemonics are stored in encrypted secure storage.

### Latest Updates

Version 6.4.1 (details in [CHANGELOG.md](CHANGELOG.md)), together with web wallet 3.1.1:

- Faster start: the app no longer waits for the servers before showing the wallet; history and balance load in the background.
- Returning to the app keeps the transaction list on screen while it refreshes (no more brief "No Transactions Yet").
- Fingerprint lock covers every screen when returning to the app, including Send, Receive and Settings.
- Payment requests: the name in a request is marked as not verified, a warning appears when a request borrows a saved contact's name, and hidden characters are removed.
- Address book: each contact has a Send button.

Version 6.4, released together with web wallet 3.1:

- Scanning a payment request now fills in the amount, not only the address, and shows the request's note.
- Payment requests shared from the Receive screen include a web wallet link.
- Fixed: exporting the address book over an older file could leave part of the old file behind, making it impossible to import.

Earlier:

- Qr code scanner added to Address Book
- Added "Subtract Fee from amount" toggle in send view
- Chat has been removed due to a recent Google Play policy change/update
- Refined Send fee UX with a clearer fee source selector (`Manual` vs `Auto (Node Fee)`) and active-state highlighting.
- Simplified estimated fee card layout with clearer grouping: estimated fee, fee source, fee rate, and net send after fee (advanced input-selected mode).
- Improved simple mode fee estimation to be amount-aware using confirmed UTXOs, producing more realistic estimates than a fixed baseline example.
- Kept advanced mode fee behavior input-aware from selected UTXOs (coin control), so detailed estimates remain tied to selected inputs.

- Upgraded to Flutter 3.47.2 • channel stable
- Upgraded to Android Gradle Plugin (AGP) 9.7.1
- Upgraded to Kotlin 2.4.10
- Migration Flow Hardening:
  - Added explicit migration warning + acknowledgment step before migration starts.
  - Added funded-wallet pre-check for smart fee availability and blocks migration when node fee estimation is unavailable.
  - Added pending-transaction guard: migration is delayed while unconfirmed/pending transactions exist.
  - Added secure-storage preflight and fail-closed behavior before irreversible sweep operations.
  - Added migration integrity checks for migrated private key/address consistency before success handoff.
  - Added detailed failure dialog path so users get clear migration error reasons.
  - Added stage-based migration progress dialogs for both pre-send preparation and send/finalize phases.
  - Added migration interruption handling with explicit user guidance when app context changes mid-flow.
  - Added migration cancellation feedback dialog so exits are not silent.
  - Added one-tap "Copy All Backup Data" action (formatted address + seed + WIF + optional sweep amount).
  - Enforced post-success backup confirmation dialog before final completion.
  - Updated empty-wallet migration success wording to avoid claiming a transaction was sent.
- Fee Estimation Hardening:
  - Handles `estimatesmartfee` failures explicitly (RPC errors, missing `feerate`, and `feerate: -1` / no estimate).
  - Adds send-time manual fee entry fallback when estimation is unavailable.
  - Shows fee estimation status on Send screen with loading state and warning indicator.
  - Blocks signing/broadcast until a valid fee rate is provided (estimated or manual).
  - Fee-bump retry dialog only runs for transactions that started from estimator-provided fee rates.
- Manual Fee UX Improvements:
  - Unit toggle for `sat/vB` and `BTCS/kvB` with conversion.
  - Network-condition presets tuned to current conditions:
    - Low: `0.00000226 BTCS/kvB`
    - High: `0.0004 BTCS/kvB`
- Resume/Background Reliability:
  - Improved silent transaction refresh behavior so latest transactions are reloaded after app resume/background transitions.
  - Added shared wallet sync coalescing for timer/resume/manual refresh to avoid overlapping sync races.
  - Reduced startup blocking when RPC is unavailable while preserving RPC warning visibility.
- Send Preview Consistency:
  - Transaction preview now updates live on amount edits.
  - Auto input-selection mode now shows computed expected change instead of "Auto".
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
# --extra-gen-snapshot-options=--strip removes the DWARF debug info that newer
# Flutter otherwise leaves in the native library (it would partly undo
# --obfuscate). `flutter build` has no --strip flag of its own. The symbols
# needed to read crash reports are still written to --split-debug-info.
flutter build appbundle --release --obfuscate \
  --extra-gen-snapshot-options=--strip \
  --split-debug-info=build/app/outputs/symbols \
  --dart-define-from-file=dart_defines.json

# iOS
flutter build ios --release --dart-define-from-file=dart_defines.json
```

Output locations:

- APK: `build/app/outputs/flutter-apk/app-release.apk`
- AAB: `build/app/outputs/bundle/release/app-release.aab`
- Debug symbols (upload to Play Console for readable crash reports): `build/app/outputs/symbols`

With `--extra-gen-snapshot-options=--strip`, Flutter (3.47) ends the bundle build with "Release app bundle failed to strip debug symbols from native libraries" and exit code 1, although the `.aab` is complete, signed and stripped. Its check expects a debug-symbol entry for `libapp.so`, which `--strip` intentionally leaves empty. Check that `build/app/outputs/bundle/release/app-release.aab` has a fresh timestamp before uploading.

Before each Play Store upload, raise `versionCode` in `android/app/build.gradle.kts` (the Play Console refuses a code it has seen, including internal test uploads).

## iOS Release (GitHub Actions)

The workflow `.github/workflows/ios_release.yml` ("iOS Release Build") builds a signed iOS app on a GitHub macOS runner and uploads it to **TestFlight**. It never runs on a push: it only starts when you start it. Commits that should not be picked up by any future automatic workflow can still carry `[skip ci]` in the message.

### Before starting it

1. Commit and push everything that should be in the build; the workflow builds the `main` branch as it is on GitHub.
2. Raise the version in `pubspec.yaml` (`version: 6.4.1+5`). iOS uses it directly: `6.4.1` is the version users see, and the number after `+` is the build number, which must be higher than any build already uploaded to App Store Connect, including TestFlight uploads.
3. Check that the signing files have not expired: the Apple Distribution certificate (yearly) and the provisioning profile (yearly). Renewing either means updating its repository secret (below).

### Starting it

On GitHub: open the repository → **Actions** → **iOS Release Build** → **Run workflow** → branch `main` → **Run workflow**.

Or from a terminal with the [GitHub CLI](https://cli.github.com/):

```bash
gh workflow run ios_release.yml -R bitcoin-silver/wallet --ref main
gh run watch -R bitcoin-silver/wallet        # follow it (choose the new run)
gh run list -R bitcoin-silver/wallet --workflow ios_release.yml -L 5
```

A run takes roughly 8 to 10 minutes. When it succeeds, the build appears in App Store Connect → TestFlight after Apple's processing (usually 10 to 30 minutes). The `.ipa` is also kept as the run's `ios-ipa` artifact, even when the TestFlight upload fails.

### What it uses

- Flutter **3.47.5**, pinned in the workflow to the version used for local and Android builds. When you upgrade Flutter locally, raise `flutter-version` in the workflow too.
- Bundle ID `top.bitcoinsilver.bitcoinsilverWallet`, manual signing with the "Apple Distribution" certificate.
- Repository secrets (Settings → Secrets and variables → Actions):

| Secret | Used for |
|---|---|
| `IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD` | Apple Distribution certificate (.p12, base64) and its password |
| `IOS_PROVISION_PROFILE_BASE64` | App Store provisioning profile (.mobileprovision, base64) |
| `KEYCHAIN_PASSWORD` | Any password for the temporary keychain on the runner |
| `APPSTORE_TEAM_ID` | Apple developer team ID |
| `APPSTORE_API_KEY_ID`, `APPSTORE_API_ISSUER_ID`, `APPSTORE_API_PRIVATE_KEY` | App Store Connect API key used to upload to TestFlight |
| `RPC_URL`, `NOTIFICATION_API_KEY`, `LIVECOINWATCH_API_KEY` | Written into `dart_defines.json`, like the local `dart_defines.json` |
| `RPC_USER`, `RPC_PASSWORD` | Optional; not needed for the default public RPC proxy |

To store a file as a base64 secret: `base64 -i file.p12 | pbcopy` on macOS, or `base64 -w0 file.p12` on Linux, then paste the output as the secret's value.

### If it fails

Open the run on GitHub and look at the first red step:

- **Import signing certificate…**: a certificate or profile secret is wrong or expired.
- **Build signed IPA**: a code or dependency problem; try `flutter build ios --release` locally on a Mac with the same Flutter version.
- **Upload to TestFlight**: usually a build number that was already used (raise the number after `+` in `pubspec.yaml`) or an App Store Connect API key issue.

## Security

- Private keys stored in encrypted secure storage (Keychain/KeyStore)
- Optional biometric authentication
- RPC credentials injected at build time, never hardcoded
- No personal data collected

**Never commit `dart_defines.json` or `.env` to version control.**

## Migration Safety Checklist

Use this quick checklist after migration-related changes:

- Warning + Consent: Migration starts only after user acknowledgment dialog is accepted.
- Pending Guard: Migration is blocked while pending/unconfirmed transactions exist.
- Fee Guard: Funded migration is blocked when smart fee estimation is unavailable.
- Storage Guard: Secure storage preflight succeeds before sweep/save steps.
- Integrity Guard: On success, migrated private key and derived address are validated.
- Backup Gate: Success requires user backup confirmation dialog completion.
- Backup Copy Action: Users can copy all migration backup data in one formatted payload.
- Interruption UX: Context-loss/interruption is surfaced with a retry-in-one-go notice.
- Failure UX: Any failure path shows a clear reason dialog and keeps old wallet active.
- Resume Sync: After app resume/background transitions, latest transactions reload correctly.

Suggested manual smoke test sequence:

1. Empty wallet migration (12-word and 24-word).
2. Funded wallet migration with small amount.
3. Funded wallet migration with larger/fragmented UTXOs.
4. Pending transaction scenario (verify migration is delayed).
5. Smart fee unavailable scenario (verify migration is blocked with explanation).

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -m 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

For bugs or feature requests, please open an issue.

Current Google Play version: 6.3

<a href="https://play.google.com/store/apps/details?id=top.bitcoinsilver.wallet2025&pli=1">
    <img src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" alt="Get it on Google Play" height="60">
</a>

## License

MIT
