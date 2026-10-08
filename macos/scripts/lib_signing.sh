#!/usr/bin/env bash
# Shared signing helpers for release.sh and package_release.sh. Source it.

# Days of remaining validity below which a release warns about the signing
# certificate. Already-shipped builds keep working after expiry (they carry a
# secure timestamp), but no new release can be signed with an expired cert.
WITTY_CERT_WARN_DAYS="${WITTY_CERT_WARN_DAYS:-120}"

# Print the Developer ID Application identity to sign with:
# $1 if given, else $WITTY_SIGN_IDENTITY, else the only Developer ID
# Application identity in the keychain. Fails rather than guessing when the
# keychain holds none or several (e.g. a personal and a company team).
resolve_sign_identity() {
  local explicit="${1:-${WITTY_SIGN_IDENTITY:-}}"
  if [ -n "$explicit" ]; then
    echo "$explicit"
    return 0
  fi

  local found
  found="$(security find-identity -p codesigning -v 2>/dev/null |
    sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | sort -u)"
  local count
  count="$(printf '%s' "$found" | grep -c . || true)"

  if [ "$count" -eq 1 ]; then
    echo "$found"
    return 0
  fi
  if [ "$count" -eq 0 ]; then
    echo "error: no valid 'Developer ID Application' identity in the keychain" >&2
  else
    echo "error: $count Developer ID Application identities found; set WITTY_SIGN_IDENTITY to one of:" >&2
    printf '%s\n' "$found" | sed 's/^/  /' >&2
  fi
  return 1
}

# Fail if the identity's certificate has expired; warn if it expires within
# WITTY_CERT_WARN_DAYS. Takes the certificate as PEM on stdin so it can be
# tested without a keychain.
check_cert_validity_pem() {
  local identity="$1" pem
  pem="$(cat)"
  if [ -z "$pem" ]; then
    echo "error: no certificate found for '$identity'" >&2
    return 1
  fi
  local end
  end="$(printf '%s\n' "$pem" | openssl x509 -noout -enddate | sed 's/^notAfter=//')"
  if ! printf '%s\n' "$pem" | openssl x509 -noout -checkend 0 >/dev/null; then
    echo "error: signing certificate for '$identity' expired on $end" >&2
    return 1
  fi
  if ! printf '%s\n' "$pem" | openssl x509 -noout -checkend $((WITTY_CERT_WARN_DAYS * 86400)) >/dev/null; then
    echo "warning: signing certificate for '$identity' expires on $end (within ${WITTY_CERT_WARN_DAYS} days); request a new Developer ID certificate before then" >&2
  fi
  return 0
}

check_cert_validity() {
  security find-certificate -c "$1" -p 2>/dev/null | check_cert_validity_pem "$1"
}

# Submit a file to the notary service and fail unless Apple accepts it.
# On rejection, print the notary log, which names the offending binaries.
notarize() {
  local file="$1" profile="$2" result status id
  result="$(xcrun notarytool submit "$file" --keychain-profile "$profile" \
    --wait --output-format json)"
  status="$(printf '%s' "$result" | plutil -extract status raw -o - - 2>/dev/null || true)"
  id="$(printf '%s' "$result" | plutil -extract id raw -o - - 2>/dev/null || true)"
  echo "    notarization ${id:-?}: ${status:-unknown}"
  if [ "$status" != "Accepted" ]; then
    [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$profile" >&2 || true
    echo "error: notarization of $(basename "$file") was not accepted" >&2
    return 1
  fi
}
