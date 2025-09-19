#!/usr/bin/env bash

set -eo pipefail

# 导入公共函数
source "$(dirname "$0")/common.sh"

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

# 安装依赖
install_depends() {
    echo_color "yellow" "检查依赖: wget, curl, git, gh"
    
    local missing_deps=()
    for cmd in wget curl git gh; do
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
    DOWNLOAD_LINK=$(curl -s "$WEBSITE_URL" | grep -o 'https://[^"]*\.dmg' | head -n 1)
    
    if [ -z "$DOWNLOAD_LINK" ]; then
        echo_color "red" "无法获取下载链接"
        exit 1
    fi
    
    # 验证下载链接
    if ! echo "$DOWNLOAD_LINK" | grep -q "^https://.*\.dmg$"; then
        echo_color "red" "获取到的下载链接格式不正确"
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
    # 从 Info.plist 获取版本号
    local INFO_PLIST="${MOUNT_DIR}/WeChat.app/Contents/Info.plist"
    if [ -f "$INFO_PLIST" ]; then
        # 优先使用 WeChatBundleVersion
        VERSION=$(/usr/libexec/PlistBuddy -c "Print :WeChatBundleVersion" "$INFO_PLIST" 2>/dev/null || true)
        
        # 如果获取失败，尝试 CFBundleShortVersionString
        if [ -z "$VERSION" ]; then
            VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || true)
        fi
        
        # 输出调试信息
        if [ "${DEBUG:-}" = "1" ]; then
            echo_color "yellow" "正在从 Info.plist 获取版本号"
            echo_color "yellow" "WeChatBundleVersion: $(/usr/libexec/PlistBuddy -c "Print :WeChatBundleVersion" "$INFO_PLIST" 2>/dev/null || echo "未找到")"
            echo_color "yellow" "CFBundleShortVersionString: $(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "未找到")"
        fi
    fi
    
    # 卸载 DMG
    hdiutil detach "$MOUNT_DIR" &>/dev/null || {
        echo_color "yellow" "卸载 DMG 时出现警告，继续执行"
    }
    
    if [ -z "$VERSION" ] || ! validate_version "$VERSION"; then
        echo_color "red" "无法提取有效的版本信息"
        echo_color "red" "当前提取到的版本号: ${VERSION:-未找到}"
        exit 1
    fi
    
    echo_color "green" "提取到版本号: $VERSION"
    
    # 显示二进制文件中的所有版本号（用于调试）
    if [ "${DEBUG:-}" = "1" ]; then
        echo_color "yellow" "二进制文件中的所有版本号:"
        strings "$WECHAT_BINARY" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -V
    fi
}

# 验证版本号格式
validate_version() {
    local ver="$1"
    
    # 检查版本号格式 (x.x.x.xx)
    if ! echo "$ver" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        return 1
    fi
    
    # 解析版本号各个部分
    local major_ver=$(echo "$ver" | cut -d. -f1)
    local minor_ver=$(echo "$ver" | cut -d. -f2)
    local patch_ver=$(echo "$ver" | cut -d. -f3)
    local build_ver=$(echo "$ver" | cut -d. -f4)
    
    # WeChat 版本号通常在这个范围内
    if [ "$major_ver" -lt 1 ] || [ "$major_ver" -gt 9 ] || \
       [ "$minor_ver" -lt 0 ] || [ "$minor_ver" -gt 99 ] || \
       [ "$patch_ver" -lt 0 ] || [ "$patch_ver" -gt 99 ] || \
       [ "$build_ver" -lt 0 ] || [ "$build_ver" -gt 99 ]; then
        return 1
    fi
    
    # 排除特殊版本号
    if echo "$ver" | grep -qE '^(0\.|127\.|255\.)'; then
        return 1
    fi
    
    return 0
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
    
    # 准备文件
    VERSION_DIR="WeChatMac/$VERSION"
    SOURCE_FILE="${TEMP_PATH}/temp/WeChatMac.dmg"
    TARGET_FILE="$VERSION_DIR/WeChatMac-$VERSION.dmg"
    
    # 移动文件到版本目录
    mkdir -p "$VERSION_DIR"
    cp "$SOURCE_FILE" "$TARGET_FILE"
    
    # 计算 SHA256 并准备发布文件
    NOW_SUM256=$(prepare_files "$PLATFORM" "$VERSION" "$TARGET_FILE" "$VERSION_DIR" "$DOWNLOAD_LINK")
    
    # 获取最新发布信息
    RELEASE_INFO=$(get_latest_release_info "$PLATFORM" "mac")
    if [ -n "$RELEASE_INFO" ]; then
        LATEST_VERSION=$(echo "$RELEASE_INFO" | cut -d':' -f1)
        LATEST_SUM256=$(echo "$RELEASE_INFO" | cut -d':' -f2)
    fi
    
    # 检查是否需要更新
    if [ "$NOW_SUM256" = "$LATEST_SUM256" ] && [ -n "$LATEST_SUM256" ]; then
        echo_color "green" "当前已是最新版本，无需更新"
    else
        echo_color "yellow" "检测到新版本，创建发布..."
        
        # 处理版本冲突
        VERSION_TAG="${VERSION}-mac"
        if [ "${VERSION}-mac" = "$LATEST_VERSION" ]; then
            VERSION_TAG="${VERSION}-mac_$(date -u '+%Y%m%d%H%M%S')"
        fi
        
        # 创建发布
        create_github_release "$PLATFORM" "$VERSION" "$VERSION_TAG" \
            "$TARGET_FILE" \
            "$TARGET_FILE.sha256" \
            "$NOW_SUM256"
            
        echo_color "green" "版本 $VERSION 发布成功"
    fi
    
    # 清理临时文件
    echo_color "yellow" "清理临时文件"
    rm -rf "${TEMP_PATH}/temp"
}

main
