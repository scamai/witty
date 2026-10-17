#!/usr/bin/env bash
# Tests for lib_signing.sh. Needs no keychain: `security` is stubbed on PATH
# and certificates are generated on the fly.
#
# Usage: macos/scripts/test_lib_signing.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILED=0

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; FAILED=1; }

# Run a lib_signing.sh function in a clean shell whose `security` prints the
# identities in $IDENTITIES (one name per line).
run_lib() {
  mkdir -p "$TMP/bin"
  cat >"$TMP/bin/security" <<'EOF'
#!/usr/bin/env bash
i=1
while IFS= read -r name; do
  [ -n "$name" ] || continue
  echo "  $i) 0000000000000000000000000000000000000000 \"$name\""
  i=$((i + 1))
done <<<"${IDENTITIES:-}"
echo "     $((i - 1)) valid identities found"
EOF
  chmod +x "$TMP/bin/security"
  PATH="$TMP/bin:$PATH" bash -c '. "$1"; shift; "$@"' _ "$SCRIPT_DIR/lib_signing.sh" "$@"
}

PERSONAL="Developer ID Application: Jane Doe (AAAAAAAAAA)"
COMPANY="Developer ID Application: Example Inc. (BBBBBBBBBB)"

# ─── resolve_sign_identity ───

out="$(IDENTITIES="$PERSONAL" run_lib resolve_sign_identity 2>/dev/null)"
[ "$out" = "$PERSONAL" ] && pass "single Developer ID identity is picked" || fail "single identity: got '$out'"

out="$(IDENTITIES="Apple Development: Jane Doe (CCCCCCCCCC)
$PERSONAL" run_lib resolve_sign_identity 2>/dev/null)"
[ "$out" = "$PERSONAL" ] && pass "non-Developer-ID identities are ignored" || fail "ignore dev identities: got '$out'"

if IDENTITIES="$PERSONAL
$COMPANY" run_lib resolve_sign_identity >/dev/null 2>"$TMP/err"; then
  fail "two Developer ID identities must not be guessed between"
else
  grep -q "Example Inc." "$TMP/err" && grep -q "Jane Doe" "$TMP/err" &&
    pass "two identities fail and list both" || fail "ambiguity error lacks the candidates: $(cat "$TMP/err")"
fi

if IDENTITIES="" run_lib resolve_sign_identity >/dev/null 2>&1; then
  fail "no identity must fail"
else
  pass "no identity fails"
fi

out="$(IDENTITIES="$PERSONAL
$COMPANY" WITTY_SIGN_IDENTITY="$COMPANY" run_lib resolve_sign_identity 2>/dev/null)"
[ "$out" = "$COMPANY" ] && pass "WITTY_SIGN_IDENTITY overrides discovery" || fail "env override: got '$out'"

out="$(IDENTITIES="" WITTY_SIGN_IDENTITY="$COMPANY" run_lib resolve_sign_identity "$PERSONAL" 2>/dev/null)"
[ "$out" = "$PERSONAL" ] && pass "explicit argument wins over env" || fail "argument override: got '$out'"

# ─── release_dmg_name ───

out="$(run_lib release_dmg_name witty-v0.1.4 "x86_64 arm64" 2>/dev/null)"
[ "$out" = "Witty-v0.1.4-macos-universal.dmg" ] && pass "fat app is named universal" || fail "universal name: got '$out'"

out="$(run_lib release_dmg_name witty-v0.1.4 "arm64" 2>/dev/null)"
[ "$out" = "Witty-v0.1.4-macos-arm64.dmg" ] && pass "arm64 app is named arm64" || fail "arm64 name: got '$out'"

out="$(run_lib release_dmg_name witty-v0.1.4 "x86_64" 2>/dev/null)"
[ "$out" = "Witty-v0.1.4-macos-x86_64.dmg" ] && pass "x86_64 app is named x86_64" || fail "x86_64 name: got '$out'"

if run_lib release_dmg_name "" "arm64" >/dev/null 2>&1; then
  fail "a missing tag must fail"
else
  pass "a missing tag fails"
fi

if run_lib release_dmg_name witty-v0.1.4 "" >/dev/null 2>&1; then
  fail "unknown architectures must fail"
else
  pass "unknown architectures fail"
fi

# ─── check_cert_validity_pem ───

make_cert() { # name days
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMP/$1.key" \
    -out "$TMP/$1.pem" -days "$2" -subj "/CN=$1" >/dev/null 2>&1
}
make_cert longlived 400
make_cert shortlived 30

if run_lib check_cert_validity_pem "x" <"$TMP/longlived.pem" 2>"$TMP/err"; then
  [ -s "$TMP/err" ] && fail "a 400-day cert must not warn: $(cat "$TMP/err")" || pass "valid cert passes quietly"
else
  fail "a 400-day cert must pass"
fi

if run_lib check_cert_validity_pem "x" <"$TMP/shortlived.pem" 2>"$TMP/err"; then
  grep -q "warning: .*expires" "$TMP/err" && pass "cert expiring within 120 days warns" ||
    fail "30-day cert did not warn"
else
  fail "a cert that is still valid must not fail the release"
fi

if run_lib check_cert_validity_pem "x" </dev/null 2>/dev/null; then
  fail "missing certificate must fail"
else
  pass "missing certificate fails"
fi

# An already-expired cert needs -not_before/-not_after (OpenSSL >= 3.4; the
# LibreSSL in /usr/bin lacks them). Report the gap instead of passing silently.
if openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMP/expired.key" \
  -out "$TMP/expired.pem" -not_before 20200101000000Z -not_after 20200201000000Z \
  -subj "/CN=expired" >/dev/null 2>&1; then
  if run_lib check_cert_validity_pem "x" <"$TMP/expired.pem" 2>"$TMP/err"; then
    fail "an expired cert must fail"
  else
    grep -q "expired on" "$TMP/err" && pass "expired cert fails" || fail "expired cert: wrong message: $(cat "$TMP/err")"
  fi
else
  echo "SKIP - expired-cert case: $(openssl version) cannot backdate certificates"
  FAILED=1
fi

exit "$FAILED"
