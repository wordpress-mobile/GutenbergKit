#!/bin/bash -eu

echo "--- :rubygems: Installing Ruby Dependencies"
pushd ./ios > /dev/null
install_gems

echo "--- :s3: Uploading iOS artifacts to S3"
bundle exec fastlane upload_ios_artifacts_to_s3

# Restore the working directory
popd > /dev/null
