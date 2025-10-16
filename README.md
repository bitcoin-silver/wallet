# bitcoinsilver_wallet

A new Flutter project.

## Getting Started

# Build Configuration

This document explains how to build the Bitcoin Silver Wallet with RPC credentials for production.

## Security Notice

**NEVER commit RPC credentials to version control.** The app uses environment variables during build time to inject credentials securely.

## **For RPC credentials please contact @mrvistos or @janosraul in BTCS official Tg: https://t.me/official_bitcoinsilver**

## Building for Production

### Method 1: Using --dart-define flags

```bash
flutter build apk --dart-define=RPC_URL=http://YOUR_RPC_URL:PORT \
                  --dart-define=RPC_USER=your_rpc_user \
                  --dart-define=RPC_PASSWORD=your_rpc_password
```

For iOS:
```bash
flutter build ios --dart-define=RPC_URL=http://YOUR_RPC_URL:PORT \
                  --dart-define=RPC_USER=your_rpc_user \
                  --dart-define=RPC_PASSWORD=your_rpc_password
```

### Method 2: Using a config file (Recommended for CI/CD)

Create a file named `dart_defines.json` (add to .gitignore):

```json
{
  "RPC_URL": "http://YOUR_RPC_URL:PORT",
  "RPC_USER": "your_rpc_user",
  "RPC_PASSWORD": "your_rpc_password"
}
```

Then use:
```bash
flutter build apk --dart-define-from-file=dart_defines.json
```
```bash
flutter run --dart-define-from-file=dart_defines.json
```

### Method 3: Environment Variables + Build Script

Create a `build.sh` script:

```bash
#!/bin/bash

# Load from environment or .env file
source .env  # or export variables manually

flutter build apk \
  --dart-define=RPC_URL="$RPC_URL" \
  --dart-define=RPC_USER="$RPC_USER" \
  --dart-define=RPC_PASSWORD="$RPC_PASSWORD"
```

## Development Builds

For development without credentials (will need manual RPC setup in app):

```bash
flutter run
# or
flutter build apk
```

## CI/CD Integration

### GitHub Actions Example

```yaml
- name: Build APK
  env:
    RPC_URL: ${{ secrets.RPC_URL }}
    RPC_USER: ${{ secrets.RPC_USER }}
    RPC_PASSWORD: ${{ secrets.RPC_PASSWORD }}
  run: |
    flutter build apk \
      --dart-define=RPC_URL="$RPC_URL" \
      --dart-define=RPC_USER="$RPC_USER" \
      --dart-define=RPC_PASSWORD="$RPC_PASSWORD"
```

### GitLab CI Example

```yaml
build:
  script:
    - flutter build apk
        --dart-define=RPC_URL="$RPC_URL"
        --dart-define=RPC_USER="$RPC_USER"
        --dart-define=RPC_PASSWORD="$RPC_PASSWORD"
  variables:
    RPC_URL: $CI_RPC_URL
    RPC_USER: $CI_RPC_USER
    RPC_PASSWORD: $CI_RPC_PASSWORD
```

## Verifying Configuration

After building, the credentials will be stored securely in the device's secure storage and retrieved at runtime.

## Security Best Practices

1. ✅ Never commit credentials to git
2. ✅ Use environment variables or secure CI/CD secrets
3. ✅ Add `dart_defines.json` to `.gitignore`
4. ✅ Rotate credentials regularly
5. ✅ Use different credentials for development/staging/production


# Building Android App Bundle (AAB) for Google Play

## Quick Build Command

```bash
# Build AAB with RPC credentials
flutter build appbundle \
  --dart-define=RPC_URL=http://your-rpc-url:port \
  --dart-define=RPC_USER=your_username \
  --dart-define=RPC_PASSWORD=your_password
```

Or using config file:
```bash
flutter build appbundle --dart-define-from-file=dart_defines.json
```

## Prerequisites

### 1. Configure App Signing

#### Option A: Upload Key (Recommended)
Google Play will manage your app signing key.

1. Generate upload keystore:
```bash
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

2. Create `android/key.properties`:
```properties
storePassword=your_store_password
keyPassword=your_key_password
keyAlias=upload
storeFile=/path/to/upload-keystore.jks
```

3. Update `android/app/build.gradle`:
```gradle
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    ...

    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }

    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled true
            shrinkResources true
        }
    }
}
```

#### Option B: App Signing by Google Play (Easier)
Let Google Play manage everything - just upload and they handle signing.

### 2. Update App Version

Edit `pubspec.yaml`:
```yaml
version: 1.0.3+3  # 1.0.3 is version name, 3 is version code
```

### 3. Configure App Details

Edit `android/app/build.gradle`:
```gradle
android {
    ...
    defaultConfig {
        applicationId "com.bitcoinsilver.wallet"  # Your unique ID
        minSdkVersion 21
        targetSdkVersion 34
        versionCode 3
        versionName "1.0.3"
    }
}
```

## Build Commands

### Standard Release Build
```bash
flutter build appbundle --release \
  --dart-define=RPC_URL=http://your-rpc-url:port \
  --dart-define=RPC_USER=your_username \
  --dart-define=RPC_PASSWORD=your_password
```

### With Obfuscation (Recommended for Production)
```bash
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info=build/app/outputs/symbols \
  --dart-define=RPC_URL=http://your-rpc-url:port \
  --dart-define=RPC_USER=your_username \
  --dart-define=RPC_PASSWORD=your_password
```

### Using Config File
```bash
# Create dart_defines.json with your credentials
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info=build/app/outputs/symbols \
  --dart-define-from-file=dart_defines.json
  
  flutter build appbundle --release --obfuscate --split-debug-info=build/app/outputs/symbols --dart-define-from-file=dart_defines.json
```

## Output Location

The AAB file will be created at:
```
build/app/outputs/bundle/release/app-release.aab
```

## Uploading to Google Play Console

1. Go to [Google Play Console](https://play.google.com/console)
2. Select your app (or create new app)
3. Go to **Production** → **Create new release**
4. Upload `app-release.aab`
5. Fill in release notes
6. Review and roll out

## Build Script (Recommended)

Create `build_playstore.sh`:
```bash
#!/bin/bash

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | xargs)
fi

# Clean previous builds
flutter clean
flutter pub get

# Build AAB with obfuscation
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info=build/app/outputs/symbols \
  --dart-define=RPC_URL="$RPC_URL" \
  --dart-define=RPC_USER="$RPC_USER" \
  --dart-define=RPC_PASSWORD="$RPC_PASSWORD"

echo "✅ Build complete!"
echo "📦 AAB location: build/app/outputs/bundle/release/app-release.aab"
```

Make executable:
```bash
chmod +x build_playstore.sh
./build_playstore.sh
```

## CI/CD Example (GitHub Actions)

`.github/workflows/release.yml`:
```yaml
name: Release to Play Store

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - uses: actions/setup-java@v3
        with:
          distribution: 'zulu'
          java-version: '17'

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.35.3'

      - name: Decode keystore
        run: |
          echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 -d > android/app/keystore.jks

      - name: Create key.properties
        run: |
          echo "storePassword=${{ secrets.KEYSTORE_PASSWORD }}" > android/key.properties
          echo "keyPassword=${{ secrets.KEY_PASSWORD }}" >> android/key.properties
          echo "keyAlias=${{ secrets.KEY_ALIAS }}" >> android/key.properties
          echo "storeFile=keystore.jks" >> android/key.properties

      - name: Build AAB
        run: |
          flutter pub get
          flutter build appbundle --release \
            --obfuscate \
            --split-debug-info=build/app/outputs/symbols \
            --dart-define=RPC_URL="${{ secrets.RPC_URL }}" \
            --dart-define=RPC_USER="${{ secrets.RPC_USER }}" \
            --dart-define=RPC_PASSWORD="${{ secrets.RPC_PASSWORD }}"

      - name: Upload to Play Store
        uses: r0adkll/upload-google-play@v1
        with:
          serviceAccountJsonPlainText: ${{ secrets.PLAY_STORE_JSON }}
          packageName: com.bitcoinsilver.wallet
          releaseFiles: build/app/outputs/bundle/release/app-release.aab
          track: production
```

## Troubleshooting

### Issue: "You uploaded a debuggable APK"
**Solution**: Make sure to use `--release` flag

### Issue: "Upload key not configured"
**Solution**: Set up signing config in build.gradle

### Issue: "Version code already used"
**Solution**: Increment version in pubspec.yaml

### Issue: "RPC credentials not working"
**Solution**: Verify dart-define values are set correctly

## Security Checklist

Before uploading to Play Store:

- [ ] RPC credentials set via --dart-define (not hardcoded)
- [ ] Keystore file is secure and backed up
- [ ] key.properties is in .gitignore
- [ ] Obfuscation enabled for production
- [ ] Version code incremented
- [ ] Test the AAB on a real device before upload
- [ ] ProGuard rules configured if needed

## File Sizes

- APK: Larger, includes all architectures
- AAB: Smaller, Google Play optimizes per device
- Typical AAB: 20-50% smaller than APK

## Next Steps

1. Build AAB with credentials
2. Test on real device (install from AAB)
3. Upload to Play Store Internal Testing
4. Graduate to Production when ready

# Security Documentation

## RPC Credentials Management

### Overview

The Bitcoin Silver Wallet uses a secure, production-ready approach for managing RPC node credentials:

- ✅ **No hardcoded credentials** in source code
- ✅ **Environment-based configuration** during build time
- ✅ **Encrypted storage** on device using platform-specific secure storage
- ✅ **Runtime retrieval** from secure storage

### How It Works

1. **Build Time**: Credentials are injected via `--dart-define` flags
2. **First Launch**: Credentials are stored in encrypted secure storage (Keychain/KeyStore)
3. **Runtime**: Credentials are retrieved securely from device storage
4. **Protection**: All credentials protected by device security (biometrics/PIN)

### For Developers

Quick start:
```bash
# Copy and configure environment
cp .env.example .env
# Edit .env with your credentials

# Build with credentials
flutter build apk \
  --dart-define-from-file=dart_defines.json
```

### Security Features

#### 1. Secure Storage
- iOS: Uses Keychain Services
- Android: Uses Android KeyStore
- Encrypted at rest

#### 2. Biometric Authentication
- Optional biometric lock on app launch
- Re-authentication on app resume from background
- Configurable in Settings

#### 3. Private Key Protection
- Stored in Flutter Secure Storage
- Never logged or transmitted
- Optional biometric protection before display

#### 4. Network Security
- All RPC communications use authenticated requests
- Credentials never exposed in UI or logs

### Security Checklist

When deploying to production:

- [ ] Build with `--dart-define` flags (never use hardcoded values)
- [ ] Store credentials in CI/CD secrets (GitHub Actions, GitLab CI, etc.)
- [ ] Enable biometric authentication for users
- [ ] Use HTTPS for RPC endpoints when possible
- [ ] Rotate RPC credentials regularly
- [ ] Different credentials for dev/staging/production
- [ ] Review `.gitignore` to ensure no credential files committed

### Reporting Security Issues

If you discover a security vulnerability, please email [security contact] instead of using the issue tracker.

### Compliance

- GDPR: No personal data collected or transmitted
- Data Privacy: All sensitive data encrypted at rest
- Open Source: Full transparency of security implementation

