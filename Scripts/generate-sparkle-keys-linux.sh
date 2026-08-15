#!/bin/bash
# Generates the Sparkle EdDSA signing keypair for OriginCheck updates
# without a Mac. Sparkle's own generate_keys tool is a macOS binary, but
# the key itself is standard Ed25519: a PKCS#8 PEM private key and the
# base64 of the raw 32-byte public key, which is exactly what Sparkle's
# sign_update -f and SUPublicEDKey expect.
#
# Requirements: openssl 3.x. Verify the tool with:
#   openssl version
#
# What this script does:
#   1. Refuses to run if Sparkle/private-key.pem already exists. That file
#      means a key was already generated and its private half is already in
#      the SPARKLE_PRIVATE_KEY secret; generating a second pair would break
#      every release that used the first one. Rotate deliberately instead:
#      delete the file, re-run, replace the committed public key, and set
#      the new private key as the secret.
#   2. Generates an Ed25519 keypair into Sparkle/private-key.pem
#      (gitignored, chmod 600). The private key is never printed.
#   3. Prints the public key and the exact remaining steps: set the secret
#      and commit the public key.
#
# Usage: sh Scripts/generate-sparkle-keys-linux.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY_FILE="${ROOT}/Sparkle/private-key.pem"

if ! openssl version | grep -q "OpenSSL 3"; then
  echo "error: openssl 3.x is required (found: $(openssl version))." >&2
  exit 1
fi

if [[ -f "${KEY_FILE}" ]]; then
  echo "error: ${KEY_FILE} already exists. A keypair is already generated." >&2
  echo "  If the SPARKLE_PRIVATE_KEY secret is set, you are done here." >&2
  echo "  To rotate: delete the file, re-run this script, commit the new" >&2
  echo "  public key, and replace the secret with the new private key." >&2
  exit 1
fi

mkdir -p "$(dirname "${KEY_FILE}")"
umask 077
openssl genpkey -algorithm ED25519 -out "${KEY_FILE}"
chmod 600 "${KEY_FILE}"

# Sanity: the keypair must sign and verify, or nothing downstream works.
MESSAGE="$(mktemp)"
SIG="$(mktemp)"
PUB="$(mktemp)"
trap 'rm -f "${MESSAGE}" "${SIG}" "${PUB}"' EXIT
printf 'origincheck key check' > "${MESSAGE}"
openssl pkey -in "${KEY_FILE}" -pubout -out "${PUB}"
openssl pkeyutl -sign -inkey "${KEY_FILE}" -rawin -in "${MESSAGE}" -out "${SIG}"
if ! openssl pkeyutl -verify -pubin -inkey "${PUB}" -rawin -in "${MESSAGE}" -sigfile "${SIG}" 2>/dev/null; then
  rm -f "${KEY_FILE}"
  echo "error: the generated keypair failed its sign/verify check. Removed it." >&2
  exit 1
fi

PUBLIC_KEY="$(openssl pkey -in "${KEY_FILE}" -pubout -outform DER | tail -c 32 | base64 | tr -d '\n')"

echo "Generated ${KEY_FILE}"
echo
echo "PUBLIC key (commit this in Sparkle/public-key.txt, replacing the placeholder):"
echo "  ${PUBLIC_KEY}"
echo
cat <<NOTES
The PRIVATE key lives at ${KEY_FILE}. It is gitignored and must never be
committed.

Remaining steps:
1. Copy the contents of ${KEY_FILE} into the repository secret
   SPARKLE_PRIVATE_KEY at Settings > Secrets and variables > Actions.
   (gh secret set requires admin access; without it, paste in the UI.)
2. Commit the public key above into Sparkle/public-key.txt.
3. Keep the private key somewhere safe (a password manager) in case the
   secret is ever lost. If it is lost, rotate with the steps above.

Anyone holding the private key can sign updates that OriginCheck will
install. Treat it like a password.
NOTES
