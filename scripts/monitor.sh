#!/usr/bin/env bash

set -eo pipefail

# Import common functions
source "$(dirname "$0")/common.sh"

PLATFORM="$1"
DOWNLOAD_URL_OVERRIDE="$2"

if [ -z "$PLATFORM" ]; then
    echo_color "red" "Usage: $0 [all|win|mac|android] [optional_url]"
    exit 1
fi

if [ "$PLATFORM" == "all" ]; then
    if [ -n "$DOWNLOAD_URL_OVERRIDE" ]; then
        echo_color "yellow" "Warning: Custom URL '$DOWNLOAD_URL_OVERRIDE' is ignored in 'all' mode."
    fi
    for p in win mac android; do
        "$0" "$p"
    done
    exit 0
fi

# Normalize platform names
if [ "$PLATFORM" == "windows" ]; then
    PLATFORM="win"
fi

check_github_auth

echo_color "yellow" "Starting WeChat monitor for $PLATFORM..."

# 1. Get Download URL
if [ -n "$DOWNLOAD_URL_OVERRIDE" ]; then
    DOWNLOAD_URL="$DOWNLOAD_URL_OVERRIDE"
    echo_color "yellow" "Using custom download URL: $DOWNLOAD_URL"
else
    DOWNLOAD_URL=$(scrape_url "$PLATFORM")
fi

if [ -z "$DOWNLOAD_URL" ]; then
    echo_color "red" "Failed to scrape download URL for $PLATFORM"
    exit 1
fi
echo_color "green" "Found URL: $DOWNLOAD_URL"

# 2. Extract Basic Version (Fallback)
BASIC_VERSION=$(parse_version_from_url "$DOWNLOAD_URL")
echo_color "green" "Basic Version from URL: $BASIC_VERSION"

# 3. Download (To extract real version)
# We must download to know the real version for Windows
TEMP_DIR="temp_${PLATFORM}_${BASIC_VERSION}"
mkdir -p "$TEMP_DIR"
FILENAME=$(basename "$DOWNLOAD_URL")
FILEPATH="${TEMP_DIR}/${FILENAME}"

echo_color "yellow" "Downloading $FILENAME to extract details..."
if ! curl -C - -L --retry 3 --retry-delay 5 --speed-limit 1024 --speed-time 15 -o "$FILEPATH" "$DOWNLOAD_URL"; then
    echo_color "red" "Download failed."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 4. Extract Detailed Version
VERSION=$(extract_detailed_version "$FILEPATH" "$PLATFORM" "$BASIC_VERSION")
echo_color "green" "Detailed Version: $VERSION"

# 5. Check Remote Release
HASH=$(calculate_sha256 "$FILEPATH")
echo_color "green" "SHA256: $HASH"

EXISTING_TAG=$(find_existing_hash_in_releases "$VERSION" "$PLATFORM" "$HASH") || true

if [ -n "$EXISTING_TAG" ]; then
    echo_color "green" "Hash $HASH already released in $EXISTING_TAG. No action needed."
    rm -rf "$TEMP_DIR"
    exit 0
fi

# If we are here, it means either:
# 1. The version is completely new
# 2. The version exists but with different hashes, and THIS binary has a new hash

TAG="v${VERSION}-${PLATFORM}"
if check_tag_exists "$TAG"; then
    echo_color "yellow" "Version $VERSION exists but has a different hash. Creating supplemental release..."
else
    echo_color "yellow" "New version $VERSION detected. Proceeding to release..."
fi

create_release "$VERSION" "$PLATFORM" "$FILEPATH" "$DOWNLOAD_URL" "$HASH"

# Cleanup
rm -rf "$TEMP_DIR"
echo_color "green" "Done."
