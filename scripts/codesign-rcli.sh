#!/bin/bash
# Post-build codesign for rcli binary.
# Uses "RCLI Dev" self-signed cert if available (stable identity across rebuilds),
# otherwise falls back to ad-hoc signing with a fixed identifier.
BINARY="$1"
if [ -z "$BINARY" ]; then
    echo "Usage: codesign-rcli.sh <binary>" >&2
    exit 1
fi

if security find-identity -v 2>/dev/null | grep -q 'RCLI Dev'; then
    codesign -f -s 'RCLI Dev' "$BINARY" 2>/dev/null
    echo "-- Signed rcli with RCLI Dev certificate"
else
    codesign -f -s - -i ai.runanywhere.rcli "$BINARY" 2>/dev/null
    echo "-- Ad-hoc signed rcli (run: rcli dictate setup to create stable cert)"
fi
