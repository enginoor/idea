#!/bin/bash
# Packages build/OriginCheck.app into a branded, drag-to-install DMG:
# custom background, positioned icons, and an Applications shortcut.
#
# Uses dmgbuild when available (it writes the window layout directly into
# the image's .DS_Store, which Finder automation cannot do reliably on
# recent macOS). Falls back to a plain hdiutil DMG when dmgbuild is
# missing; the fallback still carries the app and the Applications link.
#
# Usage: sh Scripts/make-dmg.sh <version> <repo-root> [output-dir]
#   DMGBUILD=/path/to/dmgbuild   optional explicit path to dmgbuild
set -euo pipefail

VERSION="${1:?version required}"
ROOT="${2:?repo root required}"
OUT_DIR="${3:-${ROOT}/build}"

APP="${OUT_DIR}/OriginCheck.app"
DMG="${OUT_DIR}/OriginCheck-${VERSION}.dmg"
BG="${ROOT}/assets/dmg-background@2x.png"
SETTINGS="${ROOT}/Scripts/dmg-settings.py"

if [[ ! -d "${APP}" ]]; then
  echo "error: ${APP} not found. Run Scripts/package-app.sh first." >&2
  exit 1
fi
rm -f "${DMG}"

# Locate dmgbuild: explicit env var, PATH, pip --user, or a venv bin dir.
DMGBUILD="${DMGBUILD:-}"
if [[ -z "${DMGBUILD}" ]] && command -v dmgbuild >/dev/null 2>&1; then
  DMGBUILD="$(command -v dmgbuild)"
fi
if [[ -z "${DMGBUILD}" ]] && [[ -x "$(python3 -m site --user-base 2>/dev/null)/bin/dmgbuild" ]]; then
  DMGBUILD="$(python3 -m site --user-base)/bin/dmgbuild"
fi

if [[ -n "${DMGBUILD}" ]]; then
  APP_PATH="${APP}" DMG_BG="${BG}" "${DMGBUILD}" -s "${SETTINGS}" "OriginCheck" "${DMG}"
else
  echo "dmgbuild not found, building a plain DMG (pip install dmgbuild for the branded layout)." >&2
  staging="$(mktemp -d)"
  trap 'rm -rf "${staging}"' EXIT
  cp -R "${APP}" "${staging}/OriginCheck.app"
  ln -s /Applications "${staging}/Applications"
  hdiutil create -volname "OriginCheck" -srcfolder "${staging}" \
    -fs HFS+ -format UDZO -ov "${DMG}" >/dev/null
fi

[[ -f "${DMG}" ]] || { echo "error: DMG was not created at ${DMG}" >&2; exit 1; }
echo "Built ${DMG} ($(du -h "${DMG}" | cut -f1))"
