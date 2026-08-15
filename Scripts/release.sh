#!/bin/bash
# Cut an OriginCheck release end to end.
#
#   bash Scripts/release.sh v1.2.0
#
# One command, one lifecycle:
#   validate repository state  ->  validate version  ->  verify tests/CI
#   ->  build the production app (on macOS)  ->  validate the bundle
#   ->  create and validate the DMG (on macOS)  ->  create the version tag
#   ->  push the tag  ->  the Release workflow builds, signs, and publishes
#   ->  wait for it  ->  verify the published DMG
#
# The production build, DMG, Sparkle signing, appcast update, and GitHub
# release are executed by the Release workflow on macOS runners, so this
# script runs on any machine with git and the gh CLI. When run on a Mac it
# additionally performs a full local pre-flight build so packaging problems
# surface before the tag is pushed.
#
# Safety: nothing is published unless the working tree is clean, the version
# is well-formed, the tag does not exist, CI is green for this commit, and
# the Sparkle public key is in place.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

VERSION_ARG="${1:-}"
if [[ -z "${VERSION_ARG}" ]]; then
  echo "usage: bash Scripts/release.sh vX.Y.Z" >&2
  exit 1
fi
VERSION="${VERSION_ARG#v}"
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version must look like 1.2.0, got '${VERSION_ARG}'" >&2
  exit 1
fi
TAG="v${VERSION}"
# Derive owner/repo from the origin remote so this works from any fork.
REMOTE_URL="$(git config --get remote.origin.url || true)"
REMOTE_URL="${REMOTE_URL%.git}"
REPO="$(echo "${REMOTE_URL}" | sed -E 's#(https?://github.com/|git@github.com:)([^/]+)/([^/]+)$#\2/\3#')"
if [[ -z "${REPO}" || "${REPO}" == *github.com* ]]; then
  echo "error: could not derive the GitHub repository from remote.origin.url." >&2
  exit 1
fi

log() { printf '\033[1;36m==>\033[0m %s\n' "$1"; }

# --- Preconditions ----------------------------------------------------------
if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree is not clean. Commit or stash first." >&2
  exit 1
fi
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "${BRANCH}" != "main" ]]; then
  echo "error: releases are cut from main (currently on ${BRANCH})." >&2
  exit 1
fi
if ! command -v gh >/dev/null 2>&1; then
  echo "error: the gh CLI is required. Install it from https://cli.github.com" >&2
  exit 1
fi
gh auth status >/dev/null 2>&1 || { echo "error: gh is not authenticated. Run 'gh auth login'." >&2; exit 1; }

git fetch --tags origin -q
if git rev-parse "${TAG}" >/dev/null 2>&1; then
  echo "error: tag ${TAG} already exists locally." >&2
  exit 1
fi
if git ls-remote --tags origin "refs/tags/${TAG}" | grep -q "${TAG}"; then
  echo "error: tag ${TAG} already exists on origin." >&2
  exit 1
fi

SHA="$(git rev-parse HEAD)"
log "Validating release ${TAG} at $(git rev-parse --short HEAD)"

# --- CI gate: the exact commit being released must be green ----------------
log "Verifying CI is green for $(git rev-parse --short HEAD)"
CONCLUSION="$(gh run list --commit "${SHA}" --workflow ci.yml \
  --json status,conclusion --jq '[.[] | select(.status == "completed")][0].conclusion' 2>/dev/null || true)"
if [[ -z "${CONCLUSION}" ]]; then
  PENDING="$(gh run list --commit "${SHA}" --workflow ci.yml \
    --json status --jq '[.[] | select(.status != "completed")] | length' 2>/dev/null || true)"
  if [[ "${PENDING:-0}" != "0" ]]; then
    echo "error: CI is still running for this commit. Wait for it to finish, then retry." >&2
  else
    echo "error: no completed CI run found for this commit. Push the code and wait for CI, then retry." >&2
  fi
  exit 1
fi
if [[ "${CONCLUSION}" != "success" ]]; then
  echo "error: CI is not green for this commit (conclusion: ${CONCLUSION})." >&2
  exit 1
fi
echo "CI green for ${SHA:0:7}"

# --- Sparkle public key must be real ----------------------------------------
PUBLIC_KEY_FILE="${ROOT}/Sparkle/public-key.txt"
if [[ ! -f "${PUBLIC_KEY_FILE}" ]]; then
  echo "error: Sparkle/public-key.txt is missing. Run bash Scripts/generate-sparkle-keys.sh once on a Mac." >&2
  exit 1
fi
if grep -q "REPLACE" "${PUBLIC_KEY_FILE}" || [[ -z "$(tr -d '[:space:]' < "${PUBLIC_KEY_FILE}")" ]]; then
  echo "error: Sparkle/public-key.txt still contains the placeholder. Run Scripts/generate-sparkle-keys.sh and commit the real key." >&2
  exit 1
fi

# --- Optional local pre-flight build (macOS only) ----------------------------
if [[ "$(uname -s)" == "Darwin" ]]; then
  log "Pre-flight build (macOS detected)"
  command -v swift >/dev/null 2>&1 || { echo "error: swift not found" >&2; exit 1; }
  command -v hdiutil >/dev/null 2>&1 || { echo "error: hdiutil not found" >&2; exit 1; }
  swift test
  (cd App && swift package resolve -q && swift build -c release)

  BUILD_NUMBER="$(date -u +%Y%m%d%H%M%S)"
  log "Packaging OriginCheck ${VERSION} (build ${BUILD_NUMBER})"
  bash Scripts/package-app.sh "${VERSION}" "${BUILD_NUMBER}" "${ROOT}"
  SMOKE_TEST=1 bash Scripts/validate-app.sh "${ROOT}/build/OriginCheck.app" "${VERSION}" "${BUILD_NUMBER}"
  bash Scripts/make-dmg.sh "${VERSION}" "${ROOT}"
  SMOKE_TEST=1 bash Scripts/validate-dmg.sh "${ROOT}/build/OriginCheck-${VERSION}.dmg" "OriginCheck.app" "${VERSION}" "${BUILD_NUMBER}"
  echo "Pre-flight build passed: the app and DMG build cleanly on this Mac."
else
  log "Not macOS: skipping the local build. The Release workflow builds the production app on macOS runners."
fi

# --- Tag and push ------------------------------------------------------------
log "Creating tag ${TAG}"
git tag -a "${TAG}" -m "OriginCheck ${VERSION}"
git push origin "${TAG}"

log "Release workflow started for ${TAG}. Waiting for it to finish..."
RUN_ID=""
for _ in $(seq 1 180); do
  sleep 15
  STATUS="$(gh run list --commit "${SHA}" --workflow release.yml \
    --json databaseId,status,conclusion,event \
    --jq '[.[] | select(.event == "push")][0] | "\(.databaseId) \(.status) \(.conclusion)"' 2>/dev/null || true)"
  RUN_ID="$(echo "${STATUS}" | awk '{print $1}')"
  STATE="$(echo "${STATUS}" | awk '{print $2}')"
  if [[ "${STATE}" == "completed" ]]; then
    break
  fi
done

if [[ "${STATE}" != "completed" ]]; then
  echo "error: timed out waiting for the Release workflow. Check https://github.com/${REPO}/actions" >&2
  exit 1
fi
if [[ -n "${RUN_ID}" ]]; then
  echo "Release workflow run: https://github.com/${REPO}/actions/runs/${RUN_ID}"
fi

CONCLUSION="$(echo "${STATUS}" | awk '{print $3}')"
if [[ "${CONCLUSION}" != "success" ]]; then
  echo "error: the Release workflow finished with conclusion '${CONCLUSION}'. See the run log above." >&2
  exit 1
fi

# --- Verify the published artifact -------------------------------------------
log "Verifying the published release"
DMG_ASSET="OriginCheck-${VERSION}.dmg"
DMG_FOUND="$(gh api "/repos/${REPO}/releases/tags/${TAG}" \
  --jq "[.assets[].name] | index(\"${DMG_ASSET}\") != null" 2>/dev/null || echo false)"
if [[ "${DMG_FOUND}" != "true" ]]; then
  echo "error: release ${TAG} does not contain the ${DMG_ASSET} asset." >&2
  exit 1
fi

log "Released ${TAG}"
echo "  https://github.com/${REPO}/releases/tag/${TAG}"
echo "  DMG: https://github.com/${REPO}/releases/download/${TAG}/${DMG_ASSET}"
echo "  Users on macOS 14+ can now update automatically through Sparkle."
