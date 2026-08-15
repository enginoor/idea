#!/bin/bash
# Packages the SwiftPM-built OriginCheck executable into a production
# OriginCheck.app bundle: embedded Sparkle.framework, a versioned Info.plist
# with the Sparkle feed URL and public key, the app icon, and an ad-hoc
# code signature.
#
# Usage: sh Scripts/package-app.sh <version> <build-number> <repo-root> [output-dir]
#   <version>       marketing version, e.g. 1.2.0
#   <build-number>  monotonic build number, e.g. 20260815120000
#   <repo-root>     repository root (the parent of App/, Scripts/, ...)
#   [output-dir]    where to write OriginCheck.app (defaults to <repo-root>/build)
#
# Prerequisites:
#   cd App && swift build -c release
#   cd App && swift package resolve   (fetches the Sparkle binary artifact)
set -euo pipefail

VERSION="${1:?version required}"
BUILD="${2:?build number required}"
ROOT="${3:?repo root required}"
OUT_DIR="${4:-${ROOT}/build}"

BINARY="${ROOT}/App/.build/release/OriginCheck"
APP_DIR="${OUT_DIR}/OriginCheck.app"

if [[ ! -x "${BINARY}" ]]; then
  echo "error: binary not found at ${BINARY}. Build the app first:" >&2
  echo "  cd App && swift build -c release" >&2
  exit 1
fi

# The Sparkle public verification key is committed (it is public). The
# private signing key never enters the repository; it lives in a Keychain
# and/or a CI secret. Releases refuse to build without a real public key so
# an unsigned update can never ship by accident.
PUBLIC_KEY_FILE="${ROOT}/Sparkle/public-key.txt"
if [[ ! -f "${PUBLIC_KEY_FILE}" ]]; then
  echo "error: ${PUBLIC_KEY_FILE} is missing. Generate the Sparkle keys once:" >&2
  echo "  bash Scripts/generate-sparkle-keys.sh" >&2
  exit 1
fi
PUBLIC_KEY="$(tr -d '[:space:]' < "${PUBLIC_KEY_FILE}")"
if [[ -z "${PUBLIC_KEY}" || "${PUBLIC_KEY}" == *"REPLACE"* ]]; then
  echo "error: Sparkle/public-key.txt still contains the placeholder. Run Scripts/generate-sparkle-keys.sh and commit the real public key." >&2
  exit 1
fi

# Sparkle.framework is a prebuilt binary artifact downloaded by SwiftPM.
# It ships pre-signed by the Sparkle project, so it is copied as-is and
# never re-signed: the final codesign below deliberately omits --deep so it
# does not touch (or break) this signature.
SPARKLE_FRAMEWORK="$(find "${ROOT}/App/.build/artifacts" -type d -name Sparkle.framework -path '*macos*' 2>/dev/null | head -1)"
if [[ -z "${SPARKLE_FRAMEWORK}" ]]; then
  echo "error: Sparkle.framework not found. Fetch it first:" >&2
  echo "  cd App && swift package resolve" >&2
  exit 1
fi

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources" "${APP_DIR}/Contents/Frameworks"

cp "${BINARY}" "${APP_DIR}/Contents/MacOS/OriginCheck"

# ditto preserves symlinks, permissions, and resource forks, which plain cp
# can silently drop (Sparkle's framework relies on Versions/Current links).
ditto "${SPARKLE_FRAMEWORK}" "${APP_DIR}/Contents/Frameworks/Sparkle.framework"

# App icon: assets/AppIcon.png is converted to icns by make-icon.sh.
ICNS="${ROOT}/build/AppIcon.icns"
if [[ ! -f "${ICNS}" ]]; then
  bash "${ROOT}/Scripts/make-icon.sh" "${ROOT}"
fi
if [[ -f "${ICNS}" ]]; then
  cp "${ICNS}" "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>OriginCheck</string>
    <key>CFBundleIdentifier</key><string>com.origincheck.app</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>OriginCheck</string>
    <key>CFBundleDisplayName</key><string>OriginCheck</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>SUFeedURL</key><string>https://raw.githubusercontent.com/enginoor/idea/main/appcast.xml</string>
    <key>SUPublicEDKey</key><string>${PUBLIC_KEY}</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUScheduledCheckInterval</key><integer>86400</integer>
    <key>SUAutomaticallyUpdate</key><false/>
</dict>
</plist>
PLIST

printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

# Ad-hoc sign the app bundle. No --deep: Sparkle.framework keeps its own
# signature. Notarization needs a Developer ID certificate and is a separate
# hardening step on top of this.
codesign --force --sign - "${APP_DIR}"

echo "Packaged ${APP_DIR} (version ${VERSION}, build ${BUILD})"
