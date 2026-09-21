#!/bin/bash
set -euo pipefail

publish_params=$(prepare_to_publish_to_s3_params)

# PR and branch versions include the commit SHA, so an existing one already
# holds this commit's artifact. Tag versions don't, so re-publishing a tag still fails.
if [[ -z "${BUILDKITE_TAG:-}" ]]; then
    version=$(./android/gradlew -q -p ./android :gutenberg:calculateVersionName $publish_params)
    is_published=$(./android/gradlew -q -p ./android :gutenberg:isVersionPublishedToS3 \
        --published-group-id=org.wordpress.gutenbergkit \
        --published-artifact-id=android \
        --version-name="$version")

    if [[ "$is_published" == "true" ]]; then
        echo "Version '$version' is already published to S3, skipping"
        exit 0
    fi
fi

./android/gradlew -p ./android :gutenberg:prepareToPublishToS3 $publish_params :gutenberg:publish
