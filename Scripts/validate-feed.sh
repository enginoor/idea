#!/bin/bash
# Validates appcast.xml before a release is published:
#   - the feed is well-formed XML
#   - every enclosure carries url, length, sparkle:version,
#     sparkle:shortVersionString, and sparkle:edSignature
#   - the newest entry matches the release being cut (version + build)
#   - the download URL points at the GitHub release asset for this version
#
# Usage: sh Scripts/validate-feed.sh <repo-root> [version] [build] [github-repo]
set -euo pipefail

ROOT="${1:?repo root required}"
VERSION="${2:-}"
BUILD="${3:-}"
GITHUB_REPO="${4:-}"
FEED="${ROOT}/appcast.xml"

[[ -f "${FEED}" ]] || { echo "error: ${FEED} not found" >&2; exit 1; }

if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout "${FEED}" || { echo "error: appcast.xml is not well-formed XML" >&2; exit 1; }
elif command -v python3 >/dev/null 2>&1; then
  python3 -c "import sys, xml.etree.ElementTree as ET; ET.parse(sys.argv[1])" "${FEED}" \
    || { echo "error: appcast.xml is not well-formed XML" >&2; exit 1; }
else
  echo "warning: no XML parser found, skipping well-formedness check" >&2
fi
echo "appcast.xml is well-formed XML"

python3 - "${FEED}" "${VERSION}" "${BUILD}" "${GITHUB_REPO}" <<'PY'
import sys
import xml.etree.ElementTree as ET

feed, version, build, github_repo = sys.argv[1:5]
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
tree = ET.parse(feed)
channel = tree.getroot().find("channel")
items = channel.findall("item")
if not items:
    print("warning: feed has no release entries yet")
    sys.exit(0)

required = ["url", "length"]
for item in items:
    enc = item.find("enclosure")
    if enc is None:
        print("error: item without an enclosure")
        sys.exit(1)
    for key in required:
        if not enc.get(key):
            print(f"error: enclosure missing {key}")
            sys.exit(1)
    for key in ("version", "shortVersionString", "edSignature"):
        if not enc.get(f"{{{ns['sparkle']}}}{key}"):
            print(f"error: enclosure missing sparkle:{key}")
            sys.exit(1)

if build and version:
    newest = items[0].find("enclosure")
    got_version = newest.get(f"{{{ns['sparkle']}}}shortVersionString")
    got_build = newest.get(f"{{{ns['sparkle']}}}version")
    if got_version != version or got_build != build:
        print(f"error: newest feed entry is {got_version} ({got_build}), expected {version} ({build})")
        sys.exit(1)
    if github_repo:
        expected_prefix = f"https://github.com/{github_repo}/releases/download/v{version}/"
        if not newest.get("url", "").startswith(expected_prefix):
            print(f"error: download URL {newest.get('url')} does not point at the GitHub release asset")
            sys.exit(1)

print(f"appcast validation passed: {len(items)} release entr{'y' if len(items) == 1 else 'ies'}")
PY
