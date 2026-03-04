#!/usr/bin/env bash

set -euo pipefail

version="${BUILDKITE_TAG#v}"

if [[ -z "$version" ]]; then
  echo "Error: BUILDKITE_TAG is unset or empty"
  exit 1
fi

install_gems
make build-resources-xcframework REFRESH_L10N=1 REFRESH_JS_BUILD=1
bundle exec fastlane publish_to_s3 "version:${version}"
