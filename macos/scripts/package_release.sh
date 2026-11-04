#!/usr/bin/env bash
# Package a distributable, notarized Witty DMG from the ReleaseLocal build, and
# for a tagged release the signed appcast that offers it to Witty's updater.
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
#                        named for upload: dist/Witty-v0.1.4-macos-<arch>.dmg,
#                        and the app's version and CHANGELOG.md must match it.
#   WITTY_DMG            output path (default: dist/Witty.dmg without a tag,
#                        else the name above). A tagged release also writes
#                        appcast.xml next to it.
#   WITTY_UPDATE_FEED_URL, WITTY_UPDATE_PUBLIC_ED_KEY
#                        when set, the app's SUFeedURL and SUPublicEDKey must
#                        equal them. A tagged release must carry Witty's own feed
#                        and key either way, and a build number higher than the
#                        previous tag's and the one the published appcast (at
#                        WITTY_UPDATE_FEED_URL, else the app's SUFeedURL) offers.
#   WITTY_SPARKLE_KEY_ACCOUNT, WITTY_CRITICAL_UPDATE
#                        see release.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=lib_signing.sh
. "$SCRIPT_DIR/lib_signing.sh"
# shellcheck source=lib_update.sh
. "$SCRIPT_DIR/lib_update.sh"

APP="${WITTY_APP:-${REPO_ROOT}/macos/build/ReleaseLocal/Witty.app}"

DEV_ID="$(resolve_sign_identity "${1:-}")"
PROFILE="${2:-AC_NOTARY}"

[ -d "${APP}" ] || { echo "error: ${APP} not found — run the zig build above first"; exit 1; }

TAG="$(resolve_release_tag "${REPO_ROOT}")"
if [ -n "${TAG}" ]; then
  check_release_version "${TAG}" \
    "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")" \
    "${REPO_ROOT}/CHANGELOG.md"
  BUILD="$(release_checks project "${REPO_ROOT}/macos/Ghostty.xcodeproj/project.pbxproj")"
  DMG_NAME="$(release_dmg_name "${TAG}" "$(lipo -archs "${APP}/Contents/MacOS/ghostty")")"
else
  DMG_NAME="Witty.dmg"
fi
DMG="${WITTY_DMG:-${REPO_ROOT}/dist/${DMG_NAME}}"
APPCAST="$(dirname "${DMG}")/appcast.xml"

echo "==> Signing identity: ${DEV_ID}"
echo "==> Notary profile:   ${PROFILE}"
echo "==> Output:           ${DMG}"
check_cert_validity "${DEV_ID}"

ENTITLEMENTS="${REPO_ROOT}/macos/GhosttyReleaseLocal.entitlements"
[ -f "${ENTITLEMENTS}" ] || { echo "error: missing ${ENTITLEMENTS}"; exit 1; }
CODESIGN_FLAGS=(--force --options runtime --timestamp)

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# Everything that changes the bundle happens before it is signed.
echo "==> Checking the updater…"
prepare_release_plist "${APP}"
if [ -n "${TAG}" ]; then
  # An appcast from an earlier run must never sit next to this DMG.
  rm -f "${APPCAST}"
  app_check=("${APP}" --build "${BUILD}")
  [ -z "${WITTY_UPDATE_FEED_URL:-}" ] || app_check+=(--feed "${WITTY_UPDATE_FEED_URL}")
  [ -z "${WITTY_UPDATE_PUBLIC_ED_KEY:-}" ] || app_check+=(--key "${WITTY_UPDATE_PUBLIC_ED_KEY}")
  release_checks app "${app_check[@]}"
  # release.sh checked this before building; a repackaged app gets the same check, so
  # a build number users' Sparkle would ignore as not newer is never signed. The
  # app's feed passed the check above.
  WITTY_UPDATE_FEED_URL="${WITTY_UPDATE_FEED_URL:-$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "${APP}/Contents/Info.plist")}" \
    check_build_number "${TAG}" "${REPO_ROOT}" >/dev/null
  critical_update_flag >/dev/null
else
  release_checks scan "${APP}"
fi
echo "    updater OK"

# xcodebuild's manual signing produces no secure timestamp, which the notary
# rejects — so always re-sign inside-out here (same as halo's pipeline).

echo "==> 1/8 Signing Sparkle.framework helpers inside-out…"
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

echo "==> 2/8 Signing the app bundle (hardened runtime + entitlements)…"
codesign "${CODESIGN_FLAGS[@]}" \
         --entitlements "${ENTITLEMENTS}" \
         --sign "${DEV_ID}" "${APP}"
codesign --verify --deep --strict --verbose=2 "${APP}"
codesign -dvvv "${APP}" 2>&1 | grep -E "^(Authority|TeamIdentifier|Timestamp)" | sort -u
echo "    codesign verify OK"

# The app gets its own ticket so it passes Gatekeeper offline after it is
# dragged out of the DMG; a ticket stapled only to the DMG stays behind.
echo "==> 3/8 Notarizing the app…"
ditto -c -k --keepParent "${APP}" "${WORK}/Witty.zip"
notarize "${WORK}/Witty.zip" "${PROFILE}"

echo "==> 4/8 Stapling the app…"
xcrun stapler staple "${APP}"
xcrun stapler validate "${APP}"

echo "==> 5/8 Building and signing the DMG…"
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

echo "==> 6/8 Notarizing and stapling the DMG…"
notarize "${DMG}" "${PROFILE}"
xcrun stapler staple "${DMG}"
xcrun stapler validate "${DMG}"

echo "==> 7/8 Gatekeeper checks…"
spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG}"
spctl --assess --type execute --verbose=2 "${APP}"
syspolicy_check distribution "${APP}"

# Last, because the appcast signs the DMG's final bytes, ticket included.
if [ -n "${TAG}" ]; then
  echo "==> 8/8 Generating and signing the appcast…"
  generate_signed_appcast "${TAG}" "${DMG}" "${BUILD}" "${APPCAST}" "${WORK}"
  echo "    ${APPCAST}"
  echo "==> Done. Distributable: ${DMG}"
  echo "    Upload both with macos/scripts/publish_release.sh: the DMG first, the appcast last."
else
  echo "==> 8/8 No appcast for an untagged build."
  echo "==> Done. Distributable: ${DMG}"
fi
