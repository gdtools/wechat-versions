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

# 检查 GitHub CLI 登录状态
check_github_auth() {
    gh auth status &>/dev/null || {
        echo_color "red" "GitHub CLI 未登录，请先运行 'gh auth login'"
        exit 1
    }
}

# 准备文件并计算 SHA256
prepare_files() {
    local PLATFORM="$1"
    local VERSION="$2"
    local SOURCE_FILE="$3"
    local TARGET_DIR="$4"
    local DOWNLOAD_URL="$5"
    
    echo_color "yellow" "准备文件"
    
    mkdir -p "$TARGET_DIR"
    
    # 计算 SHA256
    local NOW_SUM256=$(shasum -a 256 "$SOURCE_FILE" | awk '{print $1}')
    
    # 创建 SHA256 文件
    cat > "${SOURCE_FILE}.sha256" <<EOF
DestVersion: $VERSION
Sha256: $NOW_SUM256
UpdateTime: $(date -u '+%Y-%m-%d %H:%M:%S') (UTC)
DownloadFrom: $DOWNLOAD_URL
EOF

    echo_color "green" "SHA256: $NOW_SUM256"
    echo "$NOW_SUM256"
}

# 创建发布
create_github_release() {
    local PLATFORM="$1"
    local VERSION="$2"
    local VERSION_TAG="$3"
    local ASSET_PATH="$4"
    local SHA256_FILE="$5"
    local NOW_SUM256="$6"
    
    echo_color "yellow" "创建 GitHub 发布"
    
    # 发布说明
    local RELEASE_NOTES="Platform: $PLATFORM\nVersion: $VERSION\nSHA256: $NOW_SUM256\nUpdate Time: $(date -u '+%Y-%m-%d %H:%M:%S') (UTC)"
    
    # 创建发布
    gh release create "v$VERSION_TAG" "$ASSET_PATH" \
        -F "$SHA256_FILE" \
        -t "WeChat $PLATFORM v$VERSION_TAG" \
        -n "$RELEASE_NOTES" || {
            echo_color "red" "创建发布失败"
            exit 1
        }
}

# 获取最新发布信息
get_latest_release_info() {
    local PLATFORM="$1"
    local SUFFIX="$2"
    
    echo_color "yellow" "获取 GitHub 最新发布信息"
    
    check_github_auth
    
    # 筛选最新发布版本
    local FILTERED_RELEASE=$(gh release list --limit 20 2>/dev/null | grep "$PLATFORM" | grep -E "\\-${SUFFIX}[[:space:]]" | head -1 || true)
    
    if [ -n "$FILTERED_RELEASE" ]; then
        local VERSION=$(echo "$FILTERED_RELEASE" | awk '{print $4}' | sed 's/^v//' )
        local SUM256=$(gh release view "v$VERSION" --json body --jq ".body" | grep 'Sha256:' | awk -F': ' '{print $2}' || echo "")
        echo "$VERSION:$SUM256"
    else
        echo ""
    fi
}
