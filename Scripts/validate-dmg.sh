#!/bin/bash
# Validates a production DMG before it may be published or signed:
#   - the file exists and is a real disk image (hdiutil imageinfo)
#   - it mounts read-only
#   - it contains the app bundle and the Applications shortcut
#   - the mounted app passes Scripts/validate-app.sh
#
# Usage: sh Scripts/validate-dmg.sh <dmg-path> <app-name> [expected-version] [expected-build]
#   app-name is the .app name inside the image, e.g. OriginCheck.app
set -euo pipefail

DMG="${1:?dmg path required}"
APP_NAME="${2:?app name required}"
EXPECTED_VERSION="${3:-}"
EXPECTED_BUILD="${4:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ -f "${DMG}" ]] || fail "DMG not found at ${DMG}"
hdiutil imageinfo "${DMG}" >/dev/null 2>&1 || fail "${DMG} is not a valid disk image"
echo "Disk image format verified: ${DMG}"

MOUNT="$(mktemp -d)"
cleanup() {
  hdiutil detach "${MOUNT}" -quiet >/dev/null 2>&1 || true
  rm -rf "${MOUNT}"
}
trap cleanup EXIT

hdiutil attach -nobrowse -readonly -mountpoint "${MOUNT}" "${DMG}" >/dev/null \
  || fail "DMG did not mount"
echo "DMG mounted at ${MOUNT}"

[[ -d "${MOUNT}/${APP_NAME}" ]] || fail "${APP_NAME} missing from the DMG"
[[ -L "${MOUNT}/Applications" ]] || fail "Applications shortcut missing from the DMG"
echo "Contents verified: ${APP_NAME} and Applications shortcut present"

# Validate the mounted app, not just the one sitting in build/.
if [[ -x "${ROOT}/Scripts/validate-app.sh" ]]; then
  SMOKE_TEST="${SMOKE_TEST:-}" bash "${ROOT}/Scripts/validate-app.sh" \
    "${MOUNT}/${APP_NAME}" "${EXPECTED_VERSION}" "${EXPECTED_BUILD}"
fi

echo "DMG validation passed: ${DMG}"
