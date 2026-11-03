#!/usr/bin/env bash
# Upload a tagged release's DMG and appcast to its GitHub release, in the order
# that never lets the update feed point at a file that is not there yet: the DMG
# first, checked against the local file, then appcast.xml last. Once the release
# is published, checks that the feed users fetch is that appcast.
#
# Usage:
#   macos/scripts/publish_release.sh          upload, then check the live feed
#   macos/scripts/publish_release.sh --check  only check the live feed
#
# Before running it: release.sh has produced dist/Witty-<version>-macos-<arch>.dmg
# and dist/appcast.xml at the tag, the tag is pushed, and the GitHub release
# exists (a draft is fine) with its notes:
#   gh release create witty-vX.Y.Z --repo scamai/witty --draft \
#     --title "Witty vX.Y.Z — …" --notes-file <notes>
# Uploading to a draft keeps the feed unchanged until you publish it; then run
# this again with --check.
#
# Env overrides:
#   WITTY_RELEASE_TAG      release tag (default: the witty-v* tag at HEAD)
#   WITTY_UPDATE_FEED_URL  the feed the release's app reads (required)
#   WITTY_DIST             folder with the DMG and appcast (default: dist/)
#   WITTY_RELEASE_REPO     GitHub repository (default: scamai/witty)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=lib_signing.sh
. "$SCRIPT_DIR/lib_signing.sh"
# shellcheck source=lib_update.sh
. "$SCRIPT_DIR/lib_update.sh"

CHECK_ONLY=0
case "${1:-}" in
  "") ;;
  --check) CHECK_ONLY=1 ;;
  *)
    echo "usage: $0 [--check]" >&2
    exit 2
    ;;
esac

REPO="${WITTY_RELEASE_REPO:-scamai/witty}"
DIST="${WITTY_DIST:-$REPO_ROOT/dist}"
TAG="$(resolve_release_tag "$REPO_ROOT")"
[ -n "$TAG" ] || { echo "error: HEAD has no witty-v* tag; set WITTY_RELEASE_TAG" >&2; exit 1; }
release_checks feed "${WITTY_UPDATE_FEED_URL:-}"

APPCAST="$DIST/appcast.xml"
shopt -s nullglob
DMGS=("$DIST/Witty-${TAG#witty-}-macos-"*.dmg)
shopt -u nullglob
if [ "${#DMGS[@]}" -ne 1 ]; then
  echo "error: expected one $DIST/Witty-${TAG#witty-}-macos-<arch>.dmg, found ${#DMGS[@]}; run release.sh at $TAG" >&2
  exit 1
fi
DMG="${DMGS[0]}"
[ -f "$APPCAST" ] || { echo "error: $APPCAST not found; run release.sh at $TAG" >&2; exit 1; }

# The appcast must describe exactly this DMG; release.sh checked its signatures.
BUILD="$(release_checks project "$REPO_ROOT/macos/Ghostty.xcodeproj/project.pbxproj")"
release_checks appcast "$APPCAST" --dmg "$DMG" --tag "$TAG" --build "$BUILD" >/dev/null

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Fail unless the feed users fetch is byte for byte the local appcast.
check_live_feed() {
  local status=0
  fetch_published_appcast "$WITTY_UPDATE_FEED_URL" "$WORK/live.xml" || status=$?
  if [ "$status" -eq 2 ]; then
    echo "error: $WITTY_UPDATE_FEED_URL is not found; is $TAG published, and the latest release?" >&2
    return 1
  fi
  [ "$status" -eq 0 ] || return 1
  if ! cmp -s "$WORK/live.xml" "$APPCAST"; then
    echo "error: $WITTY_UPDATE_FEED_URL is not $APPCAST; is $TAG the latest release?" >&2
    return 1
  fi
  echo "    $WITTY_UPDATE_FEED_URL serves $TAG's appcast (build $BUILD)"
}

if [ "$CHECK_ONLY" -eq 1 ]; then
  echo "==> Checking the live feed…"
  check_live_feed
  exit 0
fi

if ! gh release view "$TAG" --repo "$REPO" --json tagName >/dev/null 2>&1; then
  echo "error: $REPO has no release for $TAG; create it first (a draft is fine):" >&2
  echo "  gh release create $TAG --repo $REPO --draft --title \"Witty ${TAG#witty-} — …\" --notes-file <notes>" >&2
  exit 1
fi

# Print "<size> <digest>" of the release asset named $1, or nothing if there is none.
# The digest is "sha256:<hex>", or empty where GitHub reports none.
asset_info() {
  local api
  api="$(gh release view "$TAG" --repo "$REPO" --json apiUrl --jq .apiUrl)"
  gh api "${api#https://api.github.com/}/assets" --paginate \
    --jq ".[] | select(.name == \"$1\") | \"\(.size) \(.digest // \"\")\""
}

# True if asset info $1 ("<size> <digest>") is the file with size $2 and digest $3.
asset_matches() {
  case "$1" in
    "$2 $3") return 0 ;;
    "$2 ")
      echo "note: GitHub reports no digest for this asset; only its size ($2 bytes) was compared" >&2
      return 0
      ;;
    *) return 1 ;;
  esac
}

# Upload $1 unless the release already has the same file; fail if it has another,
# or if what GitHub stored differs from the local file.
upload_asset() {
  local file="$1" name info size digest
  name="$(basename "$file")"
  size="$(wc -c <"$file" | tr -d ' ')"
  digest="sha256:$(sha256_of "$file")"
  info="$(asset_info "$name")"
  if [ -n "$info" ]; then
    if ! asset_matches "$info" "$size" "$digest"; then
      echo "error: $TAG already has a different $name ($info; local $size $digest); delete it first" >&2
      return 1
    fi
    echo "    $name is already uploaded"
    return 0
  fi
  gh release upload "$TAG" "$file" --repo "$REPO"
  info="$(asset_info "$name")"
  if ! asset_matches "$info" "$size" "$digest"; then
    echo "error: the uploaded $name is '$info', the local file is $size $digest" >&2
    return 1
  fi
  echo "    $name uploaded and matches the local file"
}

echo "==> 1/3 Uploading the DMG…"
upload_asset "$DMG"
echo "==> 2/3 Uploading the appcast, last…"
upload_asset "$APPCAST"

echo "==> 3/3 Checking the live feed…"
state="$(gh release view "$TAG" --repo "$REPO" --json isDraft,isPrerelease --jq '"\(.isDraft) \(.isPrerelease)"')"
case "$state" in
  "false false") check_live_feed ;;
  "true "*) echo "    $TAG is a draft: publish it, then run $0 --check" ;;
  *) echo "warning: $TAG is a prerelease, which the feed never serves (it follows the latest release)" >&2 ;;
esac
