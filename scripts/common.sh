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
    
    echo_color "yellow" "准备文件并计算哈希值"
    
    # 验证源文件存在且可读
    if [ ! -f "$SOURCE_FILE" ] || [ ! -r "$SOURCE_FILE" ]; then
        echo_color "red" "源文件不存在或无法读取: $SOURCE_FILE"
        exit 1
    fi
    
    # 验证文件大小
    local FILE_SIZE=$(stat -f%z "$SOURCE_FILE")
    if [ "$FILE_SIZE" -lt 1000000 ]; then # 小于1MB
        echo_color "red" "文件大小异常（小于1MB）: $FILE_SIZE bytes"
        exit 1
    fi
    
    # 验证目标目录权限
    if ! mkdir -p "$TARGET_DIR" 2>/dev/null; then
        echo_color "red" "无法创建目标目录: $TARGET_DIR"
        exit 1
    fi
    
    if [ ! -w "$TARGET_DIR" ]; then
        echo_color "red" "目标目录无写入权限: $TARGET_DIR"
        exit 1
    fi
    
    # 计算 SHA256
    local NOW_SUM256
    NOW_SUM256=$(shasum -a 256 "$SOURCE_FILE" | awk '{print $1}') || {
        echo_color "red" "计算哈希值失败"
        exit 1
    }
    
    # 验证哈希值格式
    if ! echo "$NOW_SUM256" | grep -qE '^[a-fA-F0-9]{64}$'; then
        echo_color "red" "生成的哈希值格式不正确: $NOW_SUM256"
        exit 1
    fi
    
    echo_color "yellow" "文件大小: $FILE_SIZE bytes"
    
    # 创建 SHA256 文件
    if ! cat > "${SOURCE_FILE}.sha256" <<EOF
DestVersion: $VERSION
Sha256: $NOW_SUM256
FileSize: $FILE_SIZE
UpdateTime: $(date -u '+%Y-%m-%d %H:%M:%S') (UTC)
DownloadFrom: $DOWNLOAD_URL
EOF
    then
        echo_color "red" "创建 SHA256 文件失败"
        exit 1
    fi

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
    
    # 使用 jq 解析 JSON 输出，获取最新的符合条件的发布
    local latest_release_info=$(gh release list --json 'tagName,body' --limit 100 2>/dev/null | \
        jq -r ".[] | select(.tagName | test(\"${SUFFIX}$|${SUFFIX}_[0-9]+$\")) | {tagName: .tagName, body: .body}" | \
        jq -s 'sort_by(.tagName) | reverse | .[0]')
    
    if [ -n "$latest_release_info" ] && [ "$latest_release_info" != "null" ]; then
        # 从 body 中提取 SHA256
        local VERSION=$(echo "$latest_release_info" | jq -r '.tagName' | sed 's/^v//')
        local SUM256=$(echo "$latest_release_info" | jq -r '.body' | grep -i 'Sha256:' | awk -F': ' '{print $2}' | tr -d '\r\n')
        
        if [ -n "$VERSION" ] && [ -n "$SUM256" ]; then
            echo_color "yellow" "找到最新版本: $VERSION"
            echo_color "yellow" "最新版本哈希值: $SUM256"
            echo "$VERSION:$SUM256"
            return 0
        fi
    fi
    
    echo_color "yellow" "未找到符合条件的发布版本"
    echo ""
}
