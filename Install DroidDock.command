#!/bin/bash
#
# Install DroidDock.command
# ─────────────────────────
# Double-click this file in Finder to build DroidDock from source and install it
# to your Applications folder — no typing required.
#
# (If macOS says it "cannot be opened because it is from an unidentified
#  developer", right-click the file → Open → Open. That only happens once.)
#
set -euo pipefail

# Always run from the repository root, however Finder launched us.
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(pwd)"

APP_NAME="DroidDock"
XCODEGEN_VERSION="${XCODEGEN_VERSION:-2.45.4}"
CACHE_DIR="${REPO_ROOT}/.cache"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
info() { printf '\033[1;36m▸\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m⚠\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; }

# Print a friendly result and keep the window open until a key is pressed.
finish() {
    local code=$?
    echo
    if [[ $code -eq 0 ]]; then
        ok "DroidDock is installed and launching. You can close this window."
    else
        err "Install did not complete (exit code $code). See the messages above."
    fi
    echo
    read -n 1 -s -r -p "Press any key to close…" || true
    echo
    exit $code
}
trap finish EXIT

clear
bold "🤖  DroidDock Installer"
echo "Builds DroidDock from source and installs it to Applications. Zero typing."
echo

# ── 1. macOS only ─────────────────────────────────────────────────────────────
if [[ "$(uname -s)" != "Darwin" ]]; then
    err "DroidDock is a macOS application."
    exit 1
fi

# ── 2. Full Xcode (needed to compile the SwiftUI app + asset catalog) ─────────
if ! xcrun --find actool >/dev/null 2>&1; then
    err "Full Xcode is required (the Command Line Tools alone can't build the app)."
    echo "   1. Install Xcode from the App Store (opening it for you now)."
    echo "   2. Launch Xcode once and accept the license agreement."
    echo "   3. Double-click this installer again."
    open "macappstore://apps.apple.com/app/xcode/id497799835" 2>/dev/null \
        || open "https://apps.apple.com/app/xcode/id497799835" 2>/dev/null || true
    exit 1
fi
ok "Xcode toolchain found — $(xcodebuild -version | head -1)."

# ── 3. XcodeGen (prefer PATH, else fetch the official prebuilt — no Homebrew) ──
if command -v xcodegen >/dev/null 2>&1; then
    ok "XcodeGen found on PATH."
else
    info "Fetching XcodeGen ${XCODEGEN_VERSION} (one-time, no Homebrew needed)…"
    mkdir -p "${CACHE_DIR}"
    dist="${CACHE_DIR}/xcodegen-dist"
    if [[ ! -x "${dist}/xcodegen/bin/xcodegen" ]]; then
        zip="${CACHE_DIR}/xcodegen-${XCODEGEN_VERSION}.zip"
        curl -fL --retry 4 --retry-delay 2 -o "$zip" \
            "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"
        rm -rf "$dist"; mkdir -p "$dist"
        unzip -q -o "$zip" -d "$dist"
        chmod +x "${dist}/xcodegen/bin/xcodegen"
    fi
    # `share/` must sit beside `bin/` — adding bin to PATH satisfies that.
    export PATH="${dist}/xcodegen/bin:${PATH}"
    ok "XcodeGen ${XCODEGEN_VERSION} ready."
fi

# ── 4. Provision the embedded adb + scrcpy toolchain ──────────────────────────
info "Provisioning the embedded adb / scrcpy toolchain…"
"${REPO_ROOT}/scripts/fetch-binaries.sh"

# ── 5. Generate the project and build a Release ───────────────────────────────
info "Generating the Xcode project…"
xcodegen generate

info "Building ${APP_NAME} (Release). This can take a couple of minutes…"
xcodebuild \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -derivedDataPath build \
    build

PRODUCT="build/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "$PRODUCT" ]]; then
    err "Build finished but ${PRODUCT} was not produced."
    exit 1
fi
ok "Build succeeded."

# ── 6. Quit any running copy so the update replaces it (no two instances) ─────
info "Quitting any running copy of ${APP_NAME}…"
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
pkill -x "${APP_NAME}" 2>/dev/null || true
# Reap any scrcpy mirror window the old copy may have left behind.
pkill -f "window-title=DroidDock-Mirror" 2>/dev/null || true
sleep 1   # let it release the bundle before we overwrite it

# ── 7. Install into /Applications (fall back to ~/Applications) ───────────────
DEST="/Applications"
if [[ ! -w "$DEST" ]]; then
    warn "/Applications is not writable; installing to ~/Applications instead."
    DEST="${HOME}/Applications"
    mkdir -p "$DEST"
fi
info "Installing to ${DEST}/${APP_NAME}.app…"
rm -rf "${DEST:?}/${APP_NAME}.app"
cp -R "$PRODUCT" "${DEST}/"
# Clear the quarantine flag so the freshly-built app opens without a prompt.
xattr -dr com.apple.quarantine "${DEST}/${APP_NAME}.app" 2>/dev/null || true
ok "Installed → ${DEST}/${APP_NAME}.app"

# ── 8. Launch ─────────────────────────────────────────────────────────────────
open "${DEST}/${APP_NAME}.app" || true
