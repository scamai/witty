#!/usr/bin/env bash
# Full Witty release pipeline: ReleaseFast build → Developer ID re-sign →
# DMG → notarize → staple → signed appcast. Produces dist/Witty.dmg, verified
# distributable; when HEAD carries a witty-v* tag, dist/Witty-<version>-macos-<arch>.dmg
# and dist/appcast.xml, which macos/scripts/publish_release.sh uploads.
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
#   WITTY_UPDATE_FEED_URL, WITTY_UPDATE_PUBLIC_ED_KEY
#                        Witty's Sparkle appcast URL
#                        (https://github.com/scamai/witty/releases/latest/download/appcast.xml)
#                        and the public half of Witty's EdDSA key. A tag build
#                        fails without both, with Ghostty's key, or with any
#                        other feed URL; an untagged build without both
#                        only warns, and has its updater turned off.
#   WITTY_SPARKLE_KEY_ACCOUNT
#                        keychain account of Witty's private EdDSA key
#                        (default: witty, as in `generate_keys --account witty`)
#   WITTY_CRITICAL_UPDATE=1
#                        mark the release critical in the appcast (a security
#                        fix): it cannot be skipped, and installs no sooner
#                        than any other update
#
# One-time prereqs:
#   1. Developer ID Application cert in the login keychain
#      (verify: security find-identity -p codesigning -v).
#   2. notarytool credential profile for the same team:
#        xcrun notarytool store-credentials "AC_NOTARY" \
#          --apple-id "<apple-id>" --team-id "<TEAMID>"
#      (it prompts for an app-specific password; keep it out of shell history)
#   3. Witty's EdDSA key in the keychain under WITTY_SPARKLE_KEY_ACCOUNT. Never
#      in the repository or CI; see macos/AGENTS.md.
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
# shellcheck source=lib_update.sh
. "$SCRIPT_DIR/lib_update.sh"

IDENTITY="$(resolve_sign_identity)"
PROFILE="${WITTY_NOTARY_PROFILE:-AC_NOTARY}"
# Fail before a several-minute build, not after it.
check_cert_validity "$IDENTITY"

# zig build reads both from the environment; the app's updater stays off
# unless it gets the two together. A release must have Witty's own and a build
# number its users' Sparkle will see as new.
TAG="$(resolve_release_tag "$REPO_ROOT")"
if [ -n "$TAG" ]; then
  echo "==> Checking the updater settings for $TAG…"
  check_release_update_settings "$TAG" "$REPO_ROOT"
elif [ -z "${WITTY_UPDATE_FEED_URL:-}" ] || [ -z "${WITTY_UPDATE_PUBLIC_ED_KEY:-}" ]; then
  echo "warning: WITTY_UPDATE_FEED_URL and WITTY_UPDATE_PUBLIC_ED_KEY are not both set;" \
    "this untagged build has its updater turned off" >&2
fi

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
