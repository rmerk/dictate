#!/usr/bin/env bash
set -euo pipefail

# Notarize RCLI.app for distribution
# Usage: bash scripts/notarize.sh path/to/RCLI.app
#
# Requires:
#   APPLE_ID — your Apple ID email
#   APPLE_TEAM_ID — your team ID
#   APPLE_APP_PASSWORD — app-specific password

APP_PATH="${1:?Usage: notarize.sh path/to/RCLI.app}"
APP_NAME="$(basename "$APP_PATH" .app)"

echo "=== Zipping for notarization ==="
ZIP_PATH="/tmp/${APP_NAME}.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "=== Submitting to Apple ==="
xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "${APPLE_ID}" \
    --team-id "${APPLE_TEAM_ID}" \
    --password "${APPLE_APP_PASSWORD}" \
    --wait

echo "=== Stapling ==="
xcrun stapler staple "$APP_PATH"

echo "=== Done ==="
echo "Notarized: $APP_PATH"
rm "$ZIP_PATH"
