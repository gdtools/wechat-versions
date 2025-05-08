#!/usr/bin/env bash

set -eo pipefail

# ====================================================
# 配置变量
# ====================================================
TEMP_PATH="WeChatWin"
PLATFORM="For Windows"
WEBSITE_URL="https://dldir1v6.qq.com/weixin/Universal/Windows/WeChatWin.exe"
DOWNLOAD_LINK=""
VERSION=""
NOW_SUM256=""
LATEST_SUM256=""
LATEST_VERSION=""

# ====================================================
# 函数定义
# ====================================================

# 打印分隔线
print_separator() {
    printf '%*s\n' 60 | tr ' ' '#'
}

# 彩色输出
echo_color() {
    local color="$1"
    shift
    local message="$*"
    case "$color" in
        yellow)
            echo -e "\033[1;33m$message\033[0m"
            ;;
        red)
            echo -e "\033[1;31m$message\033[0m" >&2
            ;;
        green)
            echo -e "\033[1;32m$message\033[0m"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# 安装依赖
install_depends() {
    print_separator
    echo_color "yellow" "Installing dependencies: 7zip, wget, curl, git"
    print_separator
    brew install p7zip wget curl git
}

# 下载 WeChatWin
download_wechat() {
    print_separator
    echo_color "yellow" "Downloading the newest WeChatWin..."
    print_separator

    mkdir -p "$TEMP_PATH"
    wget -q "$WEBSITE_URL" -O "${TEMP_PATH}/WeChatWin.exe"
    if [ "$?" -ne 0 ]; then
        echo_color "red" "Download Failed, please check your network!"
        clean_data 1
    fi
}

# 解压并提取版本
extract_version() {
    print_separator
    echo_color "yellow" "Extracting version from WeChatWin..."
    print_separator

    # 第一次解压，得到 install.7z
    7z x "${TEMP_PATH}/WeChatWin.exe" -o"${TEMP_PATH}/temp"
    if [ ! -f "${TEMP_PATH}/temp/install.7z" ]; then
        echo_color "red" "Failed to extract install.7z!"
        clean_data 1
    fi

    # 第二次解压，得到带版本号的文件夹
    7z x "${TEMP_PATH}/temp/install.7z" -o"${TEMP_PATH}/temp/install"
    VERSION=$(ls -l "${TEMP_PATH}/temp/install" | awk '{print $9}' | grep '^[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*$')

    if [ -z "$VERSION" ]; then
        echo_color "red" "Failed to extract version information!"
        clean_data 1
    fi
}

# 计算 SHA256
compute_sha256() {
    local file_path="$1"
    shasum -a 256 "$file_path" | awk '{print $1}'
}

# 准备提交
prepare_commit() {
    print_separator
    echo_color "yellow" "Preparing to commit new version..."
    print_separator

    VERSION_DIR="WeChatWin/$VERSION"
    mkdir -p "$VERSION_DIR"
    cp "${TEMP_PATH}/WeChatWin.exe" "$VERSION_DIR/WeChatWin-$VERSION.exe"

    NOW_SUM256=$(compute_sha256 "$VERSION_DIR/WeChatWin-$VERSION.exe")

    cat > "$VERSION_DIR/WeChatWin-$VERSION.exe.sha256" <<EOF
DestVersion: $VERSION
Sha256: $NOW_SUM256
UpdateTime: $(date -u '+%Y-%m-%d %H:%M:%S') (UTC)
DownloadFrom: $WEBSITE_URL
EOF

    echo_color "green" "SHA256: $NOW_SUM256"
}

# 获取最新 Release 信息
get_latest_release_info() {
    print_separator
    echo_color "yellow" "Getting latest GitHub release info for platform: $PLATFORM..."
    print_separator

    # 获取所有的 release 信息
    RELEASES=$(gh release list --limit 100 || true)

    # 根据平台筛选 release
    FILTERED_RELEASE=$(echo "$RELEASES" | grep "$PLATFORM" || true)

    if [ -z "$FILTERED_RELEASE" ]; then
        LATEST_SUM256=""
        LATEST_VERSION=""
    else
        # 提取最新的版本信息（根据你的 release 格式调整解析）
        LATEST_VERSION=$(echo "$FILTERED_RELEASE" | awk '{print $1}' | sed 's/^v//')
        LATEST_SUM256=$(gh release view "v$LATEST_VERSION" --json body --jq ".body" | grep 'Sha256:' | awk -F': ' '{print $2}')
    fi

    echo_color "green" "Latest Version for $PLATFORM: $LATEST_VERSION"
    echo_color "green" "Latest SHA256 for $PLATFORM: $LATEST_SUM256"
}

# 创建新的 Release
create_release() {
    print_separator
    echo_color "yellow" "Creating new GitHub release for platform: $PLATFORM..."
    print_separator

    # 检查是否版本号冲突
    if [ "$VERSION" = "$LATEST_VERSION" ]; then
        # 如果版本冲突，生成带时间戳的 Tag
        VERSION_TAG="${VERSION}_${PLATFORM}_$(date -u '+%Y%m%d%H%M%S')"
        echo_color "yellow" "Version already exists for $PLATFORM. Using new tag: v$VERSION_TAG"
    else
        VERSION_TAG="$VERSION"
    fi

    # 尝试创建 Release
    gh release create "v$VERSION_TAG" "WeChatWin/$VERSION/WeChatWin-$VERSION.exe" \
        -F "WeChatWin/$VERSION/WeChatWin-$VERSION.exe.sha256" \
        -t "Wechat For Windows v$VERSION_TAG" \
        -n "Platform: $PLATFORM" || {
            echo_color "red" "Failed to create release. Tag v$VERSION_TAG might already exist."
            clean_data 1
        }
}

# 清理临时数据并退出
clean_data() {
    print_separator
    echo_color "yellow" "Cleaning runtime and exiting..."
    print_separator

    rm -rfv "WeChatWin"
    exit "$1"
}

# ====================================================
# 主流程
# ====================================================
main() {
    install_depends
    download_wechat
    extract_version
    prepare_commit
    get_latest_release_info

    if [ "$NOW_SUM256" = "$LATEST_SUM256" ] && [ -n "$LATEST_SUM256" ]; then
        echo_color "green" "This is the newest Version!"
        clean_data 0
    fi

    create_release
    clean_data 0
}

main
