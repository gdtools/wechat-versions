#!/usr/bin/env bash

set -eo pipefail

# ====================================================
# 配置变量
# ====================================================
TEMP_PATH="WeChatMac"
PLATFORM="For Mac"
WEBSITE_URL="https://mac.weixin.qq.com/?t=mac&lang=zh_CN"
VERSION=""
NOW_SUM256=""
LATEST_SUM256=""
LATEST_VERSION=""

# ====================================================
# 函数定义
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

# 安装依赖
install_depends() {
    echo_color "yellow" "检查依赖: wget, curl, git, gh, pup"
    
    local missing_deps=()
    for cmd in wget curl git gh pup; do
        command -v $cmd >/dev/null 2>&1 || missing_deps+=($cmd)
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo_color "yellow" "安装缺失依赖: ${missing_deps[*]}"
        brew install "${missing_deps[@]}"
    else
        echo_color "green" "所有依赖已安装"
    fi
}

# 下载 WeChat DMG
download_wechat() {
    echo_color "yellow" "下载最新版 WeChatMac"
    
    # 创建临时目录
    mkdir -p "$TEMP_PATH/temp"
    
    # 获取下载链接
    DOWNLOAD_LINK=$(curl -s "$WEBSITE_URL" | pup 'a.download-button:nth-of-type(1) attr{href}')
    
    if [ -z "$DOWNLOAD_LINK" ]; then
        echo_color "red" "无法获取下载链接"
        exit 1
    fi
    
    # 下载 DMG 文件
    wget -q --continue "$DOWNLOAD_LINK" -O "${TEMP_PATH}/temp/WeChatMac.dmg" || {
        echo_color "red" "下载失败，请检查网络连接"
        exit 1
    }
    
    echo_color "green" "下载完成: ${TEMP_PATH}/temp/WeChatMac.dmg"
}

# 提取版本信息
extract_version() {
    echo_color "yellow" "提取 WeChat 版本信息"
    
    # 挂载 DMG 文件
    MOUNT_DIR=$(hdiutil attach "${TEMP_PATH}/temp/WeChatMac.dmg" -nobrowse | sed -n 's/^.*\(\/Volumes\/.*\)$/\1/p' | tail -n1)
    
    if [ -z "$MOUNT_DIR" ]; then
        echo_color "red" "挂载 DMG 文件失败"
        exit 1
    fi
    
    # 定位 WeChat 二进制文件
    WECHAT_BINARY="${MOUNT_DIR}/WeChat.app/Contents/MacOS/WeChat"
    
    if [ ! -f "$WECHAT_BINARY" ]; then
        echo_color "red" "未找到 WeChat 二进制文件"
        hdiutil detach "$MOUNT_DIR" &>/dev/null || true
        exit 1
    fi
    
    # 提取版本号
    VERSION=$(strings "$WECHAT_BINARY" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort | uniq -c | sort -rn | head -n 1 | awk '{print $2}')
    
    # 卸载 DMG
    hdiutil detach "$MOUNT_DIR" &>/dev/null || {
        echo_color "yellow" "卸载 DMG 时出现警告，继续执行"
    }
    
    if [ -z "$VERSION" ]; then
        echo_color "red" "无法提取版本信息"
        exit 1
    fi
    
    echo_color "green" "提取到版本号: $VERSION"
}

# 准备文件并计算 SHA256
prepare_files() {
    echo_color "yellow" "准备文件"
    
    VERSION_DIR="WeChatMac/$VERSION"
    mkdir -p "$VERSION_DIR"
    
    # 复制到版本目录
    cp "${TEMP_PATH}/temp/WeChatMac.dmg" "$VERSION_DIR/WeChatMac-$VERSION.dmg"
    
    # 计算 SHA256
    NOW_SUM256=$(shasum -a 256 "$VERSION_DIR/WeChatMac-$VERSION.dmg" | awk '{print $1}')
    
    # 创建 SHA256 文件
    cat > "$VERSION_DIR/WeChatMac-$VERSION.dmg.sha256" <<EOF
DestVersion: $VERSION
Sha256: $NOW_SUM256
UpdateTime: $(date -u '+%Y-%m-%d %H:%M:%S') (UTC)
DownloadFrom: $DOWNLOAD_LINK
EOF

    echo_color "green" "SHA256: $NOW_SUM256"
}

# 获取 GitHub 最新发布信息
get_release_info() {
    echo_color "yellow" "获取 GitHub 最新发布信息"
    
    # 检查 GitHub CLI 登录状态
    gh auth status &>/dev/null || {
        echo_color "red" "GitHub CLI 未登录，请先运行 'gh auth login'"
        exit 1
    }
    
    # 筛选最新发布版本（tag 以 -mac 结尾）
    FILTERED_RELEASE=$(gh release list --limit 20 2>/dev/null | grep "$PLATFORM" | grep -E '\-mac[[:space:]]' | head -1 || true)
    
    if [ -n "$FILTERED_RELEASE" ]; then
        LATEST_VERSION=$(echo "$FILTERED_RELEASE" | awk '{print $4}' | sed 's/^v//' )
        LATEST_SUM256=$(gh release view "v$LATEST_VERSION" --json body --jq ".body" | grep 'Sha256:' | awk -F': ' '{print $2}' || echo "")
    fi
}

# 创建发布
create_release() {
    echo_color "yellow" "创建 GitHub 发布"
    
    # 处理版本冲突
    local VERSION_TAG="${VERSION}-mac"
    if [ "${VERSION}-mac" = "$LATEST_VERSION" ]; then
        VERSION_TAG="${VERSION}-mac_$(date -u '+%Y%m%d%H%M%S')"
    fi
    
    # 发布说明
    local RELEASE_NOTES="Platform: $PLATFORM\nVersion: $VERSION\nSHA256: $NOW_SUM256\nUpdate Time: $(date -u '+%Y-%m-%d %H:%M:%S') (UTC)"
    
    # 创建发布
    gh release create "v$VERSION_TAG" "$VERSION_DIR/WeChatMac-$VERSION.dmg" \
        -F "$VERSION_DIR/WeChatMac-$VERSION.dmg.sha256" \
        -t "WeChat $PLATFORM v$VERSION_TAG" \
        -n "$RELEASE_NOTES" || {
            echo_color "red" "创建发布失败"
            exit 1
        }
}

# 清理临时文件
clean_temp() {
    echo_color "yellow" "清理临时文件"
    rm -rf "${TEMP_PATH}/temp"
}

# ====================================================
# 主流程
# ====================================================
main() {
    echo_color "green" "启动 WeChatMac 版本检测脚本"
    
    # 捕获中断信号
    trap "echo_color red '脚本被用户中断'; exit 130" INT
    
    install_depends
    download_wechat
    extract_version
    prepare_files
    get_release_info
    
    # 检查是否需要更新
    if [ "$NOW_SUM256" = "$LATEST_SUM256" ] && [ -n "$LATEST_SUM256" ]; then
        echo_color "green" "当前已是最新版本，无需更新"
    else
        echo_color "yellow" "检测到新版本，创建发布..."
        create_release
        echo_color "green" "版本 $VERSION 发布成功"
    fi
    
    clean_temp
}

main
