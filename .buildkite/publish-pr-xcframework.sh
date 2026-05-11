#!/bin/bash
set -euo pipefail

if [[ "${BUILDKITE_PULL_REQUEST:-false}" == "false" ]]; then
    echo "Not a PR build, skipping PR XCFramework publish"
    exit 0
fi

# Skip on fork PRs: bot credentials and S3 secrets aren't available, and we
# couldn't push the snapshot branch back to the canonical repo anyway.
if [[ -n "${BUILDKITE_PULL_REQUEST_REPO:-}" ]] \
    && [[ "$BUILDKITE_PULL_REQUEST_REPO" != *"wordpress-mobile/GutenbergKit"* ]]; then
    echo "PR is from a fork (${BUILDKITE_PULL_REQUEST_REPO}), skipping XCFramework publish"
    exit 0
fi

echo '--- :robot_face: Use bot for Git operations'
source use-bot-for-git

echo '--- :arrow_down: Downloading XCFramework artifacts'
buildkite-agent artifact download '*.xcframework.zip' . --step "build-xcframework"
buildkite-agent artifact download '*.xcframework.zip.checksum.txt' . --step "build-xcframework"

echo '--- :rubygems: Setting up Gems'
install_gems

echo "--- :rocket: Publishing PR build for PR #${BUILDKITE_PULL_REQUEST}"
bundle exec fastlane publish_pr_xcframework pr_number:"$BUILDKITE_PULL_REQUEST"
