#!/usr/bin/env bash

# Packages an XCFramework into a ZIP archive with a checksum file.
#
# Prerequisites:
#   - A built .xcframework under build/
#
# Output:
#   - GutenbergKitResources-<git-sha>.xcframework.zip
#   - GutenbergKitResources-<git-sha>.xcframework.zip.checksum.txt

set -euo pipefail

SCHEME="GutenbergKitResources"
BUILD_DIR="$(pwd)/build"
OUTPUT_DIR="${1:-$(pwd)}"

# Address the artifact by exact SHA-suffixed name rather than globbing — keeps
# the packager honest about which xcframework it's shipping even when stale
# builds linger from prior runs or other branches.
GIT_SHA="$(git rev-parse HEAD)"
XCFRAMEWORK_PATH="${BUILD_DIR}/${SCHEME}-${GIT_SHA}.xcframework"

if [ ! -d "${XCFRAMEWORK_PATH}" ]; then
    echo "Error: ${XCFRAMEWORK_PATH} not found. Run build_xcframework.sh first." >&2
    exit 1
fi

XCFRAMEWORK_NAME=$(basename "${XCFRAMEWORK_PATH}")
ZIP_NAME="${XCFRAMEWORK_NAME}.zip"

# Create ZIP archive
echo "--- Creating ZIP archive"
(cd "${BUILD_DIR}" && zip -r "${ZIP_NAME}" "${XCFRAMEWORK_NAME}" > /dev/null)
cp "${BUILD_DIR}/${ZIP_NAME}" "${OUTPUT_DIR}/${ZIP_NAME}"

# Compute checksum
echo "--- Computing checksum"
CHECKSUM=$(swift package compute-checksum "${OUTPUT_DIR}/${ZIP_NAME}")
echo "${CHECKSUM}" > "${OUTPUT_DIR}/${ZIP_NAME}.checksum.txt"

echo ""
echo "XCFramework: ${OUTPUT_DIR}/${ZIP_NAME}"
echo "Checksum:    ${CHECKSUM}"
