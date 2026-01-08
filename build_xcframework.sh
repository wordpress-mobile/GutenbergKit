#!/usr/bin/env bash

set -euo pipefail

# Originally sourced from:
# https://github.com/OpenSwiftUIProject/ProtobufKit/blob/937eae5426277bec040c7f99bc8e1498c30ed467/Scripts/build_xcframework.sh
#
# Found it via:
# https://forums.swift.org/t/how-on-earth-can-i-create-a-framework-from-a-swift-package/76797/6
#
# Related:
# https://forums.swift.org/t/how-to-build-swift-package-as-xcframework/41414/57

# Script modified from https://docs.emergetools.com/docs/analyzing-a-spm-framework-ios

PACKAGE_NAME=${1-}
if [ -z "$PACKAGE_NAME" ]; then
    echo "No package name provided. Using the first scheme found in the Package.swift."
    PACKAGE_NAME=$(xcodebuild -list | awk 'schemes && NF>0 { print $1; exit } /Schemes:$/ { schemes = 1 }')
    echo "Using: $PACKAGE_NAME"
fi

# Swift optimization level: -Onone (no optimization), -O (optimize for speed), -Osize (optimize for size)
# Default to -O for release builds, can be overridden with SWIFT_OPTIMIZATION_LEVEL environment variable
SWIFT_OPTIMIZATION_LEVEL="${SWIFT_OPTIMIZATION_LEVEL:--O}"
echo "Swift optimization level: $SWIFT_OPTIMIZATION_LEVEL"

# FIXME: Original script was in subfolder, this is in repo root for the time being.
#
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd -P)"
# PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT=$(pwd)

PROJECT_BUILD_DIR="${PROJECT_BUILD_DIR:-"${PROJECT_ROOT}/build"}"
XCODEBUILD_BUILD_DIR="$PROJECT_BUILD_DIR/xcodebuild"
XCODEBUILD_DERIVED_DATA_PATH="$XCODEBUILD_BUILD_DIR/DerivedData"

echo "PROJECT_BUILD_DIR is $PROJECT_BUILD_DIR"

build_framework() {
    local sdk="$1"
    local destination="$2"
    local scheme="$3"

    echo "--- Build framework for $scheme $sdk $destination"

    local XCODEBUILD_ARCHIVE_PATH="./build/$scheme-$sdk.xcarchive"

    rm -rf "$XCODEBUILD_ARCHIVE_PATH"

    # TODO: Consider using this env var to switch between static (default)
    # and dynamic (required for XCFramework)
    #
    # See:
    # https://github.com/OpenSwiftUIProject/ProtobufKit/blob/937eae5426277bec040c7f99bc8e1498c30ed467/Package.swift#L30
    # LIBRARY_TYPE=dynamic xcodebuild archive \
    xcodebuild archive \
        -scheme "$scheme" \
        -archivePath "$XCODEBUILD_ARCHIVE_PATH" \
        -derivedDataPath "$XCODEBUILD_DERIVED_DATA_PATH" \
        -sdk "$sdk" \
        -destination "$destination" \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        INSTALL_PATH='Library/Frameworks' \
        SWIFT_OPTIMIZATION_LEVEL="$SWIFT_OPTIMIZATION_LEVEL" \
        OTHER_SWIFT_FLAGS=-no-verify-emitted-module-interface \
        | xcbeautify

    if [ "$sdk" = "macosx" ]; then
        FRAMEWORK_MODULES_PATH="$XCODEBUILD_ARCHIVE_PATH/Products/Library/Frameworks/$scheme.framework/Versions/Current/Modules"
        mkdir -p "$FRAMEWORK_MODULES_PATH"
        cp -r \
        "$XCODEBUILD_DERIVED_DATA_PATH/Build/Intermediates.noindex/ArchiveIntermediates/$scheme/BuildProductsPath/Release/$scheme.swiftmodule" \
        "$FRAMEWORK_MODULES_PATH/$scheme.swiftmodule"
        rm -rf "$XCODEBUILD_ARCHIVE_PATH/Products/Library/Frameworks/$scheme.framework/Modules"
        ln -s Versions/Current/Modules "$XCODEBUILD_ARCHIVE_PATH/Products/Library/Frameworks/$scheme.framework/Modules"
    else
        FRAMEWORK_MODULES_PATH="$XCODEBUILD_ARCHIVE_PATH/Products/Library/Frameworks/$scheme.framework/Modules"
        mkdir -p "$FRAMEWORK_MODULES_PATH"
        cp -r \
        "$XCODEBUILD_DERIVED_DATA_PATH/Build/Intermediates.noindex/ArchiveIntermediates/$scheme/BuildProductsPath/Release-$sdk/$scheme.swiftmodule" \
        "$FRAMEWORK_MODULES_PATH/$scheme.swiftmodule"
    fi

    # Delete private and package swiftinterface
    rm -f "$FRAMEWORK_MODULES_PATH/$scheme.swiftmodule/*.package.swiftinterface"
    rm -f "$FRAMEWORK_MODULES_PATH/$scheme.swiftmodule/*.private.swiftinterface"
}

copy_resource_bundles() {
    local sdk="$1"
    local scheme="$2"

    echo "--- Copy resource bundles for $scheme $sdk"

    local XCODEBUILD_ARCHIVE_PATH="./build/$scheme-$sdk.xcarchive"
    local FRAMEWORK_PATH="$XCODEBUILD_ARCHIVE_PATH/Products/Library/Frameworks/$scheme.framework"

    # Find all resource bundles in DerivedData
    local BUNDLE_PATH="$XCODEBUILD_DERIVED_DATA_PATH/Build/Intermediates.noindex/ArchiveIntermediates/$scheme/IntermediateBuildFilesPath/UninstalledProducts/$sdk"

    # Copy all .bundle files found
    if [ -d "$BUNDLE_PATH" ]; then
        find "$BUNDLE_PATH" -name "*.bundle" -maxdepth 1 -type d -print0 | while IFS= read -r -d '' bundle; do
            bundle_name=$(basename "$bundle")
            echo "Copying resource bundle: $bundle_name to $FRAMEWORK_PATH"
            # Remove symlink if it exists and copy the actual bundle
            rm -rf "${FRAMEWORK_PATH:?}/$bundle_name"
            cp -R "$bundle" "$FRAMEWORK_PATH/"
        done
    else
        echo "Warning: Bundle path not found: $BUNDLE_PATH"
    fi
}

build_framework "iphonesimulator" "generic/platform=iOS Simulator" "$PACKAGE_NAME"
copy_resource_bundles "iphonesimulator" "$PACKAGE_NAME"

build_framework "iphoneos" "generic/platform=iOS" "$PACKAGE_NAME"
copy_resource_bundles "iphoneos" "$PACKAGE_NAME"

# No macOS support because of UIKit in the dependencies
#
# build_framework "macosx" "generic/platform=macOS" "$PACKAGE_NAME"
# copy_resource_bundles "macosx" "$PACKAGE_NAME"

echo "Builds completed successfully."

pushd "$PROJECT_BUILD_DIR" > /dev/null

rm -rf "$PACKAGE_NAME.xcframework"
xcodebuild -create-xcframework  \
    -framework "$PACKAGE_NAME-iphonesimulator.xcarchive/Products/Library/Frameworks/$PACKAGE_NAME.framework" \
    -framework "$PACKAGE_NAME-iphoneos.xcarchive/Products/Library/Frameworks/$PACKAGE_NAME.framework" \
    -output "$PACKAGE_NAME.xcframework"

cp -r "$PACKAGE_NAME-iphonesimulator.xcarchive/dSYMs" "$PACKAGE_NAME.xcframework/ios-arm64_x86_64-simulator"
cp -r "$PACKAGE_NAME-iphoneos.xcarchive/dSYMs" "$PACKAGE_NAME.xcframework/ios-arm64"

zip -r "$PACKAGE_NAME.xcframework.zip" "$PACKAGE_NAME.xcframework" > /dev/null

# TODO: Remove emoji, print all in green
echo "✅ XCFramework generated at $(pwd)/$PACKAGE_NAME.xcframework"

popd > /dev/null
