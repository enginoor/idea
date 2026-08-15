#!/bin/bash
# Generates (or reads) the Sparkle EdDSA signing keypair for OriginCheck
# updates. Run once, on a Mac. Sparkle's tools are macOS binaries.
#
# What it does:
#   1. Runs Sparkle's generate_keys. The PRIVATE key is saved to your login
#      Keychain; it is never written into this repository.
#   2. Writes the PUBLIC key to Sparkle/public-key.txt, which is committed.
#      The public key is not secret.
#   3. Prints the exact steps to give the PRIVATE key to CI so GitHub
#      Actions can sign releases, and how to move the key to another Mac.
#
# Usage: sh Scripts/generate-sparkle-keys.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

GENERATE_KEYS="$(find "${ROOT}/App/.build/artifacts" -iname generate_keys -path '*bin*' 2>/dev/null | head -1)"
if [[ -z "${GENERATE_KEYS}" ]]; then
  echo "error: generate_keys not found. Fetch Sparkle's tools first:" >&2
  echo "  cd App && swift package resolve" >&2
  exit 1
fi

echo "Reading the Sparkle key from your login Keychain (generate_keys creates it if missing)."
PUBLIC_KEY="$("${GENERATE_KEYS}")"
if [[ -z "${PUBLIC_KEY}" ]]; then
  echo "error: generate_keys produced no public key." >&2
  exit 1
fi

KEY_FILE="${ROOT}/Sparkle/public-key.txt"
mkdir -p "$(dirname "${KEY_FILE}")"

CURRENT=""
if [[ -f "${KEY_FILE}" ]]; then
  CURRENT="$(tr -d '[:space:]' < "${KEY_FILE}")"
fi

if [[ "${CURRENT}" == "${PUBLIC_KEY}" ]]; then
  echo "Sparkle/public-key.txt is already up to date."
elif [[ -z "${CURRENT}" || "${CURRENT}" == *"REPLACE"* ]]; then
  printf '%s\n' "${PUBLIC_KEY}" > "${KEY_FILE}"
  echo "Wrote the public key to ${KEY_FILE}. Commit this file."
else
  echo "warning: the Keychain key differs from Sparkle/public-key.txt." >&2
  echo "  Keychain:    ${PUBLIC_KEY}" >&2
  echo "  Repository:  ${CURRENT}" >&2
  echo "  Update the committed file only if you intend to rotate the key." >&2
fi

cat <<NOTES

Sparkle key is ready.

PUBLIC key (this is committed and not secret):
  ${PUBLIC_KEY}

The PRIVATE key lives in your login Keychain under "Sparkle Private Key".

For GitHub Actions to sign releases, export the private key and store it as
the SPARKLE_PRIVATE_KEY secret in the repository's Actions secrets:

  security find-generic-password -s "Sparkle Private Key" -w \\
    > /tmp/sparkle-private-key.pem
  # then paste the contents of /tmp/sparkle-private-key.pem into
  #   https://github.com/enginoor/idea/settings/secrets/actions
  rm /tmp/sparkle-private-key.pem

To move the key to another Mac (e.g. to sign from a local release):

  generate_keys -x /tmp/sparkle-export.pem   # export from this Keychain
  generate_keys -f /tmp/sparkle-export.pem   # import on the other Mac

Keep the private key safe. Anyone holding it can sign updates that
OriginCheck will install.
NOTES
