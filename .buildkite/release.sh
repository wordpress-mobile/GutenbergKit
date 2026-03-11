#!/usr/bin/env bash

set -euo pipefail

version="$1"

if [[ -z "$version" ]]; then
  echo "Error: version argument is required"
  exit 1
fi

echo "--- :robot_face: Use bot for Git operations"
source use-bot-for-git

echo "--- :rubygems: Installing gems"
install_gems

echo "--- :xcode: Building XCFramework"
make build-resources-xcframework REFRESH_L10N=1 REFRESH_JS_BUILD=1

echo "--- :rocket: Publishing release $version"
bundle exec fastlane release "version:$version"
