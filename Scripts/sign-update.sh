#!/bin/bash
# Signs an update archive with Sparkle's EdDSA update signature and prints
# the two values the update feed needs: the edSignature and the length.
#
# The exact archive passed in is the one signed; the release pipeline
# publishes that same file and only that file. Never sign one artifact and
# publish another.
#
# Usage: sh Scripts/sign-update.sh <archive> [private-key-file]
#   <archive>            the DMG (or zip) to sign
#   [private-key-file]   PEM private key. When omitted, Sparkle reads the
#                        private key from the macOS login Keychain, which is
#                        where generate_keys stores it.
#
# Prints: ed_signature=<base64>  and  length=<bytes>
set -euo pipefail

ARCHIVE="${1:?archive required}"
KEY_FILE="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SIGN_UPDATE="$(find "${ROOT}/App/.build/artifacts" -iname sign_update -path '*bin*' 2>/dev/null | head -1)"
if [[ -z "${SIGN_UPDATE}" ]]; then
  echo "error: sign_update not found. Fetch Sparkle's tools first:" >&2
  echo "  cd App && swift package resolve" >&2
  exit 1
fi

if [[ -n "${KEY_FILE}" ]]; then
  [[ -f "${KEY_FILE}" ]] || { echo "error: private key file ${KEY_FILE} not found" >&2; exit 1; }
  # Sparkle's sign_update reads the private key as base64 of the raw
  # 32-byte Ed25519 seed, not as a PEM (its decode step is a plain
  # base64 decode, so a PEM makes it fail with no output). Convert PEM
  # to the seed format here; a bare base64 seed passes through unchanged.
  if grep -q -- '-----BEGIN' "${KEY_FILE}" 2>/dev/null; then
    SEED_FILE="$(mktemp "${TMPDIR:-/tmp}/sparkle-seed.XXXXXX" 2>/dev/null || mktemp)"
    trap 'rm -f "${SEED_FILE}"' EXIT
    OPENSSL="$(brew --prefix openssl@3 2>/dev/null)/bin/openssl"
    [[ -x "${OPENSSL}" ]] || OPENSSL="$(command -v openssl || true)"
    if [[ -z "${OPENSSL}" ]]; then
      echo "error: openssl not found; cannot convert the PEM private key." >&2
      exit 1
    fi
    if ! "${OPENSSL}" pkey -in "${KEY_FILE}" -outform DER 2>/dev/null \
        | tail -c 32 | base64 | tr -d '\n' > "${SEED_FILE}"; then
      echo "error: could not convert the PEM private key to Sparkle's seed format." >&2
      echo "  The signing machine needs a full OpenSSL 3 (brew install openssl@3);" >&2
      echo "  macOS's bundled LibreSSL cannot parse Ed25519 PEMs." >&2
      exit 1
    fi
    if [[ ! -s "${SEED_FILE}" ]]; then
      echo "error: the PEM private key did not decode to a 32-byte Ed25519 seed." >&2
      exit 1
    fi
    KEY_FILE="${SEED_FILE}"
  fi
  OUTPUT="$("${SIGN_UPDATE}" -f "${KEY_FILE}" "${ARCHIVE}")"
else
  OUTPUT="$("${SIGN_UPDATE}" "${ARCHIVE}")"
fi

ED_SIGNATURE="$(echo "${OUTPUT}" | grep -oE 'sparkle:edSignature="[^"]+"' | head -1 | cut -d'"' -f2)"
LENGTH="$(echo "${OUTPUT}" | grep -oE 'length="[^"]+"' | head -1 | cut -d'"' -f2)"

if [[ -z "${ED_SIGNATURE}" || -z "${LENGTH}" ]]; then
  echo "error: sign_update produced no signature: ${OUTPUT}" >&2
  exit 1
fi

echo "ed_signature=${ED_SIGNATURE}"
echo "length=${LENGTH}"
