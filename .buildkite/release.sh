#!/bin/bash

set -euo pipefail

NEW_VERSION="${1:-}"
if [[ -z "$NEW_VERSION" ]]; then
    echo "ERROR: version argument is required." >&2
    echo "Usage: $0 vX.Y.Z" >&2
    exit 1
fi

echo '--- :robot_face: Use bot for Git operations'
source use-bot-for-git

echo '--- :arrow_down: Downloading XCFramework artifacts'
buildkite-agent artifact download '*.xcframework.zip' . --step "build-xcframework"
buildkite-agent artifact download '*.xcframework.zip.checksum.txt' . --step "build-xcframework"

echo '--- :rubygems: Setting up Gems'
install_gems

echo "--- :rocket: Publishing Swift release $NEW_VERSION"
bundle exec fastlane release "version:$NEW_VERSION"
