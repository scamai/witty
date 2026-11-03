#!/usr/bin/env bash
# Updater helpers for release.sh, package_release.sh and publish_release.sh: the
# checks that stop a tag build without Witty's own update feed and key, the pinned
# Sparkle tools, and the signed appcast. Source it. The rules themselves live in
# release_checks.py, which has its own tests (test_release_checks.py).

LIB_UPDATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

release_checks() { python3 "$LIB_UPDATE_DIR/release_checks.py" "$@"; }

# Sparkle's command-line tools come from the release of the framework the Xcode
# project pins (XCRemoteSwiftPackageReference "Sparkle", exactVersion), and the
# download is refused unless it has this SHA-256: the digest GitHub lists for the
# asset, which matched a download of it on 2026-11-03. When the project moves to a
# new Sparkle, update both lines; check_sparkle_tools_version fails until then.
SPARKLE_VERSION="2.9.6"
SPARKLE_SHA256="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"
SPARKLE_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"

# The keychain account that holds Witty's private EdDSA key (generate_keys --account).
WITTY_SPARKLE_KEY_ACCOUNT="${WITTY_SPARKLE_KEY_ACCOUNT:-witty}"

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    sha256sum "$1" | cut -d' ' -f1
  fi
}

# Fail unless the Xcode project ($1) pins the Sparkle version whose tools this
# file fetches.
check_sparkle_tools_version() {
  local pinned
  pinned="$(release_checks sparkle-version "$1")" || return 1
  if [ "$pinned" != "$SPARKLE_VERSION" ]; then
    echo "error: the Xcode project uses Sparkle $pinned but lib_update.sh fetches the $SPARKLE_VERSION tools; update SPARKLE_VERSION and SPARKLE_SHA256" >&2
    return 1
  fi
}

# Download the tools tarball from $1, refuse it unless its SHA-256 is $2, and unpack
# bin/generate_appcast and bin/sign_update into $3/bin.
fetch_sparkle_tools_from() {
  local url="$1" sha="$2" dest="$3" tarball actual
  mkdir -p "$dest"
  tarball="$dest/sparkle-tools.tar.xz"
  if ! curl -fsSL --proto-redir '=https' --retry 2 -o "$tarball" "$url"; then
    echo "error: cannot download $url" >&2
    return 1
  fi
  actual="$(sha256_of "$tarball")"
  if [ "$actual" != "$sha" ]; then
    echo "error: $url has SHA-256 $actual, expected $sha; not using it" >&2
    rm -f "$tarball"
    return 1
  fi
  tar -xJf "$tarball" -C "$dest" ./bin/generate_appcast ./bin/sign_update || return 1
  rm -f "$tarball"
}

fetch_sparkle_tools() { fetch_sparkle_tools_from "$SPARKLE_URL" "$SPARKLE_SHA256" "$1"; }

# Fetch the appcast users get today ($1, the feed URL) into $2, without cookies.
# Returns 0 when fetched, 2 when there is none yet (HTTP 404: the latest release
# has no appcast, as before the first release with an updater), 1 otherwise.
fetch_published_appcast() {
  local code
  if ! code="$(curl -sS -L --proto '=https' --proto-redir '=https' --max-time 60 \
    -o "$2" -w '%{http_code}' "$1")"; then
    echo "error: cannot fetch the published appcast $1" >&2
    return 1
  fi
  case "$code" in
    200) return 0 ;;
    404) return 2 ;;
    *)
      echo "error: fetching the published appcast $1 returned HTTP $code" >&2
      return 1
      ;;
  esac
}

# Print the build number of the Xcode project under $2 (the repository root), and
# fail unless it is higher than both the build the previous witty-v* tag before
# $1 shipped and every build the published appcast offers. When $1 is not a tag
# in the repository yet (WITTY_RELEASE_TAG may name one not created or fetched),
# the previous tag is the last witty-v* tag at or before HEAD. A comparison that
# cannot run is reported with a note, never skipped silently.
check_build_number() {
  local tag="$1" root="$2" tmp prev from="${1}^" status=0
  local args=()
  tmp="$(mktemp -d)"
  if ! git -C "$root" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    from=HEAD
  fi
  prev="$(git -C "$root" describe --tags --abbrev=0 --match 'witty-v*' "$from" 2>/dev/null || true)"
  if [ -z "$prev" ]; then
    echo "note: no witty-v* tag before $tag in $root, so there is no previous tag's build to beat" >&2
  elif git -C "$root" show "$prev:macos/Ghostty.xcodeproj/project.pbxproj" >"$tmp/previous.pbxproj" 2>/dev/null; then
    args+=(--previous-project "$tmp/previous.pbxproj" --previous-name "$prev")
  else
    echo "note: $prev has no macos/Ghostty.xcodeproj/project.pbxproj, so there is no previous tag's build to beat" >&2
  fi
  fetch_published_appcast "${WITTY_UPDATE_FEED_URL:-}" "$tmp/published.xml" || status=$?
  case "$status" in
    0) args+=(--previous-appcast "$tmp/published.xml") ;;
    2) echo "note: ${WITTY_UPDATE_FEED_URL:-} does not exist yet, so there is no published build to beat" >&2 ;;
    *)
      rm -rf "$tmp"
      return 1
      ;;
  esac
  status=0
  release_checks project "$root/macos/Ghostty.xcodeproj/project.pbxproj" ${args[@]+"${args[@]}"} || status=$?
  rm -rf "$tmp"
  return "$status"
}

# Everything a tag build ($1, repository root $2) needs before it starts: Witty's
# own feed URL and public key in the environment, the Sparkle tools matching the
# framework, and a build number Sparkle will see as new.
check_release_update_settings() {
  local tag="$1" root="$2"
  release_checks settings "${WITTY_UPDATE_FEED_URL:-}" "${WITTY_UPDATE_PUBLIC_ED_KEY:-}" || return 1
  check_sparkle_tools_version "$root/macos/Ghostty.xcodeproj/project.pbxproj" || return 1
  check_build_number "$tag" "$root" >/dev/null
}

# The release app asks before its first automatic check, as Ghostty's releases do
# (upstream .github/workflows/release-tag.yml): without SUEnableAutomaticChecks in
# the Info.plist, Sparkle asks on the second launch. The source plist keeps it false
# so development builds never check on their own. Run before signing.
prepare_release_plist() {
  local plist="$1/Contents/Info.plist"
  if /usr/libexec/PlistBuddy -c "Print :SUEnableAutomaticChecks" "$plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Delete :SUEnableAutomaticChecks" "$plist"
  fi
}

# Print the critical-update flag for release_checks.py appcast, and fail on a
# WITTY_CRITICAL_UPDATE other than unset, 0 or 1.
critical_update_flag() {
  case "${WITTY_CRITICAL_UPDATE:-0}" in
    0) echo "--not-critical" ;;
    1) echo "--critical" ;;
    *)
      echo "error: WITTY_CRITICAL_UPDATE must be 0 or 1, got '${WITTY_CRITICAL_UPDATE}'" >&2
      return 1
      ;;
  esac
}

# Write the signed appcast for release $1 (tag) to $4: one item, build $3, for the
# notarized and stapled DMG $2, downloaded from the tag's release assets. $5 is a
# scratch directory. generate_appcast signs the DMG and, because the app sets
# SURequireSignedFeed, the feed; both signatures are then verified with sign_update.
# WITTY_CRITICAL_UPDATE=1 marks the release critical (a security fix): it cannot be
# skipped, and installs no sooner than any other update.
generate_signed_appcast() {
  local tag="$1" dmg="$2" build="$3" out="$4" work="$5"
  local tools="$work/sparkle" src="$work/appcast-src" gen="$work/appcast-out/appcast.xml"
  local prefix flag signature
  local critical=()
  flag="$(critical_update_flag)" || return 1
  if [ "$flag" = "--critical" ]; then
    # An empty version: critical for every older build.
    critical=(--critical-update-version "")
  fi
  prefix="$(release_checks download-prefix "$tag")" || return 1
  fetch_sparkle_tools "$tools" || return 1

  # A fresh folder holding only this DMG, and a fresh output path: generate_appcast
  # keeps the items of an appcast it finds at the output path, and makes deltas from
  # older archives next to the new one.
  rm -rf "$src" "$(dirname "$gen")"
  mkdir -p "$src" "$(dirname "$gen")"
  cp "$dmg" "$src/"
  "$tools/bin/generate_appcast" \
    --account "$WITTY_SPARKLE_KEY_ACCOUNT" \
    --download-url-prefix "$prefix" \
    --maximum-versions 1 \
    --maximum-deltas 0 \
    ${critical[@]+"${critical[@]}"} \
    -o "$gen" \
    "$src" || return 1

  signature="$(release_checks appcast "$gen" --dmg "$dmg" --tag "$tag" --build "$build" "$flag")" || return 1
  "$tools/bin/sign_update" --account "$WITTY_SPARKLE_KEY_ACCOUNT" --verify "$gen" || return 1
  "$tools/bin/sign_update" --account "$WITTY_SPARKLE_KEY_ACCOUNT" --verify "$dmg" "$signature" || return 1
  mkdir -p "$(dirname "$out")"
  cp "$gen" "$out"
}
