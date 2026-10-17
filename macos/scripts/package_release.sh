#!/usr/bin/env bash
# Package a distributable, notarized Witty DMG from the ReleaseLocal build.
# Modeled on halo's scripts/sign_and_notarize.sh.
#
# Build first (Developer ID signed, hardened runtime comes from the Xcode
# ReleaseLocal configuration):
#   zig build -Demit-macos-app -Doptimize=ReleaseFast \
#     -Dmacos-sign-identity="Developer ID Application: <Name> (<TEAMID>)"
#
# Prereqs (one-time):
#   1. Developer ID Application cert in the login keychain
#      (verify: security find-identity -p codesigning -v).
#   2. A stored notarytool credential profile for the same team:
#        xcrun notarytool store-credentials "AC_NOTARY" \
#          --apple-id "<apple-id>" --team-id "<TEAMID>"
#      (it prompts for an app-specific password; keep it out of shell history)
#
# Usage:
#   macos/scripts/package_release.sh [signing-identity] [notary-profile]
#
# Env overrides:
#   WITTY_SIGN_IDENTITY  used when no identity argument is given; with neither,
#                        the keychain's only Developer ID Application identity
#   WITTY_APP            app bundle to package (default: the ReleaseLocal build).
#                        Point it at a copy to repackage without touching the
#                        build output a running Witty may be using.
#   WITTY_RELEASE_TAG    release tag such as witty-v0.1.4 (default: the
#                        witty-v* tag at HEAD, if any). With a tag the DMG is
#                        named for upload: dist/Witty-v0.1.4-macos-<arch>.dmg.
#   WITTY_DMG            output path (default: dist/Witty.dmg without a tag,
#                        else the name above)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=lib_signing.sh
. "$SCRIPT_DIR/lib_signing.sh"

APP="${WITTY_APP:-${REPO_ROOT}/macos/build/ReleaseLocal/Witty.app}"

DEV_ID="$(resolve_sign_identity "${1:-}")"
PROFILE="${2:-AC_NOTARY}"

[ -d "${APP}" ] || { echo "error: ${APP} not found — run the zig build above first"; exit 1; }

TAG="${WITTY_RELEASE_TAG:-$(git -C "${REPO_ROOT}" describe --exact-match --tags --match 'witty-v*' 2>/dev/null || true)}"
if [ -n "${TAG}" ]; then
  DMG_NAME="$(release_dmg_name "${TAG}" "$(lipo -archs "${APP}/Contents/MacOS/ghostty")")"
else
  DMG_NAME="Witty.dmg"
fi
DMG="${WITTY_DMG:-${REPO_ROOT}/dist/${DMG_NAME}}"

echo "==> Signing identity: ${DEV_ID}"
echo "==> Notary profile:   ${PROFILE}"
echo "==> Output:           ${DMG}"
check_cert_validity "${DEV_ID}"

ENTITLEMENTS="${REPO_ROOT}/macos/GhosttyReleaseLocal.entitlements"
[ -f "${ENTITLEMENTS}" ] || { echo "error: missing ${ENTITLEMENTS}"; exit 1; }
CODESIGN_FLAGS=(--force --options runtime --timestamp)

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# xcodebuild's manual signing produces no secure timestamp, which the notary
# rejects — so always re-sign inside-out here (same as halo's pipeline).

echo "==> 1/7 Signing Sparkle.framework helpers inside-out…"
SPARKLE_FW="${APP}/Contents/Frameworks/Sparkle.framework"
if [ -d "${SPARKLE_FW}" ]; then
  SPARKLE_V="${SPARKLE_FW}/Versions/B"
  codesign "${CODESIGN_FLAGS[@]}" --sign "${DEV_ID}" \
           "${SPARKLE_V}/XPCServices/Installer.xpc"
  codesign "${CODESIGN_FLAGS[@]}" --preserve-metadata=entitlements \
           --sign "${DEV_ID}" "${SPARKLE_V}/XPCServices/Downloader.xpc"
  codesign "${CODESIGN_FLAGS[@]}" --sign "${DEV_ID}" \
           "${SPARKLE_V}/Autoupdate"
  codesign "${CODESIGN_FLAGS[@]}" --sign "${DEV_ID}" \
           "${SPARKLE_V}/Updater.app"
  codesign "${CODESIGN_FLAGS[@]}" --sign "${DEV_ID}" \
           "${SPARKLE_FW}"
  echo "    Sparkle.framework signed"
fi

for PLUGIN in "${APP}"/Contents/PlugIns/*.plugin; do
  [ -e "${PLUGIN}" ] || continue
  codesign "${CODESIGN_FLAGS[@]}" --sign "${DEV_ID}" "${PLUGIN}"
  echo "    $(basename "${PLUGIN}") signed"
done

echo "==> 2/7 Signing the app bundle (hardened runtime + entitlements)…"
codesign "${CODESIGN_FLAGS[@]}" \
         --entitlements "${ENTITLEMENTS}" \
         --sign "${DEV_ID}" "${APP}"
codesign --verify --deep --strict --verbose=2 "${APP}"
codesign -dvvv "${APP}" 2>&1 | grep -E "^(Authority|TeamIdentifier|Timestamp)" | sort -u
echo "    codesign verify OK"

# The app gets its own ticket so it passes Gatekeeper offline after it is
# dragged out of the DMG; a ticket stapled only to the DMG stays behind.
echo "==> 3/7 Notarizing the app…"
ditto -c -k --keepParent "${APP}" "${WORK}/Witty.zip"
notarize "${WORK}/Witty.zip" "${PROFILE}"

echo "==> 4/7 Stapling the app…"
xcrun stapler staple "${APP}"
xcrun stapler validate "${APP}"

echo "==> 5/7 Building and signing the DMG…"
mkdir -p "$(dirname "${DMG}")"
rm -f "${DMG}"
if command -v create-dmg >/dev/null 2>&1; then
  create-dmg --volname "Witty" --app-drop-link 480 170 \
    --window-size 660 360 "${DMG}" "${APP}" >/dev/null
else
  hdiutil create -volname "Witty" -srcfolder "${APP}" -ov -format UDZO "${DMG}" >/dev/null
fi
codesign --force --timestamp --sign "${DEV_ID}" "${DMG}"
codesign --verify --strict --verbose=2 "${DMG}"
echo "    ${DMG}"

echo "==> 6/7 Notarizing and stapling the DMG…"
notarize "${DMG}" "${PROFILE}"
xcrun stapler staple "${DMG}"
xcrun stapler validate "${DMG}"

echo "==> 7/7 Gatekeeper checks…"
spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG}"
spctl --assess --type execute --verbose=2 "${APP}"
syspolicy_check distribution "${APP}"

echo "==> Done. Distributable: ${DMG}"
