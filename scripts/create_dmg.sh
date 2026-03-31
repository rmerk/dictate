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
