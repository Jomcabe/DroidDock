#!/usr/bin/env bash
#
# fetch-binaries.sh — provision the self-contained adb + scrcpy toolchain.
#
# Downloads the official, pre-compiled macOS binaries and lays them out under
# DroidDock/Resources/vendor so they can be copied into the app bundle and
# resolved at runtime via Bundle.main. This script is:
#
#   • idempotent  — re-running is a no-op unless --force or a version change
#   • self-signing — ad-hoc signs + de-quarantines so binaries run on Apple Silicon
#   • arch-aware  — picks aarch64 / x86_64 from `uname -m` (override with ARCH=)
#
# It is invoked both by `make setup` and by the Xcode pre-build Run Script phase.
#
# Layout produced:
#   DroidDock/Resources/vendor/
#   ├── adb                       (Google platform-tools — universal binary)
#   └── scrcpy/                   (scrcpy v4.0 static build; libs linked in)
#       ├── scrcpy
#       ├── scrcpy-server
#       └── …                     (bundled adb, man page, icons)
#
set -euo pipefail

# ── Configuration (override via environment) ────────────────────────────────
SCRCPY_VERSION="${SCRCPY_VERSION:-4.0}"
PLATFORM_TOOLS_URL="${PLATFORM_TOOLS_URL:-https://dl.google.com/android/repository/platform-tools-latest-darwin.zip}"

# Resolve repo paths relative to this script so it works from any CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENDOR_DIR="${REPO_ROOT}/DroidDock/Resources/vendor"
CACHE_DIR="${REPO_ROOT}/.cache"

FORCE=0
for arg in "$@"; do
    case "$arg" in
        --force|-f) FORCE=1 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

# ── Helpers ──────────────────────────────────────────────────────────────────
log()  { printf '\033[1;36m▸\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m⚠\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }

# Map `uname -m` to scrcpy's release-asset arch token.
scrcpy_arch() {
    local m="${ARCH:-$(uname -m)}"
    case "$m" in
        arm64|aarch64) echo "aarch64" ;;
        x86_64|amd64)  echo "x86_64" ;;
        *) die "unsupported architecture: $m (set ARCH=aarch64|x86_64 to override)" ;;
    esac
}

download() {
    local url="$1" dest="$2"
    log "downloading $(basename "$dest")"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 4 --retry-delay 2 --progress-bar -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --tries=4 -O "$dest" "$url"
    else
        die "neither curl nor wget is available"
    fi
}

# Ad-hoc sign + de-quarantine a single Mach-O file (macOS only).
sign_file() {
    local f="$1"
    is_macos || return 0
    xattr -d com.apple.quarantine "$f" 2>/dev/null || true
    if command -v codesign >/dev/null 2>&1; then
        codesign --force --sign - --timestamp=none "$f" >/dev/null 2>&1 \
            || warn "ad-hoc signing failed for $(basename "$f")"
    fi
}

sign_tree() {
    local dir="$1"
    is_macos || { warn "not macOS — skipping ad-hoc signing (do it on the build Mac)"; return 0; }
    log "ad-hoc signing embedded binaries"
    # Sign dylibs first, then executables (inner-out keeps signatures valid).
    while IFS= read -r -d '' f; do sign_file "$f"; done \
        < <(find "$dir" -type f \( -name '*.dylib' \) -print0)
    while IFS= read -r -d '' f; do
        # Executables: regular files with the user-exec bit set.
        if [[ -x "$f" && ! "$f" == *.dylib ]]; then sign_file "$f"; fi
    done < <(find "$dir" -type f -print0)
    xattr -dr com.apple.quarantine "$dir" 2>/dev/null || true
}

# ── Pre-flight ────────────────────────────────────────────────────────────────
ARCH_TOKEN="$(scrcpy_arch)"
SCRCPY_TARBALL="scrcpy-macos-${ARCH_TOKEN}-v${SCRCPY_VERSION}.tar.gz"
SCRCPY_URL="https://github.com/Genymobile/scrcpy/releases/download/v${SCRCPY_VERSION}/${SCRCPY_TARBALL}"

mkdir -p "${VENDOR_DIR}" "${CACHE_DIR}"

# A small stamp file lets us short-circuit when nothing changed.
STAMP="${VENDOR_DIR}/.provisioned"
WANT="scrcpy=${SCRCPY_VERSION} arch=${ARCH_TOKEN}"

if [[ "$FORCE" -eq 0 && -f "$STAMP" && "$(cat "$STAMP" 2>/dev/null)" == "$WANT" \
      && -x "${VENDOR_DIR}/adb" && -x "${VENDOR_DIR}/scrcpy/scrcpy" \
      && -f "${VENDOR_DIR}/scrcpy/scrcpy-server" ]]; then
    log "vendor binaries already provisioned (${WANT}) — nothing to do."
    exit 0
fi

log "provisioning DroidDock toolchain → ${VENDOR_DIR}"
log "  arch=${ARCH_TOKEN}  scrcpy=v${SCRCPY_VERSION}"

# ── adb (Android platform-tools) ──────────────────────────────────────────────
PT_ZIP="${CACHE_DIR}/platform-tools-darwin.zip"
[[ "$FORCE" -eq 1 || ! -f "$PT_ZIP" ]] && download "$PLATFORM_TOOLS_URL" "$PT_ZIP"

PT_TMP="$(mktemp -d)"
trap 'rm -rf "$PT_TMP"' EXIT
log "extracting platform-tools"
unzip -q -o "$PT_ZIP" -d "$PT_TMP"
[[ -f "${PT_TMP}/platform-tools/adb" ]] || die "adb not found in platform-tools archive"
cp -f "${PT_TMP}/platform-tools/adb" "${VENDOR_DIR}/adb"
chmod +x "${VENDOR_DIR}/adb"

# ── scrcpy (static macOS build: self-contained binary + scrcpy-server) ────────
SC_TGZ="${CACHE_DIR}/${SCRCPY_TARBALL}"
[[ "$FORCE" -eq 1 || ! -f "$SC_TGZ" ]] && download "$SCRCPY_URL" "$SC_TGZ"

SC_TMP="$(mktemp -d)"
trap 'rm -rf "$PT_TMP" "$SC_TMP"' EXIT
log "extracting scrcpy"
tar -xzf "$SC_TGZ" -C "$SC_TMP"

# The tarball may extract into a versioned subdirectory; locate the dir that
# actually contains the `scrcpy` executable and treat that as the payload root.
SC_BIN="$(find "$SC_TMP" -type f -name scrcpy -perm -u+x -print -quit 2>/dev/null || true)"
[[ -z "$SC_BIN" ]] && SC_BIN="$(find "$SC_TMP" -type f -name scrcpy -print -quit)"
[[ -n "$SC_BIN" ]] || die "scrcpy binary not found inside ${SCRCPY_TARBALL}"
SC_PAYLOAD="$(dirname "$SC_BIN")"
[[ -f "${SC_PAYLOAD}/scrcpy-server" ]] || die "scrcpy-server not found alongside scrcpy"

rm -rf "${VENDOR_DIR}/scrcpy"
mkdir -p "${VENDOR_DIR}/scrcpy"
# Copy the whole payload so scrcpy-server stays beside the scrcpy binary.
cp -a "${SC_PAYLOAD}/." "${VENDOR_DIR}/scrcpy/"
chmod +x "${VENDOR_DIR}/scrcpy/scrcpy"

# ── Sign + finalize ───────────────────────────────────────────────────────────
sign_tree "${VENDOR_DIR}"
printf '%s' "$WANT" > "$STAMP"

log "done. embedded toolchain:"
printf '   %s\n' \
    "adb            → ${VENDOR_DIR#"${REPO_ROOT}/"}/adb" \
    "scrcpy         → ${VENDOR_DIR#"${REPO_ROOT}/"}/scrcpy/scrcpy" \
    "scrcpy-server  → ${VENDOR_DIR#"${REPO_ROOT}/"}/scrcpy/scrcpy-server"
