#!/bin/bash
# Validates a packaged OriginCheck.app before it is allowed to ship:
#   - bundle structure and Info.plist
#   - version and build number match the release being cut
#   - executable exists, correct architecture, correct rpath
#   - Sparkle.framework embedded and linked
#   - code signature verifies
#   - optional launch smoke test (SMOKE_TEST=1): the packaged app must
#     start and stay alive, which proves Sparkle loads at runtime
#
# Usage: sh Scripts/validate-app.sh <app-dir> [expected-version] [expected-build]
#   SMOKE_TEST=1 additionally launches the app for a few seconds.
set -euo pipefail

APP="${1:?app path required}"
EXPECTED_VERSION="${2:-}"
EXPECTED_BUILD="${3:-}"

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ -d "${APP}" ]] || fail "app bundle not found at ${APP}"
[[ -d "${APP}/Contents/MacOS" ]] || fail "Contents/MacOS missing"
[[ -d "${APP}/Contents/Resources" ]] || fail "Contents/Resources missing"

# The engine's detection data must ship inside the app: without the resource
# container, text detection has no frequency dictionary or phrase database and
# the app silently degrades. A release without it is not shippable.
# SwiftPM 6 names the container <Target>_<Package>.resources; older versions
# used <Target>_<Package>.bundle. Accept either.
RESOURCE_BUNDLE="$(find "${APP}/Contents/Resources" -maxdepth 1 \( -name '*.bundle' -o -name '*.resources' \) 2>/dev/null | head -1)"
if [[ -n "${RESOURCE_BUNDLE}" ]]; then
  for DATA_FILE in "english-frequencies.tsv" "ai-phrases.json" "sample-passages.json"; do
    find "${RESOURCE_BUNDLE}" -name "${DATA_FILE}" | grep -q . \
      || fail "detection data ${DATA_FILE} missing from embedded resource bundle"
  done
  echo "Detection resource bundle embedded: $(basename "${RESOURCE_BUNDLE}")"
else
  fail "no engine resource bundle in Contents/Resources; detection would not work"
fi

BIN="${APP}/Contents/MacOS/OriginCheck"
[[ -x "${BIN}" ]] || fail "executable not found at ${BIN}"

PLIST="${APP}/Contents/Info.plist"
[[ -f "${PLIST}" ]] || fail "Info.plist missing"

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "${PLIST}" >/dev/null || fail "Info.plist is not valid plist"
fi

# Version and build number must match the release being cut, so the app,
# the tag, the GitHub release, and the update feed can never disagree.
if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PLIST}" 2>/dev/null || true)"
  BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${PLIST}" 2>/dev/null || true)"
  IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${PLIST}" 2>/dev/null || true)"
  [[ -n "${VERSION}" ]] || fail "CFBundleShortVersionString missing from Info.plist"
  [[ -n "${BUILD}" ]] || fail "CFBundleVersion missing from Info.plist"
  [[ -n "${IDENTIFIER}" ]] || fail "CFBundleIdentifier missing from Info.plist"
  if [[ -n "${EXPECTED_VERSION}" ]]; then
    [[ "${VERSION}" == "${EXPECTED_VERSION}" ]] \
      || fail "version mismatch: plist says ${VERSION}, release is ${EXPECTED_VERSION}"
  fi
  if [[ -n "${EXPECTED_BUILD}" ]]; then
    [[ "${BUILD}" == "${EXPECTED_BUILD}" ]] \
      || fail "build number mismatch: plist says ${BUILD}, release is ${EXPECTED_BUILD}"
  fi
  [[ -n "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "${PLIST}" 2>/dev/null || true)" ]] \
    || fail "SUFeedURL missing from Info.plist"
  [[ -n "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${PLIST}" 2>/dev/null || true)" ]] \
    || fail "SUPublicEDKey missing from Info.plist"
  echo "Info.plist: ${IDENTIFIER} ${VERSION} (${BUILD})"
fi

# Architecture of the actual released binary, not an assumption about it.
if command -v lipo >/dev/null 2>&1; then
  ARCHS="$(lipo -archs "${BIN}")"
  [[ -n "${ARCHS}" ]] || fail "lipo reported no architectures"
  echo "Binary architectures: ${ARCHS}"
fi

# Sparkle must be embedded in the bundle, not merely linked at build time.
SPARKLE="${APP}/Contents/Frameworks/Sparkle.framework"
[[ -d "${SPARKLE}" ]] || fail "Sparkle.framework not embedded in Contents/Frameworks"
# Sparkle 2.9.5 ships the framework with Versions/B and Current -> B;
# older releases used Versions/A. Accept either so the validator does not
# hardcode the framework's internal versioning.
SPARKLE_BIN=""
for V in A B; do
  if [[ -x "${SPARKLE}/Versions/${V}/Sparkle" ]]; then
    SPARKLE_BIN="${SPARKLE}/Versions/${V}/Sparkle"
    break
  fi
done
[[ -n "${SPARKLE_BIN}" ]] || fail "Sparkle.framework executable missing"
echo "Sparkle.framework embedded: ${SPARKLE_BIN}"

if command -v otool >/dev/null 2>&1; then
  otool -L "${BIN}" | grep -q "Sparkle.framework" \
    || fail "binary is not linked against Sparkle.framework"
  otool -l "${BIN}" | grep -A3 "LC_RPATH" | grep -q "@executable_path/../Frameworks" \
    || fail "binary is missing the @executable_path/../Frameworks rpath"
  echo "Sparkle link and rpath verified"
fi

# Code signature. The app is ad-hoc signed; Sparkle.framework keeps its own.
if command -v codesign >/dev/null 2>&1; then
  codesign --verify --deep --strict --verbose=2 "${APP}" 2>&1 \
    || fail "code signature verification failed"
  echo "Code signature verified"
fi

# Launch smoke test: prove the packaged app (not the dev build) starts and
# that Sparkle loads at runtime. A dyld failure on Sparkle.framework kills
# the process within the first seconds.
if [[ "${SMOKE_TEST:-}" == "1" ]]; then
  "${BIN}" >/dev/null 2>&1 &
  PID=$!
  sleep 6
  if kill -0 "${PID}" 2>/dev/null; then
    echo "Launch smoke test passed (app stayed alive for 6 s)"
    kill "${PID}" 2>/dev/null || true
    wait "${PID}" 2>/dev/null || true
  else
    wait "${PID}" 2>/dev/null || true
    fail "launch smoke test failed: the packaged app exited during startup"
  fi
fi

echo "App bundle validation passed: ${APP}"
