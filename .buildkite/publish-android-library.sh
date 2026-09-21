#!/bin/bash
set -euo pipefail

publish_params=$(prepare_to_publish_to_s3_params)

# Versions are keyed by commit and the plugin refuses to overwrite one, so a
# second build of the same commit (e.g., a rebuild) would otherwise fail here.
version=$(./android/gradlew -q -p ./android :gutenberg:calculateVersionName $publish_params)
is_published=$(./android/gradlew -q -p ./android :gutenberg:isVersionPublishedToS3 \
    --published-group-id=org.wordpress.gutenbergkit \
    --published-artifact-id=android \
    --version-name="$version")

if [[ "$is_published" == "true" ]]; then
    echo "Version '$version' is already published to S3, skipping"
    exit 0
fi

./android/gradlew -p ./android :gutenberg:prepareToPublishToS3 $publish_params :gutenberg:publish
