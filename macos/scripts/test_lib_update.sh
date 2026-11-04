#!/usr/bin/env bash
# Tests for lib_update.sh, and for release.sh's use of it at a tag. Needs no keychain,
# network, Zig or macOS: curl, security, zig, package_release.sh and the Sparkle tools
# are stubbed, openssl makes the test certificate, and the rules come from
# release_checks.py, which test_release_checks.py covers on its own.
#
# Usage: macos/scripts/test_lib_update.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT="$REPO_ROOT/macos/Ghostty.xcodeproj/project.pbxproj"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILED=0
export PYTHONDONTWRITEBYTECODE=1

pass() { echo "ok   - $1"; }
fail() {
  echo "FAIL - $1"
  FAILED=1
}

FEED="https://github.com/scamai/witty/releases/latest/download/appcast.xml"
KEY="$(python3 -c 'import base64; print(base64.b64encode(bytes(range(32))).decode())')"
SIG="$(python3 -c 'import base64; print(base64.b64encode(bytes(64)).decode())')"
GHOSTTY_KEY="wsNcGf5hirwtdXMVnYoxRIX/SqZQLMOsYlD3q3imeok="

# Run a lib_update.sh function in a clean shell, with $TMP/bin first on PATH.
run_lib() {
  mkdir -p "$TMP/bin"
  PATH="$TMP/bin:$PATH" bash -c '. "$1"; . "$2"; shift 2; "$@"' _ \
    "$SCRIPT_DIR/lib_signing.sh" "$SCRIPT_DIR/lib_update.sh" "$@"
}

# A curl that answers every request with HTTP $STUB_CODE and the body $STUB_BODY,
# and records its arguments; STUB_CURL_FAIL=1 makes it fail like a network error.
cat >"$TMP/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
[ "${STUB_CURL_FAIL:-0}" = 1 ] && exit 6
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift ;;
  esac
  shift
done
[ -n "$out" ] && printf '%s' "${STUB_BODY:-}" >"$out"
printf '%s' "${STUB_CODE:-200}"
EOF
chmod +x "$TMP/curl"
use_stub_curl() { mkdir -p "$TMP/bin" && cp "$TMP/curl" "$TMP/bin/curl"; }
drop_stub_curl() { rm -f "$TMP/bin/curl"; }
export STUB_LOG="$TMP/curl.log"

# ─── fetch_sparkle_tools_from ───

mkdir -p "$TMP/tarsrc/bin"
printf '#!/bin/sh\necho generate\n' >"$TMP/tarsrc/bin/generate_appcast"
printf '#!/bin/sh\necho sign\n' >"$TMP/tarsrc/bin/sign_update"
printf '#!/bin/sh\necho keys\n' >"$TMP/tarsrc/bin/generate_keys"
chmod +x "$TMP/tarsrc/bin/"*
(cd "$TMP/tarsrc" && tar -cJf "$TMP/tools.tar.xz" ./bin)
GOOD_SHA="$(run_lib sha256_of "$TMP/tools.tar.xz")"

if run_lib fetch_sparkle_tools_from "file://$TMP/tools.tar.xz" "$GOOD_SHA" "$TMP/good" 2>"$TMP/err" &&
  [ -x "$TMP/good/bin/generate_appcast" ] && [ -x "$TMP/good/bin/sign_update" ]; then
  pass "tools with the pinned SHA-256 are unpacked"
else
  fail "pinned tools: $(cat "$TMP/err")"
fi
[ ! -e "$TMP/good/bin/generate_keys" ] && pass "generate_keys is not unpacked" || fail "generate_keys was unpacked"

# The tarball's mtimes, and so its hash, change on every run: swap the last character
# for one it is not, so the bad hash never equals the good one.
if [ "${GOOD_SHA: -1}" = 0 ]; then BAD_SHA="${GOOD_SHA%?}1"; else BAD_SHA="${GOOD_SHA%?}0"; fi
[ "$BAD_SHA" != "$GOOD_SHA" ] || fail "the bad SHA-256 equals the good one"
if run_lib fetch_sparkle_tools_from "file://$TMP/tools.tar.xz" "$BAD_SHA" "$TMP/bad" 2>"$TMP/err"; then
  fail "tools with another SHA-256 must be refused"
else
  if grep -q "expected" "$TMP/err" && [ ! -e "$TMP/bad/bin/generate_appcast" ]; then
    pass "tools with another SHA-256 are refused and not unpacked"
  else
    fail "wrong hash: $(cat "$TMP/err"); $(ls "$TMP/bad" 2>&1)"
  fi
fi

if run_lib fetch_sparkle_tools_from "file://$TMP/missing.tar.xz" "$GOOD_SHA" "$TMP/none" 2>/dev/null; then
  fail "a failed download must fail"
else
  pass "a failed download fails"
fi

# ─── check_sparkle_tools_version ───

if run_lib check_sparkle_tools_version "$PROJECT" 2>"$TMP/err"; then
  pass "the Xcode project pins the Sparkle the tools come from"
else
  fail "Sparkle version: $(cat "$TMP/err")"
fi
sed 's/version = 2\.9\.6;/version = 2.9.7;/' "$PROJECT" >"$TMP/sparkle-bumped.pbxproj"
if run_lib check_sparkle_tools_version "$TMP/sparkle-bumped.pbxproj" 2>"$TMP/err"; then
  fail "a Sparkle bump without new tools must fail"
else
  grep -q "update SPARKLE_VERSION" "$TMP/err" && pass "a Sparkle bump without new tools fails" ||
    fail "Sparkle bump: wrong message: $(cat "$TMP/err")"
fi

# ─── fetch_published_appcast ───

use_stub_curl
for case in "200 0" "404 2" "500 1"; do
  set -- $case
  STUB_CODE="$1" run_lib fetch_published_appcast "$FEED" "$TMP/published.xml" 2>/dev/null
  got=$?
  [ "$got" = "$2" ] && pass "HTTP $1 returns $2" || fail "HTTP $1 returned $got, expected $2"
done
STUB_CURL_FAIL=1 run_lib fetch_published_appcast "$FEED" "$TMP/published.xml" 2>/dev/null
[ $? = 1 ] && pass "a network error returns 1" || fail "a network error must return 1"
grep -q -- "--proto =https" "$STUB_LOG" && ! grep -E -q -- ' -b | -c |--cookie' "$STUB_LOG" &&
  pass "the published appcast is fetched over https only, without cookies" ||
  fail "fetch flags: $(cat "$STUB_LOG")"
drop_stub_curl

# ─── check_build_number and check_release_update_settings ───

# A repository with the real project at witty-v0.2.1 and a next commit at witty-v0.3.0.
make_repo() {
  local repo="$1" bump="$2"
  rm -rf "$repo"
  mkdir -p "$repo/macos/Ghostty.xcodeproj"
  cp "$PROJECT" "$repo/macos/Ghostty.xcodeproj/project.pbxproj"
  git -C "$repo" init -q
  git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m base
  git -C "$repo" add -A
  git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q -m "0.2.1"
  git -C "$repo" -c user.name=t -c user.email=t@example.com tag -a witty-v0.2.1 -m 0.2.1
  if [ "$bump" = 1 ]; then
    python3 "$SCRIPT_DIR/release_checks.py" bump "$repo/macos/Ghostty.xcodeproj/project.pbxproj" 0.3.0 >/dev/null
  fi
  git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -am "0.3.0"
  git -C "$repo" -c user.name=t -c user.email=t@example.com tag -a witty-v0.3.0 -m 0.3.0
}
BUILD="$(python3 "$SCRIPT_DIR/release_checks.py" project "$PROJECT")"
NEXT=$((BUILD + 1))
appcast_offering() {
  printf '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel><item><sparkle:version>%s</sparkle:version><enclosure url="x" length="1"/></item></channel></rss>' "$1"
}

use_stub_curl
make_repo "$TMP/repo-bumped" 1
out="$(STUB_CODE=404 WITTY_UPDATE_FEED_URL="$FEED" run_lib check_build_number witty-v0.3.0 "$TMP/repo-bumped" 2>"$TMP/err")"
[ "$out" = "$NEXT" ] && grep -q "does not exist yet" "$TMP/err" &&
  pass "a raised build passes before any appcast exists, and says so" || fail "raised build: '$out' $(cat "$TMP/err")"

if STUB_CODE=200 STUB_BODY="$(appcast_offering "$NEXT")" WITTY_UPDATE_FEED_URL="$FEED" \
  run_lib check_build_number witty-v0.3.0 "$TMP/repo-bumped" >/dev/null 2>"$TMP/err"; then
  fail "a build the published appcast already offers must fail"
else
  grep -q "already offers build $NEXT" "$TMP/err" && pass "a build the published appcast offers fails" ||
    fail "published build: wrong message: $(cat "$TMP/err")"
fi

make_repo "$TMP/repo-same" 0
if STUB_CODE=404 WITTY_UPDATE_FEED_URL="$FEED" run_lib check_build_number witty-v0.3.0 "$TMP/repo-same" >/dev/null 2>"$TMP/err"; then
  fail "the previous tag's build number must fail"
else
  grep -q "witty-v0.2.1 shipped build $BUILD" "$TMP/err" && pass "the previous tag's build number fails and names the tag" ||
    fail "same build: wrong message: $(cat "$TMP/err")"
fi

# WITTY_RELEASE_TAG may name a tag not created or fetched yet; the previous tag is
# then the last one at or before HEAD, so the comparison still runs.
make_repo "$TMP/repo-same-untagged" 0
git -C "$TMP/repo-same-untagged" tag -d witty-v0.3.0 >/dev/null
if STUB_CODE=404 WITTY_UPDATE_FEED_URL="$FEED" \
  run_lib check_build_number witty-v0.3.0 "$TMP/repo-same-untagged" >/dev/null 2>"$TMP/err"; then
  fail "a release tag missing from the repository must not skip the previous tag's build number"
else
  grep -q "witty-v0.2.1 shipped build $BUILD" "$TMP/err" &&
    pass "with the release tag not in the repository, the previous tag's build number still fails" ||
    fail "missing tag, same build: wrong message: $(cat "$TMP/err")"
fi
make_repo "$TMP/repo-bumped-untagged" 1
git -C "$TMP/repo-bumped-untagged" tag -d witty-v0.3.0 >/dev/null
out="$(STUB_CODE=404 WITTY_UPDATE_FEED_URL="$FEED" \
  run_lib check_build_number witty-v0.3.0 "$TMP/repo-bumped-untagged" 2>"$TMP/err")"
[ "$out" = "$NEXT" ] && pass "with the release tag not in the repository, a raised build passes" ||
  fail "missing tag, raised build: '$out' $(cat "$TMP/err")"
git -C "$TMP/repo-same-untagged" tag -d witty-v0.2.1 >/dev/null
out="$(STUB_CODE=404 WITTY_UPDATE_FEED_URL="$FEED" \
  run_lib check_build_number witty-v0.3.0 "$TMP/repo-same-untagged" 2>"$TMP/err")"
[ "$out" = "$BUILD" ] && grep -q "no witty-v\* tag before witty-v0.3.0" "$TMP/err" &&
  pass "with no previous witty-v* tag the comparison is skipped, and says so" ||
  fail "no previous tag: '$out' $(cat "$TMP/err")"

if STUB_CURL_FAIL=1 WITTY_UPDATE_FEED_URL="$FEED" run_lib check_build_number witty-v0.3.0 "$TMP/repo-bumped" >/dev/null 2>&1; then
  fail "an unreachable feed must fail the build-number check, not skip it"
else
  pass "an unreachable feed fails the build-number check"
fi

for settings in "|" "$FEED|" "|$KEY" "$FEED|$GHOSTTY_KEY" "https://release.files.ghostty.org/appcast.xml|$KEY" \
  "https://github.com/scamai/witty/releases/download/witty-v0.2.1/appcast.xml|$KEY" \
  "https://github.com/scamai/witty/raw/main/appcast.xml|$KEY"; do
  if STUB_CODE=404 WITTY_UPDATE_FEED_URL="${settings%%|*}" WITTY_UPDATE_PUBLIC_ED_KEY="${settings#*|}" \
    run_lib check_release_update_settings witty-v0.3.0 "$TMP/repo-bumped" >/dev/null 2>&1; then
    fail "tag build with feed '${settings%%|*}' and key '${settings#*|}' must fail"
  else
    pass "tag build with feed '${settings%%|*}' and key '${settings#*|}' fails"
  fi
done
if STUB_CODE=404 WITTY_UPDATE_FEED_URL="$FEED" WITTY_UPDATE_PUBLIC_ED_KEY="$KEY" \
  run_lib check_release_update_settings witty-v0.3.0 "$TMP/repo-bumped" 2>"$TMP/err"; then
  pass "tag build with Witty's feed, key and a raised build passes"
else
  fail "good tag build: $(cat "$TMP/err")"
fi
drop_stub_curl

# ─── release.sh ───

# The cases above call check_release_update_settings themselves; these run release.sh,
# so they fail if release.sh stops calling it. The repository is make_repo's with the
# scripts and build.zig.zon in its working tree. Stubs: `security` knows one Developer
# ID identity whose certificate is valid for 400 days, curl answers 404 (no published
# appcast yet), ZIG prints the minimum version and records a build, and
# package_release.sh records that it ran.
RELEASE_REPO="$TMP/release-repo"
MARKERS="$TMP/markers"
make_repo "$RELEASE_REPO" 1
cp -R "$SCRIPT_DIR" "$RELEASE_REPO/macos/scripts"
cp "$REPO_ROOT/build.zig.zon" "$RELEASE_REPO/build.zig.zon"
cat >"$RELEASE_REPO/macos/scripts/package_release.sh" <<'EOF'
#!/usr/bin/env bash
touch "$STUB_MARKERS/package"
EOF

mkdir -p "$TMP/release-bin"
cp "$TMP/curl" "$TMP/release-bin/curl"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMP/release.key" -out "$TMP/release.pem" \
  -days 400 -subj "/CN=Witty test" >/dev/null 2>&1 || fail "openssl cannot make the test certificate"
cat >"$TMP/release-bin/security" <<EOF
#!/usr/bin/env bash
case "\$1" in
  find-identity)
    echo '  1) 0000000000000000000000000000000000000000 "Developer ID Application: Example Inc. (BBBBBBBBBB)"'
    echo '     1 valid identities found'
    ;;
  find-certificate) cat "$TMP/release.pem" ;;
  *) exit 1 ;;
esac
EOF
ZIG_MIN="$(grep -oE 'minimum_zig_version = "[0-9.]+"' "$REPO_ROOT/build.zig.zon" | grep -oE '[0-9.]+' | head -1)"
cat >"$TMP/stub-zig" <<EOF
#!/usr/bin/env bash
case "\$1" in
  version) echo "$ZIG_MIN" ;;
  build) touch "\$STUB_MARKERS/build" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$RELEASE_REPO/macos/scripts/package_release.sh" "$TMP/release-bin/"* "$TMP/stub-zig"

# Run the release repository's release.sh with feed $1 and key $2, and nothing else
# from this shell's release settings. Its output goes to $TMP/release.out, and
# $MARKERS says how far it got.
run_release() {
  rm -rf "$MARKERS" && mkdir -p "$MARKERS"
  PATH="$TMP/release-bin:$PATH" ZIG="$TMP/stub-zig" STUB_MARKERS="$MARKERS" STUB_CODE=404 \
    WITTY_RELEASE_TAG='' WITTY_SIGN_IDENTITY='' \
    WITTY_UPDATE_FEED_URL="$1" WITTY_UPDATE_PUBLIC_ED_KEY="$2" \
    "$RELEASE_REPO/macos/scripts/release.sh" >"$TMP/release.out" 2>&1
}

# Run release.sh with feed $1 and key $2 at the tag at HEAD, and pass if it stops
# before building with an error containing $3. $4 names the case.
release_case() {
  local feed="$1" key="$2" error="$3" what="$4" tag
  tag="$(git -C "$RELEASE_REPO" describe --exact-match --tags 2>/dev/null)"
  if run_release "$feed" "$key"; then
    fail "release.sh at $tag with $what must fail"
  elif [ -e "$MARKERS/build" ]; then
    fail "release.sh at $tag with $what fails, but only after building"
  elif ! grep -qF -- "$error" "$TMP/release.out"; then
    fail "release.sh at $tag with $what fails without '$error': $(cat "$TMP/release.out")"
  else
    pass "release.sh at $tag with $what fails before building"
  fi
}

release_case "" "" "WITTY_UPDATE_FEED_URL is not set" "no updater settings"
release_case "$FEED" "$GHOSTTY_KEY" "is Ghostty's EdDSA public key" "Ghostty's key"
release_case "https://release.files.ghostty.org/appcast.xml" "$KEY" \
  "must start with https://github.com/scamai/witty/" "a feed outside scamai/witty"

if run_release "$FEED" "$KEY" && [ -e "$MARKERS/build" ] && [ -e "$MARKERS/package" ]; then
  pass "release.sh at witty-v0.3.0 with Witty's feed, key and a raised build builds and packages"
else
  fail "release.sh with good settings: $(cat "$TMP/release.out")"
fi

# A later tag whose build number was not raised.
git -C "$RELEASE_REPO" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m "0.3.1"
git -C "$RELEASE_REPO" -c user.name=t -c user.email=t@example.com tag -a witty-v0.3.1 -m 0.3.1
release_case "$FEED" "$KEY" "witty-v0.3.0 shipped build $NEXT" "a build number not raised since witty-v0.3.0"

# ─── critical_update_flag ───

[ "$(run_lib critical_update_flag)" = "--not-critical" ] && pass "releases are not critical by default" || fail "default criticality"
[ "$(WITTY_CRITICAL_UPDATE=1 run_lib critical_update_flag)" = "--critical" ] && pass "WITTY_CRITICAL_UPDATE=1 is critical" || fail "critical flag"
if WITTY_CRITICAL_UPDATE=yes run_lib critical_update_flag >/dev/null 2>&1; then
  fail "WITTY_CRITICAL_UPDATE=yes must fail"
else
  pass "WITTY_CRITICAL_UPDATE other than 0 or 1 fails"
fi

# ─── generate_signed_appcast ───

# Stub tools. generate_appcast writes an appcast for the one DMG in its source
# folder (STUB_ITEMS copies of the item) and records its arguments and that folder;
# sign_update records its arguments and fails when STUB_VERIFY_FAIL=1.
mkdir -p "$TMP/stubtools/bin"
cat >"$TMP/stubtools/bin/generate_appcast" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$TMP/generate.args"
out="" prefix="" critical=""
while [ \$# -gt 1 ]; do
  case "\$1" in
    -o) out="\$2"; shift ;;
    --download-url-prefix) prefix="\$2"; shift ;;
    --critical-update-version) critical="<sparkle:criticalUpdate></sparkle:criticalUpdate>"; shift ;;
  esac
  shift
done
src="\$1"
ls -A "\$src" >"$TMP/generate.src"
[ -e "\$out" ] && echo stale >"$TMP/generate.stale"
dmg="\$(ls "\$src")"
size="\$(wc -c <"\$src/\$dmg" | tr -d ' ')"
item="<item><sparkle:version>\${STUB_BUILD}</sparkle:version><sparkle:shortVersionString>0.3.0</sparkle:shortVersionString>\$critical<enclosure url=\"\$prefix\$dmg\" length=\"\$size\" type=\"application/octet-stream\" sparkle:edSignature=\"$SIG\"/></item>"
body="<rss xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\" version=\"2.0\"><channel>"
for _ in \$(seq "\${STUB_ITEMS:-1}"); do body="\$body\$item"; done
body="\$body</channel></rss>"
printf '%s\n<!-- sparkle-signatures:\nedSignature: %s\nlength: 1\n-->\n' "\$body" "$SIG" >"\$out"
EOF
cat >"$TMP/stubtools/bin/sign_update" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMP/sign.log"
[ "\${STUB_VERIFY_FAIL:-0}" = 1 ] && exit 1
exit 0
EOF
chmod +x "$TMP/stubtools/bin/"*

DMG_FILE="$TMP/dist/Witty-v0.3.0-macos-universal.dmg"
mkdir -p "$TMP/dist"
printf 'not really a dmg' >"$DMG_FILE"
cp "$DMG_FILE" "$TMP/dist/Witty-v0.2.1-macos-universal.dmg" # an older DMG nearby

# Run generate_signed_appcast with the stub tools in place of the download.
gen() {
  rm -f "$TMP/generate.args" "$TMP/generate.src" "$TMP/generate.stale" "$TMP/sign.log" "$TMP/dist/appcast.xml"
  rm -rf "$TMP/work"
  mkdir -p "$TMP/work"
  STUB_TOOLS="$TMP/stubtools" PATH="$TMP/bin:$PATH" STUB_BUILD="${STUB_BUILD:-$NEXT}" bash -c '
    . "$1"; . "$2"
    fetch_sparkle_tools() { mkdir -p "$1" && cp -R "$STUB_TOOLS/bin" "$1/"; }
    generate_signed_appcast witty-v0.3.0 "$3" "$4" "$5" "$6"' _ \
    "$SCRIPT_DIR/lib_signing.sh" "$SCRIPT_DIR/lib_update.sh" \
    "$DMG_FILE" "$NEXT" "$TMP/dist/appcast.xml" "$TMP/work"
}

if gen 2>"$TMP/err" && [ -f "$TMP/dist/appcast.xml" ]; then
  pass "a signed appcast is written for the DMG"
else
  fail "generate: $(cat "$TMP/err")"
fi
args="$(tr '\n' ' ' <"$TMP/generate.args" 2>/dev/null)"
case "$args" in
  *"--account witty "*"--download-url-prefix https://github.com/scamai/witty/releases/download/witty-v0.3.0/ "*"--maximum-versions 1 --maximum-deltas 0 "*)
    pass "generate_appcast gets Witty's key account, the tag's download prefix, one version and no deltas" ;;
  *) fail "generate_appcast arguments: $args" ;;
esac
case "$args" in
  *--critical-update-version*) fail "a release is critical only when asked: $args" ;;
  *) pass "a release is not marked critical by default" ;;
esac
[ "$(cat "$TMP/generate.src" 2>/dev/null)" = "$(basename "$DMG_FILE")" ] &&
  pass "generate_appcast sees only this DMG, so it makes no deltas or old items" ||
  fail "source folder: $(cat "$TMP/generate.src" 2>/dev/null)"
[ ! -e "$TMP/generate.stale" ] && pass "generate_appcast starts from no appcast" || fail "an appcast was at the output path"
if [ "$(grep -c -- '--verify' "$TMP/sign.log" 2>/dev/null)" = 2 ] &&
  grep -q -- "--verify $TMP/work/appcast-out/appcast.xml" "$TMP/sign.log" &&
  grep -q -- "--verify $DMG_FILE $SIG" "$TMP/sign.log"; then
  pass "sign_update verifies the feed's and the DMG's signatures"
else
  fail "sign_update calls: $(cat "$TMP/sign.log" 2>/dev/null)"
fi

if (export WITTY_CRITICAL_UPDATE=1; gen) 2>"$TMP/err"; then
  grep -q -- "--critical-update-version" "$TMP/generate.args" &&
    pass "WITTY_CRITICAL_UPDATE=1 marks the release critical for every older build" ||
    fail "critical arguments: $(cat "$TMP/generate.args")"
else
  fail "critical release: $(cat "$TMP/err")"
fi

for failure in "STUB_ITEMS=2|two releases in the appcast" "STUB_BUILD=1|another build number" \
  "STUB_VERIFY_FAIL=1|a signature sign_update rejects" "WITTY_CRITICAL_UPDATE=2|a bad WITTY_CRITICAL_UPDATE"; do
  if (export "${failure%%|*}"; gen) >/dev/null 2>&1; then
    fail "${failure#*|} must fail"
  elif [ -e "$TMP/dist/appcast.xml" ]; then
    fail "${failure#*|} fails but leaves dist/appcast.xml behind"
  else
    pass "${failure#*|} fails and writes no appcast"
  fi
done

# ─── prepare_release_plist ───

if [ -x /usr/libexec/PlistBuddy ]; then
  mkdir -p "$TMP/Witty.app/Contents"
  cp "$REPO_ROOT/macos/Ghostty-Info.plist" "$TMP/Witty.app/Contents/Info.plist"
  run_lib prepare_release_plist "$TMP/Witty.app" && run_lib prepare_release_plist "$TMP/Witty.app"
  if ! /usr/libexec/PlistBuddy -c "Print :SUEnableAutomaticChecks" "$TMP/Witty.app/Contents/Info.plist" >/dev/null 2>&1 &&
    /usr/libexec/PlistBuddy -c "Print :SURequireSignedFeed" "$TMP/Witty.app/Contents/Info.plist" >/dev/null 2>&1; then
    pass "the release plist loses SUEnableAutomaticChecks only, and a second run is harmless"
  else
    fail "prepare_release_plist"
  fi
else
  echo "SKIP - prepare_release_plist: needs /usr/libexec/PlistBuddy, which only macOS has"
fi

exit "$FAILED"
