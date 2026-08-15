#!/bin/bash
# Packages the SwiftPM-built OriginCheck executable into a macOS .app bundle
# and zips it with a versioned name.
#
# Prerequisite: run from the repository root after:
#   cd App && swift build -c release
#
# Usage: sh Scripts/package-app.sh <version> <output-dir>
#   <version>   release version, e.g. 0.1.0
#   <output-dir> directory to write OriginCheck.app and the zip into
set -euo pipefail

VERSION="${1:?version required}"
OUT_DIR="${2:?output dir required}"
BINARY="${OUT_DIR}/App/.build/release/OriginCheck"

if [[ ! -x "${BINARY}" ]]; then
  echo "error: binary not found at ${BINARY}. Build the app first:" >&2
  echo "  cd App && swift build -c release" >&2
  exit 1
fi

APP_DIR="${OUT_DIR}/OriginCheck.app"
ZIP="${OUT_DIR}/OriginCheck-${VERSION}-macOS.zip"

rm -rf "${APP_DIR}" "${ZIP}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

cp "${BINARY}" "${APP_DIR}/Contents/MacOS/OriginCheck"

cat > "${APP_DIR}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>OriginCheck</string>
    <key>CFBundleDisplayName</key>
    <string>OriginCheck</string>
    <key>CFBundleIdentifier</key>
    <string>com.origincheck.app</string>
    <key>CFBundleExecutable</key>
    <string>OriginCheck</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

# Ad-hoc sign so the bundle runs on a local Mac. Notarization needs a
# developer certificate and is wired in when one is available.
codesign --force --deep --sign - "${APP_DIR}"

ditto -c -k --keepParent "${APP_DIR}" "${ZIP}"

echo "Packaged ${ZIP}"
