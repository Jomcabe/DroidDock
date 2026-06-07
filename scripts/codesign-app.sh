#!/usr/bin/env bash
#
# codesign-app.sh — sign DroidDock.app (and its embedded toolchain) with a
# Developer ID for distribution / notarization. Local development does NOT need
# this — Xcode's automatic "Sign to Run Locally" plus the ad-hoc signatures
# applied by fetch-binaries.sh are sufficient to run on your own machine.
#
# Usage:
#   IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#       scripts/codesign-app.sh /path/to/DroidDock.app
#
# After signing you would typically notarize:
#   xcrun notarytool submit DroidDock.zip --keychain-profile "AC_PROFILE" --wait
#   xcrun stapler staple /path/to/DroidDock.app
#
set -euo pipefail

APP="${1:?usage: codesign-app.sh /path/to/DroidDock.app}"
IDENTITY="${IDENTITY:?set IDENTITY to your \"Developer ID Application: …\" string}"
ENTITLEMENTS="${ENTITLEMENTS:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/DroidDock/DroidDock.entitlements}"

[[ -d "$APP" ]] || { echo "no such app bundle: $APP" >&2; exit 1; }
[[ "$(uname -s)" == "Darwin" ]] || { echo "macOS only" >&2; exit 1; }

VENDOR="$APP/Contents/Resources/vendor"

echo "▸ signing embedded dylibs"
find "$VENDOR" -type f -name '*.dylib' -print0 | while IFS= read -r -d '' f; do
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$f"
done

echo "▸ signing embedded executables (adb, scrcpy)"
for exe in "$VENDOR/adb" "$VENDOR/scrcpy/scrcpy"; do
    [[ -f "$exe" ]] && codesign --force --options runtime --timestamp --sign "$IDENTITY" "$exe"
done

echo "▸ signing the app bundle (with entitlements + hardened runtime)"
codesign --force --deep --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" "$APP"

echo "▸ verifying"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "✓ signed: $APP"
