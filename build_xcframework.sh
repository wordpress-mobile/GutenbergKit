#!/usr/bin/env bash

# Builds a GutenbergKitResources XCFramework from the local source target.
#
# Prerequisites:
#   - Built web assets in ios/Sources/GutenbergKitResources/Gutenberg/
#   - Package.swift must have `resourcesMode` set to `.local`
#
# Output:
#   - build/GutenbergKitResources-<git-sha>.xcframework
#
# Adapted from:
# https://github.com/OpenSwiftUIProject/ProtobufKit/blob/937eae542/Scripts/build_xcframework.sh
# https://docs.emergetools.com/docs/analyzing-a-spm-framework-ios

set -euo pipefail

SCHEME="GutenbergKitResources"
# Minimum iOS version, read from Package.swift's declared platform so the
# framework's MinimumOSVersion (and the dylib link target below) can't drift
# from the package. SwiftPM normalizes `.v17` to "17.0" — the exact format
# App Store Connect expects for MinimumOSVersion.
MINIMUM_IOS_VERSION="$(swift package dump-package | jq -er '.platforms[] | select(.platformName == "ios") | .version' 2>/dev/null || true)"
if [[ -z "${MINIMUM_IOS_VERSION}" ]]; then
    echo "Error: could not read the iOS deployment target from Package.swift (is 'jq' installed and the Swift toolchain configured? check DEVELOPER_DIR / xcode-select -p)" >&2
    exit 1
fi
# Marketing version stamped into the framework's Info.plist, sourced from
# package.json so it always tracks the release. Read with jq (already required
# above) so this script needs no separate Node dependency and both version
# reads stay consistent. Fail closed rather than stamping a placeholder: a
# silently-wrong version is exactly the drift we want to prevent. App Store
# Connect rejects any embedded framework whose Info.plist lacks
# CFBundleShortVersionString.
# `.version // empty` collapses a missing/null/empty `version` to empty output
# so the guard below catches it, rather than stamping a literal "null".
MARKETING_VERSION="$(jq -er '.version // empty' package.json 2>/dev/null || true)"
if [[ -z "${MARKETING_VERSION}" ]]; then
    echo "Error: could not read the version field from package.json (is 'jq' installed and is this the repo root?)" >&2
    exit 1
fi

# CFBundleVersion allows at most three period-separated non-negative integers,
# so a SemVer prerelease like `0.19.0-alpha.0` is rejected (altool 90058). No
# substitution helps — prerelease identifiers are alphanumeric by spec — so
# strip the prerelease (`-...`) and build-metadata (`+...`) suffixes and stamp
# the `major.minor.patch` core. CFBundleShortVersionString keeps the full
# version, which Apple accepts.
#
# Reusing a core version across an alpha and its final release is safe:
# artifacts are identified by git SHA and by CDN URL plus SwiftPM checksum,
# never by this key.
BUNDLE_VERSION="${MARKETING_VERSION%%[-+]*}"

BUILD_DIR="$(pwd)/build"
DERIVED_DATA_PATH="${BUILD_DIR}/DerivedData"

GIT_SHA="$(git rev-parse HEAD)"
XCFRAMEWORK_NAME="${SCHEME}-${GIT_SHA}.xcframework"

# Remove prior xcframework artifacts so re-runs are hermetic and downstream
# tools (signing, packaging) never have to disambiguate between stale and
# fresh builds.
mkdir -p "${BUILD_DIR}"
find "${BUILD_DIR}" -maxdepth 1 \
    \( -name "*.xcframework" -type d \
    -o -name "*.xcframework.zip" -type f \
    -o -name "*.xcframework.zip.checksum.txt" -type f \) \
    -exec rm -rf {} +

link_dylib() {
    local object_file="$1"
    local output="$2"
    local sdk="$3"

    local sdk_path
    sdk_path="$(xcrun --sdk "${sdk}" --show-sdk-path)"
    local install_name="@rpath/${SCHEME}.framework/${SCHEME}"

    local archs
    archs=$(xcrun lipo -archs "${object_file}")

    local arch_count
    arch_count=$(echo "${archs}" | wc -w | tr -d ' ')

    local dylibs=()
    for arch in ${archs}; do
        local thin_o="${BUILD_DIR}/${SCHEME}-${sdk}-${arch}.o"
        local thin_dylib="${BUILD_DIR}/${SCHEME}-${sdk}-${arch}.dylib"

        if [[ "${arch_count}" -eq 1 ]]; then
            thin_o="${object_file}"
        else
            xcrun lipo "${object_file}" -thin "${arch}" -output "${thin_o}"
        fi

        local target="${arch}-apple-ios${MINIMUM_IOS_VERSION}"
        if [[ "${sdk}" == "iphonesimulator" ]]; then
            target="${target}-simulator"
        fi

        xcrun clang -target "${target}" -dynamiclib \
            -install_name "${install_name}" \
            -o "${thin_dylib}" \
            "${thin_o}" \
            -isysroot "${sdk_path}" \
            -L "${sdk_path}/usr/lib/swift" \
            -L "${sdk_path}/usr/lib"

        dylibs+=("${thin_dylib}")
    done

    if [[ ${#dylibs[@]} -eq 1 ]]; then
        cp "${dylibs[0]}" "${output}"
    else
        xcrun lipo -create "${dylibs[@]}" -output "${output}"
    fi
}

build_framework() {
    local sdk="$1"
    local destination="$2"
    local archive_path="${BUILD_DIR}/${SCHEME}-${sdk}.xcarchive"

    echo "--- Building ${SCHEME} for ${sdk}"

    rm -rf "${archive_path}"

    xcodebuild archive \
        -scheme "${SCHEME}" \
        -archivePath "${archive_path}" \
        -derivedDataPath "${DERIVED_DATA_PATH}" \
        -sdk "${sdk}" \
        -destination "${destination}" \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        INSTALL_PATH='Library/Frameworks' \
        OTHER_SWIFT_FLAGS=-no-verify-emitted-module-interface \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        | xcbeautify

    # SPM archives don't produce a .framework — assemble it from DerivedData
    local intermediates="${DERIVED_DATA_PATH}/Build/Intermediates.noindex/ArchiveIntermediates/${SCHEME}"
    local build_products="${intermediates}/BuildProductsPath/Release-${sdk}"
    local generated_maps="${intermediates}/IntermediateBuildFilesPath/GeneratedModuleMaps-${sdk}"

    local framework_path="${BUILD_DIR}/frameworks/${sdk}/${SCHEME}.framework"
    rm -rf "${framework_path}"
    mkdir -p "${framework_path}/Modules"
    mkdir -p "${framework_path}/Headers"

    # Binary: SPM produces a .o object file — link it into a dylib so that
    # the resource_bundle_accessor's BundleFinder class stays inside the
    # framework at runtime (otherwise it gets statically linked into the
    # consuming app binary and Bundle(for:) resolves to the wrong bundle).
    link_dylib "${build_products}/${SCHEME}.o" "${framework_path}/${SCHEME}" "${sdk}"

    # Swift module
    cp -r "${build_products}/${SCHEME}.swiftmodule" "${framework_path}/Modules/${SCHEME}.swiftmodule"
    rm -f "${framework_path}/Modules/${SCHEME}.swiftmodule"/*.package.swiftinterface
    rm -f "${framework_path}/Modules/${SCHEME}.swiftmodule"/*.private.swiftinterface

    # Module map and generated header
    cp "${generated_maps}/${SCHEME}.modulemap" "${framework_path}/Modules/module.modulemap"
    cp "${generated_maps}/${SCHEME}-Swift.h" "${framework_path}/Headers/${SCHEME}-Swift.h"

    # Framework Info.plist. CFBundleShortVersionString, CFBundleVersion, and
    # MinimumOSVersion are required by App Store Connect for any framework
    # embedded in a submitted app — altool rejects the upload without them.
    cat > "${framework_path}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${SCHEME}</string>
    <key>CFBundleIdentifier</key>
    <string>org.wordpress.GutenbergKitResources</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${SCHEME}</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUNDLE_VERSION}</string>
    <key>MinimumOSVersion</key>
    <string>${MINIMUM_IOS_VERSION}</string>
</dict>
</plist>
PLIST
}

copy_resource_bundles() {
    local sdk="$1"
    local framework_path="${BUILD_DIR}/frameworks/${sdk}/${SCHEME}.framework"
    local bundle_path="${DERIVED_DATA_PATH}/Build/Intermediates.noindex/ArchiveIntermediates/${SCHEME}/IntermediateBuildFilesPath/UninstalledProducts/${sdk}"

    echo "--- Copying resource bundles for ${sdk}"

    if [ ! -d "${bundle_path}" ]; then
        echo "Error: bundle path not found: ${bundle_path}" >&2
        exit 1
    fi

    find "${bundle_path}" -name "*.bundle" -maxdepth 1 -type d -print0 | while IFS= read -r -d '' bundle; do
        bundle_name=$(basename "${bundle}")
        echo "  ${bundle_name} -> ${framework_path}/"
        rm -rf "${framework_path:?}/${bundle_name}"
        cp -R "${bundle}" "${framework_path}/"
    done
}

# Slice directory names depend on the architectures actually built — e.g.
# `ios-arm64-simulator` when only arm64 is built vs `ios-arm64_x86_64-simulator`
# for a universal slice — so resolve them from the XCFramework rather than
# hardcoding.
resolve_slice_dir() {
    local sdk="$1"
    local matches=()
    local dir name

    for dir in "${XCFRAMEWORK_PATH}"/ios-*; do
        [ -d "${dir}" ] || continue
        name=$(basename "${dir}")
        case "${sdk}" in
            iphoneos)
                case "${name}" in
                    *-simulator|*-maccatalyst) continue ;;
                esac
                ;;
            iphonesimulator)
                case "${name}" in
                    *-simulator) ;;
                    *) continue ;;
                esac
                ;;
            *)
                echo "Error: unknown SDK '${sdk}'" >&2
                return 1
                ;;
        esac
        matches+=("${name}")
    done

    if [ ${#matches[@]} -ne 1 ]; then
        echo "Error: expected exactly one ${sdk} slice in ${XCFRAMEWORK_PATH}, found ${#matches[@]}: ${matches[*]:-<none>}" >&2
        return 1
    fi

    echo "${matches[0]}"
}

copy_dsyms_for_sdk() {
    local sdk="$1"
    local dsyms_path="${BUILD_DIR}/${SCHEME}-${sdk}.xcarchive/dSYMs"

    if [ ! -d "${dsyms_path}" ]; then
        return
    fi

    local slice
    slice=$(resolve_slice_dir "${sdk}")

    cp -r "${dsyms_path}" "${XCFRAMEWORK_PATH}/${slice}/"
}

# Reads a top-level Info.plist value, printing empty string if the key is
# absent so callers can distinguish "missing" from a real value.
plist_value() {
    plutil -extract "$1" raw -o - "$2" 2>/dev/null || true
}

# Guards against the framework's Info.plist drifting out of sync with the
# rest of the release. Runs against the actual shipped slice so a dropped or
# stale key fails GutenbergKit's own CI here, rather than a consumer's App
# Store upload three hops downstream (see altool errors 90057 / 90360).
verify_framework_plist() {
    local plist="$1"

    plutil -lint "${plist}" >/dev/null

    local short_version bundle_version min_os
    short_version="$(plist_value CFBundleShortVersionString "${plist}")"
    bundle_version="$(plist_value CFBundleVersion "${plist}")"
    min_os="$(plist_value MinimumOSVersion "${plist}")"

    if [[ "${short_version}" != "${MARKETING_VERSION}" ]]; then
        echo "Error: ${plist}: CFBundleShortVersionString='${short_version}' does not match package.json version '${MARKETING_VERSION}'" >&2
        exit 1
    fi
    if [[ "${bundle_version}" != "${BUNDLE_VERSION}" ]]; then
        echo "Error: ${plist}: CFBundleVersion='${bundle_version}' does not match expected '${BUNDLE_VERSION}' (derived from package.json version '${MARKETING_VERSION}')" >&2
        exit 1
    fi
    # Assert Apple's grammar directly, not just agreement with package.json: a
    # value can track the release perfectly and still be rejected on upload.
    if [[ ! "${bundle_version}" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
        echo "Error: ${plist}: CFBundleVersion='${bundle_version}' must be at most three period-separated non-negative integers (altool 90058)" >&2
        exit 1
    fi
    if [[ "${min_os}" != "${MINIMUM_IOS_VERSION}" ]]; then
        echo "Error: ${plist}: MinimumOSVersion='${min_os}' does not match expected '${MINIMUM_IOS_VERSION}'" >&2
        exit 1
    fi

    echo "  OK: ${plist} (v${short_version}, min iOS ${min_os})"
}

# Build for both platforms
build_framework "iphoneos" "generic/platform=iOS"
copy_resource_bundles "iphoneos"

build_framework "iphonesimulator" "generic/platform=iOS Simulator"
copy_resource_bundles "iphonesimulator"

# Create XCFramework
echo "--- Creating XCFramework"

DEVICE_FRAMEWORK="${BUILD_DIR}/frameworks/iphoneos/${SCHEME}.framework"
SIM_FRAMEWORK="${BUILD_DIR}/frameworks/iphonesimulator/${SCHEME}.framework"
XCFRAMEWORK_PATH="${BUILD_DIR}/${XCFRAMEWORK_NAME}"

rm -rf "${XCFRAMEWORK_PATH}"
xcodebuild -create-xcframework \
    -framework "${DEVICE_FRAMEWORK}" \
    -framework "${SIM_FRAMEWORK}" \
    -output "${XCFRAMEWORK_PATH}"

# Copy dSYMs into xcframework slices
copy_dsyms_for_sdk "iphoneos"
copy_dsyms_for_sdk "iphonesimulator"

# Verify every slice's framework Info.plist before the artifact leaves this step
echo "--- Verifying framework Info.plist"
verified_count=0
for slice_dir in "${XCFRAMEWORK_PATH}"/ios-*; do
    [ -d "${slice_dir}" ] || continue
    verify_framework_plist "${slice_dir}/${SCHEME}.framework/Info.plist"
    verified_count=$((verified_count + 1))
done
# Fail closed if the glob matched nothing: without nullglob the loop above
# would run zero iterations and exit 0, letting an empty or malformed
# XCFramework pass the very gate meant to catch it.
if [[ "${verified_count}" -eq 0 ]]; then
    echo "Error: no framework slices found to verify in ${XCFRAMEWORK_PATH}" >&2
    exit 1
fi

echo ""
echo "XCFramework: ${XCFRAMEWORK_PATH}"
