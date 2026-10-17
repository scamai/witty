#!/usr/bin/env bash
# Shared signing and packaging helpers for release.sh and package_release.sh.
# Source it.

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

# Fail unless a release tag, the app being packaged and CHANGELOG.md agree:
# $1 is the tag (witty-vX.Y.Z), $2 the app's CFBundleShortVersionString, $3 the
# changelog, which needs a "## [witty-vX.Y.Z]" section. A DMG named for one
# version must not carry another, and every release has notes.
check_release_version() {
  local tag="$1" app_version="$2" changelog="$3"
  local version="${tag#witty-v}"
  if [ "$version" = "$tag" ] || ! printf '%s\n' "$version" | grep -Eqx '[0-9]+\.[0-9]+\.[0-9]+'; then
    echo "error: release tag '$tag' is not of the form witty-vX.Y.Z" >&2
    return 1
  fi
  if [ "$app_version" != "$version" ]; then
    echo "error: the tag is $tag but the app's version is '$app_version'; set MARKETING_VERSION = $version in macos/Ghostty.xcodeproj/project.pbxproj" >&2
    return 1
  fi
  if ! grep -q "^## \[${tag//./\\.}\]" "$changelog"; then
    echo "error: $changelog has no '## [$tag]' section" >&2
    return 1
  fi
}

# Print the file name to publish the DMG under: Witty-<version>-macos-<arch>.dmg,
# e.g. Witty-v0.1.4-macos-universal.dmg. $1 is the release tag (a leading
# "witty-" is dropped), $2 the architectures `lipo -archs` reports for the app.
# Release assets are always Witty-*, never the Ghostty-* names of the v0.1.x zips.
release_dmg_name() {
  local version="${1#witty-}" arm=0 intel=0 arch a
  if [ -z "$version" ]; then
    echo "error: no release tag to name the DMG after" >&2
    return 1
  fi
  # Split on purpose: lipo separates the names with spaces. A plain word list
  # also keeps bash 3.2 (/bin/bash) happy under `set -u` when it is empty.
  # shellcheck disable=SC2086
  for a in $2; do
    case "$a" in
      arm64*) arm=1 ;;
      x86_64*) intel=1 ;;
    esac
  done
  case "$arm$intel" in
    11) arch=universal ;;
    10) arch=arm64 ;;
    01) arch=x86_64 ;;
    *)
      echo "error: unexpected app architectures: '$2'" >&2
      return 1
      ;;
  esac
  echo "Witty-${version}-macos-${arch}.dmg"
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
