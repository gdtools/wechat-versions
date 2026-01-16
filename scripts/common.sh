#!/usr/bin/env bash

# ====================================================
# 公共函数
# ====================================================

# 彩色输出
echo_color() {
    local color="$1"
    shift
    local message="$*"
    
    case "$color" in
        yellow) echo -e "\033[1;33m$message\033[0m" ;;
        red) echo -e "\033[1;31m$message\033[0m" >&2 ;;
        green) echo -e "\033[1;32m$message\033[0m" ;;
        *) echo "$message" ;;
    esac
}

# Check GitHub CLI status
check_github_auth() {
    gh auth status &>/dev/null || {
        echo_color "red" "GitHub CLI 未登录，请先运行 'gh auth login'"
        exit 1
    }
}

# Scrape Download URL
scrape_url() {
    local platform="$1"
    local url=""
    
    case "$platform" in
        win)
            # Scrape from pc.weixin.qq.com
            # Prefer Universal/64-bit if available, looking for .exe
            url=$(curl -s "https://pc.weixin.qq.com/" | grep -oE "https://[^\"']*WeChatWin_[0-9.]+\.exe" | head -n 1)
            # Fallback if specific version not found, try generic setup but we prefer versioned
            if [ -z "$url" ]; then
                url=$(curl -s "https://pc.weixin.qq.com/" | grep -oE "https://[^\"']*WeChatSetup\.exe" | head -n 1)
            fi
            ;;
        mac)
            # Scrape from mac.weixin.qq.com
            url=$(curl -s "https://mac.weixin.qq.com/?t=mac&lang=zh_CN" | grep -oE "https://[^\"']*WeChatMac_[0-9.]+\.dmg" | head -n 1)
            ;;
        android)
            # Scrape from weixin.qq.com
            # Look for arm64 if possible, else 32bit. Regex for weixin8067android...apk
            url=$(curl -s "https://weixin.qq.com/" | grep -oE "https://[^\"']*weixin[0-9]+android[0-9]+_arm64\.apk" | head -n 1)
            if [ -z "$url" ]; then
                 url=$(curl -s "https://weixin.qq.com/" | grep -oE "https://[^\"']*weixin[0-9]+android[0-9]+\.apk" | head -n 1)
            fi
            ;;
        *)
            echo_color "red" "Unknown platform: $platform"
            return 1
            ;;
    esac
    
    echo "$url"
}

# Parse Version from Filename/URL
parse_version_from_url() {
    local url="$1"
    local filename=$(basename "$url")
    local version=""
    
    if [[ "$filename" =~ WeChatWin_([0-9.]+)\.exe ]]; then
        version="${BASH_REMATCH[1]}"
    elif [[ "$filename" =~ WeChatMac_([0-9.]+)\.dmg ]]; then
        version="${BASH_REMATCH[1]}"
    elif [[ "$filename" =~ weixin([0-9]+)android([0-9]+)(_.*)?\.apk ]]; then
        # android: weixin8067android... -> 8.0.67
        # weixin 8067 -> 8.0.67
        local ver_str="${BASH_REMATCH[1]}"
        # Ensure it has enough digits. Usually 3 or 4 digits. 8067 -> 8.0.67
        if [ ${#ver_str} -ge 3 ]; then
           local major=${ver_str:0:1}
           local minor=${ver_str:1:1}
           local patch=${ver_str:2}
           version="${major}.${minor}.${patch}"
        fi
    fi
    
    echo "$version"
}

# Extract Detailed Version from File
extract_detailed_version() {
    local file="$1"
    local platform="$2"
    local fallback_version="$3"
    
    local detailed_version=""
    
    if [ "$platform" == "win" ] && [ -f "$file" ]; then
        # Try to find version directory inside the archive using 7z
        # Look for pattern [x.x.x.x]
        # output is like: ... 2023-01-01 00:00:00 .... [3.9.10.19]
        local list_out=$(7z l "$file" 2>/dev/null)
        if [ $? -eq 0 ]; then
             detailed_version=$(echo "$list_out" | grep -oE '\[[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\]' | head -n 1 | tr -d '[]')
        fi
    elif [ "$platform" == "mac" ] && [ -f "$file" ]; then
        # Mac: Mount DMG and read Info.plist
        # Use hdiutil for mounting (macos runner only)
        
        # Generate random mount point to avoid collision
        local mount_point="/Volumes/WeChat_$(date +%s)"
        
        # Attach and parse mount point specifically if needed, but -mountpoint is safer
        hdiutil attach "$file" -mountpoint "$mount_point" -nobrowse -readonly -quiet
        
        local plist_path="$mount_point/WeChat.app/Contents/Info.plist"
        if [ -f "$plist_path" ]; then
            # Use PlistBuddy
            detailed_version=$(/usr/libexec/PlistBuddy -c "Print WeChatBundleVersion" "$plist_path" 2>/dev/null)
        fi
        
        # Detach
        hdiutil detach "$mount_point" -force -quiet || true
    fi
    
    if [ -n "$detailed_version" ]; then
        echo "$detailed_version"
    else
        echo "$fallback_version"
    fi
}

# Calculate SHA256 of a file
calculate_sha256() {
    local file="$1"
    if [ ! -f "$file" ]; then
        return 1
    fi
    shasum -a 256 "$file" | awk '{print $1}'
}

# Get Latest Release Version from GitHub
get_latest_release_version() {
    local platform_suffix="$1" # e.g., "win", "mac", "android"
    
     # Semantic sort
    gh release list --json 'tagName' --limit 100 2>/dev/null | \
        jq -r ".[] | select(.tagName | test(\"-${platform_suffix}(_|$)\")) | .tagName" | \
        sed "s/-${platform_suffix}.*//" | \
        jq -s 'unique | sort_by(split(".") | map(tonumber? // .)) | reverse | .[0]' | tr -d '"'
}

# Check if a specific tag exists
check_tag_exists() {
    local tag="$1"
    gh release view "$tag" &>/dev/null
}

# Create Release
create_release() {
    local version="$1"
    local platform="$2"
    local file="$3"
    local url="$4"
    local hash="$5"
    
    local tag="v${version}-${platform}"
    local date_str=$(date -u '+%Y%m%d')
    
    # Handle tag collision (same version, different hash/date)
    if check_tag_exists "$tag"; then
        tag="v${version}-${platform}_${date_str}"
        local counter=1
        while check_tag_exists "$tag"; do
             tag="v${version}-${platform}_${date_str}_${counter}"
             counter=$((counter+1))
        done
    fi
    
    echo_color "yellow" "Creating release: $tag"
    
    local filesize=$(stat -f%z "$file")
    local filename=$(basename "$file")
    
    # Generate SHA256 file
    echo "DestVersion: $version" > "${file}.sha256"
    echo "Sha256: $hash" >> "${file}.sha256"
    echo "FileSize: $filesize" >> "${file}.sha256"
    echo "UpdateTime: $(date -u '+%Y-%m-%d %H:%M:%S') (UTC)" >> "${file}.sha256"
    echo "DownloadFrom: $url" >> "${file}.sha256"
    echo "FileName: $filename" >> "${file}.sha256"
    
    local date_str=$(date "+%Y-%m-%d %H:%M:%S")
    local notes=$(printf "## WeChat %s v%s\n\n> **Released on**: %s\n\n📦 **Download**: [Link](%s)\n\n---\n### Checksums\n\n| Algorithm | Hash |\n| :--- | :--- |\n| **SHA256** | \`%s\` |" "$platform" "$version" "$date_str" "$url" "$hash")
    
    gh release create "$tag" "$file" "${file}.sha256" \
        -t "WeChat $platform v$version" \
        -n "$notes"
    
    if [ $? -eq 0 ]; then
        echo_color "green" "GitHub Release created successfully: $tag"
        # Update RELEASE_LOG.md
        update_release_log "$platform" "$version" "$hash" "$tag"
    else
        echo_color "red" "Failed to create GitHub Release"
        exit 1
    fi
}

update_release_log() {
    local platform="$1"
    local version="$2"
    local hash="$3"
    local tag="$4"
    
    local today=$(date "+%Y-%m-%d")
    local short_hash=$(echo "$hash" | cut -c 1-8)
    local release_link="https://github.com/canc3s/wechat-versions/releases/tag/${tag}"
    
    local row="| $today | **$version** | \`$short_hash\` | [Release]($release_link) |"
    # Assuming RELEASE_LOG.md is in the project root, which is parent of scripts/
    local log_file="$(dirname "$0")/../RELEASE_LOG.md"
    
    # Map platform code to Header Name
    local section_name=""
    if [ "$platform" == "win" ]; then section_name="Windows"; fi
    if [ "$platform" == "mac" ]; then section_name="Mac"; fi
    if [ "$platform" == "android" ]; then section_name="Android"; fi
    
    if [ -f "$log_file" ] && [ -n "$section_name" ]; then
        echo_color "yellow" "Updating RELEASE_LOG.md for $section_name..."
        
        # Insert row after the table header separator of the specific section
        # Logic: Find "## SectionName", then find the next line starting with "| :---", append after it.
        
        awk -v section="## $section_name" -v new_row="$row" '
        BEGIN { found_section=0; inserted=0 }
        {
            print $0
            if ($0 == section) { found_section=1 }
            if (found_section == 1 && $0 ~ /^\| :---/ && inserted == 0) {
                print new_row
                inserted=1
                found_section=0 # Stop looking
            }
        }' "$log_file" > "${log_file}.tmp" && mv "${log_file}.tmp" "$log_file"
        
        # Git operations
        git add "$log_file"
        git commit -m "docs: update release log for $platform $version"
        git push
        echo_color "green" "RELEASE_LOG.md updated and pushed."
    else
        echo_color "red" "RELEASE_LOG.md not found or invalid platform."
    fi
}
