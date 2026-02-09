#!/bin/bash

# Builds a GutenbergKitResources XCFramework from the local source target.
#
# Prerequisites:
#   - Built web assets in ios/Sources/GutenbergKitResources/Resources/
#   - GUTENBERGKIT_SWIFT_USE_LOCAL_RESOURCES=1 must be set
#
# Output:
#   - GutenbergKitResources-<git-sha>.xcframework.zip
#   - GutenbergKitResources-<git-sha>.xcframework.zip.checksum.txt

set -euo pipefail

SCHEME="GutenbergKitResources"
BUILD_DIR="$(mktemp -d)"
OUTPUT_DIR="${1:-$(pwd)}"

GIT_SHA="$(git rev-parse --short HEAD)"
XCFRAMEWORK_NAME="${SCHEME}-${GIT_SHA}.xcframework"
ZIP_NAME="${XCFRAMEWORK_NAME}.zip"

cleanup() {
    rm -rf "${BUILD_DIR}"
}
trap cleanup EXIT

echo "--- Building ${SCHEME} for iphoneos"
xcodebuild archive \
    -scheme "${SCHEME}" \
    -sdk iphoneos \
    -archivePath "${BUILD_DIR}/iphoneos.xcarchive" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    | xcbeautify

echo "--- Building ${SCHEME} for iphonesimulator"
xcodebuild archive \
    -scheme "${SCHEME}" \
    -sdk iphonesimulator \
    -archivePath "${BUILD_DIR}/iphonesimulator.xcarchive" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    | xcbeautify

# Locate the built frameworks
DEVICE_FRAMEWORK="${BUILD_DIR}/iphoneos.xcarchive/Products/usr/local/lib/${SCHEME}.framework"
SIM_FRAMEWORK="${BUILD_DIR}/iphonesimulator.xcarchive/Products/usr/local/lib/${SCHEME}.framework"

# Locate resource bundles
DEVICE_BUNDLE="${BUILD_DIR}/iphoneos.xcarchive/Products/usr/local/lib/${SCHEME}_${SCHEME}.bundle"
SIM_BUNDLE="${BUILD_DIR}/iphonesimulator.xcarchive/Products/usr/local/lib/${SCHEME}_${SCHEME}.bundle"

echo "--- Creating XCFramework"
XCFRAMEWORK_PATH="${BUILD_DIR}/${XCFRAMEWORK_NAME}"

xcodebuild -create-xcframework \
    -framework "${DEVICE_FRAMEWORK}" \
    -framework "${SIM_FRAMEWORK}" \
    -output "${XCFRAMEWORK_PATH}"

# Copy resource bundles into each framework slice
for ARCH_DIR in "${XCFRAMEWORK_PATH}"/*/; do
    FRAMEWORK_DIR=$(find "${ARCH_DIR}" -name "${SCHEME}.framework" -type d)
    if [ -d "${DEVICE_BUNDLE}" ] && [[ "${ARCH_DIR}" == *"ios-arm64"* ]]; then
        cp -R "${DEVICE_BUNDLE}" "${FRAMEWORK_DIR}/"
    elif [ -d "${SIM_BUNDLE}" ]; then
        cp -R "${SIM_BUNDLE}" "${FRAMEWORK_DIR}/"
    fi
done

# Copy dSYMs if present
DEVICE_DSYM="${BUILD_DIR}/iphoneos.xcarchive/dSYMs/${SCHEME}.framework.dSYM"
SIM_DSYM="${BUILD_DIR}/iphonesimulator.xcarchive/dSYMs/${SCHEME}.framework.dSYM"

if [ -d "${DEVICE_DSYM}" ]; then
    mkdir -p "${BUILD_DIR}/dSYMs"
    cp -R "${DEVICE_DSYM}" "${BUILD_DIR}/dSYMs/${SCHEME}-iphoneos.framework.dSYM"
fi
if [ -d "${SIM_DSYM}" ]; then
    mkdir -p "${BUILD_DIR}/dSYMs"
    cp -R "${SIM_DSYM}" "${BUILD_DIR}/dSYMs/${SCHEME}-iphonesimulator.framework.dSYM"
fi

echo "--- Creating ZIP archive"
(cd "${BUILD_DIR}" && ditto -c -k --sequesterRsrc --keepParent "${XCFRAMEWORK_NAME}" "${ZIP_NAME}")
cp "${BUILD_DIR}/${ZIP_NAME}" "${OUTPUT_DIR}/${ZIP_NAME}"

echo "--- Computing checksum"
CHECKSUM=$(swift package compute-checksum "${OUTPUT_DIR}/${ZIP_NAME}")
echo "${CHECKSUM}" > "${OUTPUT_DIR}/${ZIP_NAME}.checksum.txt"

echo ""
echo "XCFramework: ${OUTPUT_DIR}/${ZIP_NAME}"
echo "Checksum:    ${CHECKSUM}"
