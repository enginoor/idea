#!/bin/bash
# Converts the committed 1024 px app icon (assets/AppIcon.png) into a
# standard .iconset and then an .icns for the app bundle. macOS only
# (sips and iconutil ship with macOS).
#
# Usage: sh Scripts/make-icon.sh <repo-root>
set -euo pipefail

ROOT="${1:?repo root required}"
SRC="${ROOT}/assets/AppIcon.png"
BUILD_DIR="${ROOT}/build"
ICONSET="${BUILD_DIR}/AppIcon.iconset"
ICNS="${BUILD_DIR}/AppIcon.icns"

if [[ ! -f "${SRC}" ]]; then
  echo "error: ${SRC} not found." >&2
  exit 1
fi

rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"

# Standard macOS icon sizes: 16, 32, 64, 128, 256, 512 at 1x and 2x.
for SIZE in 16 32 64 128 256 512; do
  sips -z "${SIZE}" "${SIZE}" "${SRC}" --out "${ICONSET}/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "${DOUBLE}" "${DOUBLE}" "${SRC}" --out "${ICONSET}/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done

rm -f "${ICNS}"
iconutil -c icns "${ICONSET}" -o "${ICNS}"
rm -rf "${ICONSET}"

echo "Built ${ICNS}"
