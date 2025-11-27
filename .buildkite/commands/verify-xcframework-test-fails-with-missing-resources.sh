#!/bin/bash -eu

set -o pipefail

echo "--- :pencil2: Breaking bundle resource path to verify test catches failures"
# Replace "Gutenberg" with "folder_that_does_not_exist" in the HTMLPreviewManager
sed -i.bak 's/forResource: "Gutenberg", withExtension: nil/forResource: "folder_that_does_not_exist", withExtension: nil/g' ios/Sources/GutenbergKit/Sources/Views/HTMLPreview/HTMLPreviewManager.swift

echo "--- :package: Rebuilding XCFramework with broken resource path"
make build-xcframework-debug

echo "--- :apple: Running integration tests (expecting failure)"
set +e  # Don't exit on error
make test-xcframework-integration MAKECMDGOALS=test-xcframework-integration
TEST_EXIT_CODE=$?
set -e  # Re-enable exit on error

echo "--- :mag: Restoring original file"
mv ios/Sources/GutenbergKit/Sources/Views/HTMLPreview/HTMLPreviewManager.swift.bak ios/Sources/GutenbergKit/Sources/Views/HTMLPreview/HTMLPreviewManager.swift

echo "--- :white_check_mark: Verifying test failed as expected"
if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo "ERROR: Tests passed when they should have failed! The test does not properly catch missing bundle resources."
    exit 1
else
    echo "SUCCESS: Tests failed as expected when bundle resources were missing (exit code: $TEST_EXIT_CODE)"
    exit 0
fi
