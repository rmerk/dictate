# Robin App Distribution — Design Spec

**Date:** 2026-03-31
**Goal:** Ship Robin as a properly signed, notarized macOS app distributed directly (not App Store) with auto-updates via Sparkle.

## Context

Robin is a SwiftUI menu bar app wrapping the RCLI C++ voice AI engine via an xcframework. It already has:
- Working app with menu bar UI, panel window, settings, onboarding
- `RCLIEngine.xcframework` build pipeline (`scripts/build_xcframework.sh`)
- Entitlements for audio input, AppleScript automation, disable-library-validation
- Apple Developer account (team `HPNVTN3424`)
- `notarize.sh` script for `xcrun notarytool` submission
- Sparkle 2.9+ as SPM dependency (not yet wired up)
- `ModelDownloadService` for on-demand model downloads
- `PermissionService` for Microphone + Accessibility permission checks

## Distribution Channel

Direct distribution via GitHub Releases + GitHub Pages landing page. No App Store (CGEventTap, AppleScript automation, and global hotkeys are incompatible with App Sandbox).

## Design

### 1. Signing & Notarization

**Certificates required:**
- Developer ID Application (signs the .app)
- Developer ID Installer (signs the .dmg if using `productsign`, optional)

Both obtained from Apple Developer portal under Certificates, Identifiers & Profiles.

**Bundle ID:** Change from `ClearStack-Dev.Robin` to `ai.runanywhere.robin` before first public release. This must happen before any signed release ships — changing it later breaks Sparkle update continuity and user preferences.

**Build settings changes in Xcode:**
- Enable Hardened Runtime (`ENABLE_HARDENED_RUNTIME = YES`) — required for notarization
- Existing entitlements (audio-input, apple-events, disable-library-validation) are compatible with Hardened Runtime

**Notarization workflow:**
1. Archive in Xcode → Export with Developer ID signing
2. Run `notarize.sh` against the exported .app
3. Staple the notarization ticket: `xcrun stapler staple Robin.app`

No new code. Just Xcode build settings and existing script.

### 2. DMG Packaging

Create a `.dmg` disk image with Robin.app + Applications alias for drag-to-install.

**New file: `scripts/create_dmg.sh`**
- Takes a notarized+stapled `Robin.app` as input
- Creates temp read-write DMG via `hdiutil`
- Adds Applications symlink
- Converts to read-only compressed DMG
- Signs the DMG with Developer ID Application cert
- Notarizes the DMG (Apple recommends notarizing outermost container)
- Staples the DMG

**v1: No custom background image.** Plain DMG with app icon + Applications alias. Polish later.

### 3. Sparkle Auto-Updates

**Scope for v1:** Single stable channel. Beta channel deferred.

**Setup steps:**

1. **Generate EdDSA keypair:** Run Sparkle's `generate_keys` tool. Private key stored in your macOS Keychain. Public key goes in Info.plist.

2. **Wire up Sparkle in AppDelegate (~10 lines):**
   - Import Sparkle
   - Create `SPUStandardUpdaterController` as a property
   - Initialize in `applicationDidFinishLaunching`
   - Expose "Check for Updates" menu item bound to the controller

3. **Info.plist additions:**
   - `SUFeedURL` — URL to appcast.xml on GitHub Pages (e.g., `https://runanywhereai.github.io/rcli/appcast.xml`)
   - `SUPublicEDKey` — EdDSA public key string
   - `SUEnableAutomaticChecks` — `YES`

4. **Per-release appcast update:**
   - Place signed DMG in a staging folder
   - Run Sparkle's `generate_appcast` tool — reads DMG, signs with EdDSA key, outputs `appcast.xml`
   - Push updated `appcast.xml` to `gh-pages` branch

### 4. GitHub Pages

**Hosted on `gh-pages` branch** (keeps release artifacts separate from source).

**Contents:**
- `index.html` — Single static landing page with: app name, description, icon, download button (links to latest GitHub Release DMG), system requirements (macOS 13+, Apple Silicon)
- `appcast.xml` — Sparkle update feed

No framework, no build step. Plain HTML.

### 5. Onboarding & Permissions

**Existing infrastructure covers this.** Verification needed:

1. **First launch gate:** Onboarding triggers on first launch (use `hasCompletedOnboarding` in UserDefaults). Walk user through Microphone and Accessibility permission grants.

2. **Model download:** After permissions granted, trigger model download via `ModelDownloadService`. Show progress indicator. App is ready after download completes.

3. **Permission recovery:** If permission revoked after setup, show banner/alert guiding user back to System Settings. `PermissionService` polling already supports detection.

No major new code — verify existing flow works end-to-end for a fresh install.

## Release Workflow (Manual)

1. Bump version in Xcode (MARKETING_VERSION + CURRENT_PROJECT_VERSION)
2. Build xcframework: `bash scripts/build_xcframework.sh`
3. Archive in Xcode → Export with Developer ID
4. Notarize + staple: `bash scripts/notarize.sh Robin.app`
5. Create DMG: `bash scripts/create_dmg.sh Robin.app`
6. Notarize + staple DMG
7. Upload DMG to GitHub Release with tag
8. Generate appcast: `generate_appcast /path/to/dmg/folder`
9. Push appcast.xml to `gh-pages` branch
10. Update landing page download link if needed

## Deliverables

| Item | Type | Status |
|------|------|--------|
| Bundle ID change to `ai.runanywhere.robin` | Xcode setting | New |
| Enable Hardened Runtime | Xcode setting | New |
| `scripts/create_dmg.sh` | New script | New |
| Sparkle wiring in AppDelegate | ~10 lines Swift | New |
| Info.plist additions (SUFeedURL, SUPublicEDKey) | Plist entries | New |
| EdDSA keypair generation | One-time setup | New |
| `gh-pages` branch with index.html + appcast.xml | Static site | New |
| Verify onboarding flow end-to-end | Testing | Existing code |
| Developer ID certificates | Apple Developer portal | Manual setup |

## Out of Scope (v1)

- Beta release channel (Sparkle supports it, add later)
- Custom DMG background image
- CI/CD automation (GitHub Actions)
- Intel (x86_64) support
- App Store submission
- Analytics/telemetry
