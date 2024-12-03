#!/bin/bash

function show_help {
  echo "Usage: $0 {download|help} [version]"
  echo "Commands:"
  echo "  download [version]  Download editor resources for the specified version, or current version if not specified"
  echo "  help                Show this help message"
}

function download {
  if [ -z "$1" ]; then
    # If no version is passed, extract the current version from project's Package.resolved file
    VERSION=$(find . -maxdepth 1 -name "*.xcworkspace" -exec grep -A 5 '"identity" : "gutenbergkit"' {}/xcshareddata/swiftpm/Package.resolved \; | grep '"revision"' | head -n 1 | sed -E 's/.*"revision" : "([^"]+)".*/\1/')

    validate_version_string "$VERSION" "❌ Failed to locate a valid version in your project's \".xcworkspace\" directory, please specify a version"
  else
    VERSION=$1
    validate_version_string "$VERSION"
  fi

  echo "📦 Downloading editor resources for $VERSION"
  ZIP_FILE="gutenberg-kit-resources.zip"
  URL="https://cdn.a8c-ci.services/gutenberg-kit/gutenberg-kit-resources-${VERSION}.zip"
  HTTP_STATUS=$(curl -s -L -w "%{http_code}" -o $ZIP_FILE $URL)
  if [ "$HTTP_STATUS" -ne 200 ]; then
    echo "❌ Failed downloading editor resources (status code: $HTTP_STATUS), check your network connection and the specified version"
    rm $ZIP_FILE
    exit 1
  fi

  OUTPUT_DIR="GutenbergKit"
  mkdir -p $OUTPUT_DIR
  unzip -q $ZIP_FILE -d $OUTPUT_DIR
  rm $ZIP_FILE

  echo "✅ Editor resources downloaded to: $OUTPUT_DIR"
}

function validate_version_string {
  VERSION=$1
  if [ -z "$2" ]; then
    ERROR_MESSAGE="❌ Invalid version: must be valid Git version tag (e.g., v0.0.2) or commit hash, received: $VERSION"
  else
    ERROR_MESSAGE="$2"
  fi

  if [[ ! "$VERSION" =~ ^[0-9a-f]{7,40}$ && ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$ERROR_MESSAGE"
    exit 1
  fi
}

case "$1" in
  download)
    download $2
    ;;
  help|*)
    show_help
    ;;
esac
