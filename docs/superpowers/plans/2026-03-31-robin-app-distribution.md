# Robin App Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Robin as a signed, notarized macOS app with DMG packaging, Sparkle auto-updates, and a GitHub Pages landing page.

**Architecture:** Manual release pipeline — build in Xcode, sign with Developer ID, notarize via `xcrun notarytool`, package as DMG, host on GitHub Releases with Sparkle appcast on GitHub Pages.

**Tech Stack:** SwiftUI, Sparkle 2.9+, hdiutil, xcrun notarytool, GitHub Pages

**Spec:** `docs/superpowers/specs/2026-03-31-robin-app-distribution-design.md`

---

### Task 1: Update Bundle ID and Xcode Build Settings

**Files:**
- Modify: `app/Robin/Robin.xcodeproj/project.pbxproj` (lines 400, 466, 488, 509)
- Modify: `app/Robin/Robin/Info.plist`

These changes must be made in Xcode directly (editing pbxproj by hand is fragile). Open `app/Robin/Robin.xcodeproj` in Xcode and follow these steps.

- [ ] **Step 1: Change bundle identifier**

In Xcode: Select Robin target → Signing & Capabilities → Change Bundle Identifier from `ClearStack-Dev.Robin` to `ai.runanywhere.robin`.

This updates 2 lines in project.pbxproj (Debug + Release):
```
PRODUCT_BUNDLE_IDENTIFIER = "ai.runanywhere.robin";
```

Also update the test target from `ClearStack-Dev.RobinTests` to `ai.runanywhere.robin.tests` in the same way (select RobinTests target → Signing & Capabilities).

- [ ] **Step 2: Verify Hardened Runtime is enabled**

In Xcode: Robin target → Signing & Capabilities → Hardened Runtime should already be present (it is — lines 358, 424 in pbxproj show `ENABLE_HARDENED_RUNTIME = YES`). Confirm it's there.

- [ ] **Step 3: Verify signing is set to Developer ID**

In Xcode: Robin target → Signing & Capabilities → Team should be `HPNVTN3424`. Signing Certificate should be "Developer ID Application" (change from "Apple Development" if needed — this matters for export, not debug builds).

- [ ] **Step 4: Update Info.plist usage descriptions to say "Robin" not "RCLI"**

Edit `app/Robin/Robin/Info.plist` — change the usage description strings:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Robin needs microphone access to hear your voice commands and dictation.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Robin uses AppleScript to execute actions like creating notes, opening apps, and controlling system settings.</string>
</dict>
</plist>
```

- [ ] **Step 5: Build and run to verify nothing broke**

Run: Cmd+B in Xcode. Verify the app launches and the menu bar icon appears.

- [ ] **Step 6: Commit**

```bash
cd app/Robin
git add -A
git commit -m "chore: update bundle ID to ai.runanywhere.robin and fix usage descriptions"
```

---

### Task 2: Wire Up Sparkle Auto-Updates

**Files:**
- Modify: `app/Robin/Robin/RobinApp.swift` (AppDelegate class, lines 5-11 and 13-15)
- Modify: `app/Robin/Robin/Views/Settings/GeneralSettingsView.swift` (add Updates section)
- Modify: `app/Robin/Robin/Info.plist` (add Sparkle keys)

- [ ] **Step 1: Generate EdDSA keypair**

Sparkle's `generate_keys` tool is built as part of the SPM dependency. Find it in DerivedData after building:

```bash
# Build Robin once in Xcode first (Cmd+B), then:
find ~/Library/Developer/Xcode/DerivedData -name "generate_keys" -type f 2>/dev/null | head -1
```

Run the tool:
```bash
/path/to/generate_keys
```

This outputs an EdDSA public key string and stores the private key in your macOS Keychain under "Sparkle EdDSA Key". Copy the public key — you'll need it for Info.plist.

Expected output:
```
A]key:
<base64 public key string>
```

- [ ] **Step 2: Add Sparkle keys to Info.plist**

Edit `app/Robin/Robin/Info.plist` — add the three Sparkle keys:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Robin needs microphone access to hear your voice commands and dictation.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Robin uses AppleScript to execute actions like creating notes, opening apps, and controlling system settings.</string>
    <key>SUFeedURL</key>
    <string>https://runanywhereai.github.io/rcli/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>PASTE_YOUR_EDDSA_PUBLIC_KEY_HERE</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
</dict>
</plist>
```

Replace `PASTE_YOUR_EDDSA_PUBLIC_KEY_HERE` with the actual public key from Step 1.

- [ ] **Step 3: Wire up Sparkle in AppDelegate**

Edit `app/Robin/Robin/RobinApp.swift`. Add the Sparkle import and updater controller to `AppDelegate`:

```swift
import SwiftUI
import AppKit
import CRCLIEngine
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = EngineService()
    let hotkey = HotkeyService()
    let overlay = OverlayService()
    let permissions = PermissionService()
    let downloads = ModelDownloadService()
    let conversation = ConversationStore()
    let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await startApp() }
    }
    // ... rest unchanged
```

Only two lines change: the `import Sparkle` line and the `updaterController` property. `startingUpdater: true` means Sparkle begins checking for updates automatically on launch (honoring `SUEnableAutomaticChecks`).

- [ ] **Step 4: Add "Check for Updates" to GeneralSettingsView**

Edit `app/Robin/Robin/Views/Settings/GeneralSettingsView.swift`. Add `import Sparkle` and an Updates section:

```swift
import SwiftUI
import ServiceManagement
import Sparkle

struct GeneralSettingsView: View {
    @Environment(EngineService.self) private var engine
    @AppStorage("appearance") private var appearanceRaw = "system"
    @State private var launchAtLogin = false
    @State private var selectedPersonality = "default"

    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Color scheme", selection: $appearanceRaw) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue // revert
                        }
                    }
            }

            Section("Personality") {
                Picker("Voice personality", selection: $selectedPersonality) {
                    Text("Default").tag("default")
                    Text("Professional").tag("professional")
                    Text("Quirky").tag("quirky")
                    Text("Cynical").tag("cynical")
                    Text("Nerdy").tag("nerdy")
                }
                .onChange(of: selectedPersonality) { _, newValue in
                    try? engine.setPersonality(newValue)
                }
            }

            Section("Updates") {
                Button("Check for Updates...") {
                    updater.checkForUpdates()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            selectedPersonality = engine.personality
        }
    }
}
```

- [ ] **Step 5: Thread the updater through to GeneralSettingsView**

The `GeneralSettingsView` now requires an `SPUUpdater` parameter. Update `SettingsView` to pass it through. Find where `GeneralSettingsView()` is instantiated in `app/Robin/Robin/Views/SettingsView.swift` and change it to `GeneralSettingsView(updater: updater)`.

`SettingsView` needs to receive the updater too. The cleanest approach: pass the `SPUUpdater` via SwiftUI environment from `RobinApp.swift`.

In `RobinApp.swift`, update the Settings scene to pass the updater:

```swift
Settings {
    SettingsView()
        .environment(appDelegate.engine)
        .environment(appDelegate.hotkey)
        .environment(appDelegate.permissions)
        .environment(appDelegate.downloads)
        .environment(\.hotkeySetup, { appDelegate.setupHotkey() })
        .environment(\.updater, appDelegate.updaterController.updater)
        .preferredColorScheme(preferredColorScheme)
}
```

Define the environment key (add to `RobinApp.swift` or a shared file):

```swift
import Sparkle

private struct UpdaterKey: EnvironmentKey {
    static let defaultValue: SPUUpdater? = nil
}

extension EnvironmentValues {
    var updater: SPUUpdater? {
        get { self[UpdaterKey.self] }
        set { self[UpdaterKey.self] = newValue }
    }
}
```

Then in `SettingsView.swift`, read `@Environment(\.updater) private var updater` and pass `updater!` to `GeneralSettingsView(updater:)`.

Alternatively, a simpler approach: just pass the updater directly via init on `SettingsView`. Choose whichever fits the existing pattern — the environment approach is more SwiftUI-idiomatic since the other services already use `@Environment`.

- [ ] **Step 6: Build and verify**

Run: Cmd+B in Xcode. Open Settings → General. Verify "Check for Updates..." button appears. Clicking it will fail (no appcast yet) — that's expected.

- [ ] **Step 7: Commit**

```bash
cd app/Robin
git add -A
git commit -m "feat: wire up Sparkle auto-updates with check-for-updates in Settings"
```

---

### Task 3: Create DMG Packaging Script

**Files:**
- Create: `scripts/create_dmg.sh`

- [ ] **Step 1: Write the DMG creation script**

Create `scripts/create_dmg.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Create a DMG for Robin.app distribution
# Usage: bash scripts/create_dmg.sh path/to/Robin.app [signing-identity]
#
# The .app should already be notarized and stapled before running this.
# If signing-identity is provided, the DMG will be signed and notarized.

APP_PATH="${1:?Usage: create_dmg.sh path/to/Robin.app [signing-identity]}"
SIGNING_IDENTITY="${2:-}"

APP_NAME="$(basename "$APP_PATH" .app)"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1.0")
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_DIR="$(dirname "$APP_PATH")"
DMG_PATH="${DMG_DIR}/${DMG_NAME}"
TMP_DMG="/tmp/${APP_NAME}-tmp.dmg"
VOLUME_NAME="${APP_NAME}"

echo "=== Creating DMG for ${APP_NAME} v${VERSION} ==="

# Clean up any previous attempt
rm -f "$TMP_DMG" "$DMG_PATH"

# Create temporary read-write DMG
# Size: app size + 20MB headroom
APP_SIZE_KB=$(du -sk "$APP_PATH" | cut -f1)
DMG_SIZE_KB=$((APP_SIZE_KB + 20480))

hdiutil create \
    -size "${DMG_SIZE_KB}k" \
    -fs HFS+ \
    -volname "$VOLUME_NAME" \
    -type SPARSE \
    "$TMP_DMG"

# Mount the temporary DMG
MOUNT_DIR=$(hdiutil attach "${TMP_DMG}.sparseimage" -readwrite -noverify | grep "/Volumes/" | tail -1 | awk '{print $NF}')
echo "Mounted at: $MOUNT_DIR"

# Copy app and create Applications symlink
cp -R "$APP_PATH" "$MOUNT_DIR/"
ln -s /Applications "$MOUNT_DIR/Applications"

# Unmount
hdiutil detach "$MOUNT_DIR" -quiet

# Convert to read-only compressed DMG
hdiutil convert "${TMP_DMG}.sparseimage" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH"

rm -f "${TMP_DMG}.sparseimage"

# Sign the DMG if identity provided
if [[ -n "$SIGNING_IDENTITY" ]]; then
    echo "=== Signing DMG ==="
    codesign --sign "$SIGNING_IDENTITY" "$DMG_PATH"

    echo "=== Notarizing DMG ==="
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "${APPLE_ID}" \
        --team-id "${APPLE_TEAM_ID}" \
        --password "${APPLE_APP_PASSWORD}" \
        --wait

    echo "=== Stapling DMG ==="
    xcrun stapler staple "$DMG_PATH"
fi

echo "=== Done ==="
echo "DMG: $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/create_dmg.sh
```

- [ ] **Step 3: Test with an unsigned build**

Build Robin in Xcode (Cmd+B), then locate the .app in DerivedData:

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Build/Products/Debug/Robin.app" -maxdepth 5 2>/dev/null | head -1)
bash scripts/create_dmg.sh "$APP"
```

Expected: Creates a `Robin-1.0.dmg` next to the .app. Double-click it to verify the volume opens with Robin.app and an Applications alias.

- [ ] **Step 4: Commit**

```bash
git add scripts/create_dmg.sh
git commit -m "feat: add DMG creation script for Robin distribution"
```

---

### Task 4: Create GitHub Pages Site

**Files:**
- Create: `gh-pages` branch with `index.html` and placeholder `appcast.xml`

- [ ] **Step 1: Create the gh-pages branch**

```bash
git checkout --orphan gh-pages
git rm -rf .
```

- [ ] **Step 2: Create the landing page**

Create `index.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Robin — Private, Local AI Assistant for macOS</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
            color: #1d1d1f;
            background: #fbfbfd;
            text-align: center;
            padding: 80px 20px;
        }
        .container { max-width: 640px; margin: 0 auto; }
        h1 { font-size: 48px; font-weight: 700; margin-bottom: 12px; }
        .subtitle { font-size: 21px; color: #86868b; margin-bottom: 40px; }
        .download-btn {
            display: inline-block;
            background: #0071e3;
            color: white;
            font-size: 17px;
            font-weight: 500;
            padding: 12px 32px;
            border-radius: 980px;
            text-decoration: none;
            transition: background 0.2s;
        }
        .download-btn:hover { background: #0077ed; }
        .requirements {
            margin-top: 16px;
            font-size: 14px;
            color: #86868b;
        }
        .features {
            display: flex;
            gap: 32px;
            justify-content: center;
            margin: 60px 0;
        }
        .feature {
            flex: 1;
            max-width: 180px;
        }
        .feature-icon { font-size: 32px; margin-bottom: 8px; }
        .feature h3 { font-size: 16px; margin-bottom: 4px; }
        .feature p { font-size: 14px; color: #86868b; }
        footer {
            margin-top: 80px;
            font-size: 14px;
            color: #86868b;
        }
        footer a { color: #0071e3; text-decoration: none; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Robin</h1>
        <p class="subtitle">Private, Local AI Assistant for macOS</p>

        <a href="https://github.com/RunanywhereAI/rcli/releases/latest" class="download-btn">
            Download for Mac
        </a>
        <p class="requirements">Requires macOS 13+ and Apple Silicon (M1 or later)</p>

        <div class="features">
            <div class="feature">
                <div class="feature-icon">🎤</div>
                <h3>Voice Commands</h3>
                <p>Control your Mac hands-free with natural speech</p>
            </div>
            <div class="feature">
                <div class="feature-icon">✏️</div>
                <h3>Dictation</h3>
                <p>Type anywhere with your voice, faster than keyboard</p>
            </div>
            <div class="feature">
                <div class="feature-icon">🔒</div>
                <h3>100% Private</h3>
                <p>All AI runs locally on your Mac. Nothing leaves your device</p>
            </div>
        </div>

        <footer>
            <a href="https://github.com/RunanywhereAI/rcli">GitHub</a>
        </footer>
    </div>
</body>
</html>
```

- [ ] **Step 3: Create placeholder appcast.xml**

Create `appcast.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Robin Updates</title>
        <language>en</language>
        <!-- Items will be added by generate_appcast after each release -->
    </channel>
</rss>
```

This placeholder will be overwritten by Sparkle's `generate_appcast` tool when you publish your first release.

- [ ] **Step 4: Commit and push gh-pages**

```bash
git add index.html appcast.xml
git commit -m "feat: add Robin landing page and Sparkle appcast placeholder"
git push -u origin gh-pages
```

- [ ] **Step 5: Enable GitHub Pages**

Go to GitHub repo → Settings → Pages → Source: Deploy from branch → Branch: `gh-pages` → `/` (root) → Save.

Verify the site is live at `https://runanywhereai.github.io/rcli/`.

- [ ] **Step 6: Switch back to main**

```bash
git checkout main
```

---

### Task 5: Verify Onboarding Flow End-to-End

**Files:**
- Read: `app/Robin/Robin/Views/OnboardingView.swift`
- Read: `app/Robin/Robin/Services/PermissionService.swift`
- Read: `app/Robin/Robin/Services/ModelDownloadService.swift`

No code changes expected — this is a manual verification task.

- [ ] **Step 1: Reset onboarding state**

```bash
defaults delete ai.runanywhere.robin hasCompletedOnboarding 2>/dev/null || true
```

(Use the new bundle ID. If testing before the bundle ID change, use `ClearStack-Dev.Robin`.)

- [ ] **Step 2: Launch Robin from Xcode**

Cmd+R. Verify:
1. Menu bar icon appears
2. Onboarding window opens automatically (Welcome step)
3. Can navigate through all 4 steps: Welcome → Models → Permissions → Hotkey
4. Model download starts when advancing past the Models step
5. Permission cards show correct granted/not-granted state
6. "Done" button dismisses onboarding and sends notification

- [ ] **Step 3: Verify fresh-install model download**

If models aren't already downloaded, verify the download progress bar appears in the Models step and completes successfully. If models exist, verify the step doesn't error.

- [ ] **Step 4: Verify permission recovery**

1. Revoke Microphone in System Settings → Privacy & Security → Microphone → uncheck Robin
2. Verify the menu bar view shows the "Microphone access needed" banner
3. Re-grant the permission
4. Verify the banner disappears (PermissionService polling picks it up)

---

### Task 6: Document the Release Workflow

**Files:**
- Create: `docs/release-workflow.md`

- [ ] **Step 1: Write the release workflow doc**

Create `docs/release-workflow.md`:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add docs/release-workflow.md
git commit -m "docs: add Robin release workflow"
```

---

## Summary

| Task | What | New Files |
|------|------|-----------|
| 1 | Bundle ID + Xcode settings | — (Xcode changes) |
| 2 | Sparkle auto-updates | Modified: RobinApp.swift, GeneralSettingsView.swift, Info.plist |
| 3 | DMG packaging script | `scripts/create_dmg.sh` |
| 4 | GitHub Pages site | `index.html`, `appcast.xml` (on gh-pages branch) |
| 5 | Verify onboarding | — (manual testing) |
| 6 | Release workflow docs | `docs/release-workflow.md` |
