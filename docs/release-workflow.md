# Robin Release Workflow

## Prerequisites

1. **Developer ID Application certificate** installed in Keychain (from Apple Developer portal)
2. **Sparkle EdDSA private key** in Keychain (generated via `generate_keys`)
3. **Environment variables** for notarization:
   ```bash
   export APPLE_ID="your@email.com"
   export APPLE_TEAM_ID="HPNVTN3424"
   export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # App-specific password from appleid.apple.com
   ```

## Steps

### 1. Bump Version

In Xcode: Robin target → General → Version (MARKETING_VERSION) and Build (CURRENT_PROJECT_VERSION).

### 2. Build xcframework

```bash
bash scripts/build_xcframework.sh
```

### 3. Archive and Export

In Xcode:
1. Product → Archive
2. Distribute App → Developer ID
3. Export to a folder (e.g., `~/Desktop/Robin-Release/`)

### 4. Notarize the App

```bash
bash scripts/notarize.sh ~/Desktop/Robin-Release/Robin.app
```

### 5. Create DMG

```bash
bash scripts/create_dmg.sh ~/Desktop/Robin-Release/Robin.app "Developer ID Application: Your Name (HPNVTN3424)"
```

### 6. Upload to GitHub Release

```bash
VERSION="1.0.0"
gh release create "v${VERSION}" ~/Desktop/Robin-Release/Robin-${VERSION}.dmg \
    --title "Robin ${VERSION}" \
    --notes "Release notes here"
```

### 7. Update Appcast

```bash
# Find generate_appcast in DerivedData
GENERATE_APPCAST=$(find ~/Library/Developer/Xcode/DerivedData -name "generate_appcast" -type f 2>/dev/null | head -1)

# Run against folder containing the signed DMG
$GENERATE_APPCAST ~/Desktop/Robin-Release/

# Copy to gh-pages
git checkout gh-pages
cp ~/Desktop/Robin-Release/appcast.xml .
git add appcast.xml
git commit -m "release: update appcast for v${VERSION}"
git push
git checkout main
```
