#!/usr/bin/env bash
# Full Witty release pipeline: ReleaseFast build → Developer ID re-sign →
# DMG → notarize → staple. Produces dist/Witty.dmg, verified distributable.
#
# Usage:
#   macos/scripts/release.sh
#
# Env overrides:
#   ZIG                  zig binary to use (must satisfy the repo's minimum
#                        version; default: newest of PATH zig, brew zig)
#   WITTY_SIGN_IDENTITY  Developer ID identity (default: the keychain's only
#                        "Developer ID Application" identity; required when
#                        there are several)
#   WITTY_NOTARY_PROFILE notarytool keychain profile (default: AC_NOTARY)
#
# One-time prereqs:
#   1. Developer ID Application cert in the login keychain
#      (verify: security find-identity -p codesigning -v).
#   2. notarytool credential profile for the same team:
#        xcrun notarytool store-credentials "AC_NOTARY" \
#          --apple-id "<apple-id>" --team-id "<TEAMID>"
#      (it prompts for an app-specific password; keep it out of shell history)
#
# Pitfalls this script guards against:
#   - ~/.local/bin/zig is a 0.15.2 shim; this repo requires >= 0.16.0.
#   - xcodebuild manual signing adds no secure timestamp, which Apple's
#     notary rejects — package_release.sh therefore re-signs every Mach-O
#     inside-out with --timestamp (halo-style).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=lib_signing.sh
. "$SCRIPT_DIR/lib_signing.sh"

IDENTITY="$(resolve_sign_identity)"
PROFILE="${WITTY_NOTARY_PROFILE:-AC_NOTARY}"
# Fail before a several-minute build, not after it.
check_cert_validity "$IDENTITY"

# Pick a zig that meets the repo's minimum version.
REQUIRED_ZIG="$(grep -oE 'minimum_zig_version = "[0-9.]+"' "$REPO_ROOT/build.zig.zon" | grep -oE '[0-9.]+' | head -1)"
[ -n "$REQUIRED_ZIG" ] || { echo "error: cannot read minimum_zig_version from build.zig.zon" >&2; exit 1; }
version_ge() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]; }
pick_zig() {
  local candidates=("${ZIG:-}" "$(command -v zig || true)" /opt/homebrew/bin/zig)
  local c v
  for c in "${candidates[@]}"; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    v="$("$c" version 2>/dev/null || true)"
    if [ -n "$v" ] && version_ge "$REQUIRED_ZIG" "$v"; then
      echo "$c"; return 0
    fi
  done
  echo "error: no zig >= $REQUIRED_ZIG found (tried: ${candidates[*]})" >&2
  return 1
}
ZIG_BIN="$(pick_zig)"
echo "==> Using zig: $ZIG_BIN ($("$ZIG_BIN" version)), repo requires >= $REQUIRED_ZIG"

echo "==> 1/2 Building Witty.app (ReleaseFast, Developer ID signed)…"
(cd "$REPO_ROOT" && "$ZIG_BIN" build \
  -Demit-macos-app \
  -Doptimize=ReleaseFast \
  -Dmacos-sign-identity="$IDENTITY")

echo "==> 2/2 Signing, packaging, notarizing…"
"$SCRIPT_DIR/package_release.sh" "$IDENTITY" "$PROFILE"
