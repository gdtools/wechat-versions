#!/usr/bin/env bash

set -eo pipefail

# ====================================================
# 配置变量
# ====================================================
TEMP_PATH="WeChatWin/temp"
LATEST_PATH="WeChatWin/latest"
DOWNLOAD_LINK="$1"
DEFAULT_DOWNLOAD_LINK="https://dldir1v6.qq.com/weixin/Universal/Windows/WeChatWin.exe"

if [ -z "$1" ]; then
    echo_color "yellow" "Missing argument. Using default download link."
    DOWNLOAD_LINK="$DEFAULT_DOWNLOAD_LINK"
fi

# ====================================================
# 函数定义
# ====================================================

# 打印分隔线
print_separator() {
    printf '%*s\n' 60 | tr ' ' '#'
}

# 彩色输出函数
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

# 安装依赖项
install_depends() {
    print_separator
    echo_color "yellow" "Installing dependencies: 7zip, shasum, wget, curl, git"
    print_separator

    brew install p7zip wget curl git
}

# 下载 WeChat 安装包
download_wechat() {
    print_separator
    echo_color "yellow" "Downloading the newest WeChatWin..."
    print_separator

    mkdir -p "$TEMP_PATH"
    wget -q "$DOWNLOAD_LINK" -O "${TEMP_PATH}/WeChatWin.exe"
    if [ "$?" -ne 0 ]; then
        echo_color "red" "Download Failed, please check your network!"
        clean_data 1
    fi
}

# 提取版本信息
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
    DEST_VERSION=$(ls -l "${TEMP_PATH}/temp/install" | awk '{print $9}' | grep '^[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*$')

    if [ -z "$DEST_VERSION" ]; then
        echo_color "red" "Failed to extract version information!"
        clean_data 1
    fi
}

# 计算 SHA256
compute_sha256() {
    local file_path="$1"
    shasum -a 256 "$file_path" | awk '{print $1}'
}

# 准备提交（复制文件并生成 SHA256）
prepare_commit() {
    print_separator
    echo_color "yellow" "Preparing to commit new version..."
    print_separator

    VERSION_DIR="WeChatWin/$DEST_VERSION"
    mkdir -p "$VERSION_DIR"
    cp "${TEMP_PATH}/WeChatWin.exe" "$VERSION_DIR/WeChatWin-$DEST_VERSION.exe"

    NOW_SUM256=$(compute_sha256 "$VERSION_DIR/WeChatWin-$DEST_VERSION.exe")

    cat > "$VERSION_DIR/WeChatWin-$DEST_VERSION.exe.sha256" <<EOF
DestVersion: $DEST_VERSION
Sha256: $NOW_SUM256
UpdateTime: $(date -u '+%Y-%m-%d %H:%M:%S') (UTC)
DownloadFrom: $DOWNLOAD_LINK
EOF

    echo_color "green" "SHA256: $NOW_SUM256"
}

# 获取最新 GitHub Release 信息
get_latest_release_info() {
    print_separator
    echo_color "yellow" "Getting latest GitHub release info..."
    print_separator

    LATEST_BODY=$(gh release view --json body --jq ".body" || true)

    if [ -z "$LATEST_BODY" ]; then
        LATEST_SUM256=""
        LATEST_VERSION=""
    else
        LATEST_SUM256=$(echo "$LATEST_BODY" | grep 'Sha256:' | awk -F': ' '{print $2}')
        LATEST_VERSION=$(echo "$LATEST_BODY" | grep 'DestVersion:' | awk -F': ' '{print $2}')
    fi

    echo_color "green" "Latest Version: $LATEST_VERSION"
    echo_color "green" "Latest SHA256: $LATEST_SUM256"
}

# 创建新的 GitHub Release
create_release() {
    print_separator
    echo_color "yellow" "Creating new GitHub release..."
    print_separator

    if [ "$DEST_VERSION" = "$LATEST_VERSION" ]; then
        VERSION_TAG="${DEST_VERSION}_win_$(date -u '+%Y%m%d')"
    else
        VERSION_TAG="$DEST_VERSION"
    fi

    gh release create "v$VERSION_TAG" "WeChatWin/$DEST_VERSION/WeChatWin-$DEST_VERSION.exe" \
        -F "WeChatWin/$DEST_VERSION/WeChatWin-$DEST_VERSION.exe.sha256" \
        -t "Wechat For Windows v$VERSION_TAG"
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
    mkdir -p "$TEMP_PATH"
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
