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
    
    local notes="Platform: $platform\nVersion: $version\nSHA256: $hash\nSource: $url"
    
    gh release create "$tag" "$file" "${file}.sha256" \
        -t "WeChat $platform v$version" \
        -n "$notes"
}
