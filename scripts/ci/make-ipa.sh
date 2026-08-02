#!/usr/bin/env bash
#
# Packages an unsigned .xcarchive into an .ipa suitable for AltStore.
#
# Why not `xcodebuild -exportArchive`? Export requires a signing identity and a
# provisioning profile, which we deliberately do not have: Somna is distributed
# unsigned and re-signed on device by AltStore with the tester's own Apple ID.
# A signed IPA from a Personal Team would install on no device but our own.
#
# An .ipa is just a zip with the app inside a `Payload/` directory, so we build
# it directly.
#
# Usage:  scripts/ci/make-ipa.sh <archive-path> <output-ipa-path>

set -euo pipefail

ARCHIVE="${1:?usage: make-ipa.sh <archive-path> <output-ipa-path>}"
OUTPUT="${2:?usage: make-ipa.sh <archive-path> <output-ipa-path>}"

APP_DIR="${ARCHIVE}/Products/Applications"
APP=$(find "${APP_DIR}" -maxdepth 1 -name "*.app" -print -quit)

if [ -z "${APP}" ]; then
  echo "::error::No .app found in ${APP_DIR}" >&2
  exit 1
fi

STAGING=$(mktemp -d)
trap 'rm -rf "${STAGING}"' EXIT

mkdir -p "${STAGING}/Payload"
cp -R "${APP}" "${STAGING}/Payload/"

# Strip anything that must not ship. Simulator slices and dSYMs would only
# inflate the download the tester pays for on cellular.
find "${STAGING}/Payload" -name "*.dSYM" -prune -exec rm -rf {} + 2>/dev/null || true

mkdir -p "$(dirname "${OUTPUT}")"
rm -f "${OUTPUT}"
( cd "${STAGING}" && zip -qry "${OLDPWD}/${OUTPUT}" Payload )

SIZE=$(stat -f%z "${OUTPUT}" 2>/dev/null || stat -c%s "${OUTPUT}")
echo "Built ${OUTPUT} (${SIZE} bytes) from $(basename "${APP}")"

# The AltStore feed needs the exact byte size, so expose it to later steps.
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "ipa_path=${OUTPUT}"
    echo "ipa_size=${SIZE}"
  } >> "${GITHUB_OUTPUT}"
fi
