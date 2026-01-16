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

# 2. Extract Version
VERSION=$(parse_version_from_url "$DOWNLOAD_URL")
if [ -z "$VERSION" ]; then
    echo_color "red" "Failed to parse version from URL: $DOWNLOAD_URL"
    exit 1
fi
echo_color "green" "Detected Version: $VERSION"

# 3. Check Remote Release
TAG="v${VERSION}-${PLATFORM}"
if check_tag_exists "$TAG"; then
    echo_color "yellow" "Version $VERSION already released ($TAG). Checking hash..."
    
    # Check if we should re-verify hash.
    # Logic: Download and compare hash. if different -> Issue or new Release?
    # User said: "Check existing hash, if same -> skip".
    # But to check hash, we must download first.
else
    echo_color "yellow" "New version $VERSION detected. Proceeding to download..."
fi

# 4. Download
TEMP_DIR="temp_${PLATFORM}_${VERSION}"
mkdir -p "$TEMP_DIR"
FILENAME=$(basename "$DOWNLOAD_URL")
FILEPATH="${TEMP_DIR}/${FILENAME}"

echo_color "yellow" "Downloading $FILENAME..."
if ! curl -L --retry 3 --retry-delay 5 -o "$FILEPATH" "$DOWNLOAD_URL"; then
    echo_color "red" "Download failed."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 5. Calculate Hash
HASH=$(calculate_sha256 "$FILEPATH")
echo_color "green" "SHA256: $HASH"

# 6. Verify or Release
if check_tag_exists "$TAG"; then
    # Get existing hash from release body or asset?
    # This is tricky without downloading the asset or parsing the body.
    # common.sh `get_latest_release_info` parsed body.
    # Let's try to get the Release Body of the specific tag.
    
    RELEASE_BODY=$(gh release view "$TAG" --json body -q .body)
    OLD_HASH=$(echo "$RELEASE_BODY" | grep -oE "\b[a-fA-F0-9]{64}\b" | head -n 1)
    
    if [ "$HASH" == "$OLD_HASH" ]; then
        echo_color "green" "Hash matches existing release. No action needed."
        rm -rf "$TEMP_DIR"
        exit 0
    else
        echo_color "red" "Hash MISMATCH! Existing: $OLD_HASH, New: $HASH"
        # Create Issue? Or New Release with timestamp?
        # User requirement: "Check hash consistency".
        # Let's create a NEW release with timestamp suffix to preserve history.
        create_release "$VERSION" "$PLATFORM" "$FILEPATH" "$DOWNLOAD_URL" "$HASH"
    fi
else
    create_release "$VERSION" "$PLATFORM" "$FILEPATH" "$DOWNLOAD_URL" "$HASH"
fi

# Cleanup
rm -rf "$TEMP_DIR"
echo_color "green" "Done."
