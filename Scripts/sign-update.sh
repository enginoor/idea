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
