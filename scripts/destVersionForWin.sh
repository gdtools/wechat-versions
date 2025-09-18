#!/usr/bin/env bash

set -eo pipefail

# 导入公共函数
source "$(dirname "$0")/common.sh"

# ====================================================
# 配置变量
# ====================================================
TEMP_PATH="WeChatWin"
PLATFORM="For Windows"
WEBSITE_URL="https://dldir1v6.qq.com/weixin/Windows/WeChatSetup.exe"
VERSION=""
NOW_SUM256=""
LATEST_SUM256=""
LATEST_VERSION=""

# ====================================================
# 函数定义
# ====================================================

# 安装依赖
install_depends() {
    echo_color "yellow" "检查依赖: 7zip, wget, curl, git, gh"
    
    local missing_deps=()
    for cmd in 7z wget curl git gh; do
        command -v $cmd >/dev/null 2>&1 || missing_deps+=($cmd)
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo_color "yellow" "安装缺失依赖: ${missing_deps[*]}"
        brew install "${missing_deps[@]}"
    else
        echo_color "green" "所有依赖已安装"
    fi
}

# 下载并解压 WeChatWin
download_wechat() {
    echo_color "yellow" "下载最新版 WeChatWin"

    mkdir -p "$TEMP_PATH/temp"
    wget -q --continue "$WEBSITE_URL" -O "${TEMP_PATH}/temp/WeChatWin.exe" || {
        echo_color "red" "下载失败，请检查网络连接"
        exit 1
    }
    
    echo_color "yellow" "解压并提取版本信息"
    
    # 第一次解压获取 install.7z
    7z x "${TEMP_PATH}/temp/WeChatWin.exe" -o"${TEMP_PATH}/temp" >/dev/null || {
        echo_color "red" "解压 WeChatWin.exe 失败"
        exit 1
    }
    
    # 第二次解压获取版本号文件夹
    7z x "${TEMP_PATH}/temp/install.7z" -o"${TEMP_PATH}/temp/install" >/dev/null || {
        echo_color "red" "解压 install.7z 失败"
        exit 1
    }
    
    # 提取版本号
    VERSION=$(ls -l "${TEMP_PATH}/temp/install" | awk '{print $9}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    
    if [ -z "$VERSION" ]; then
        echo_color "red" "无法提取版本信息"
        exit 1
    fi
    
    echo_color "green" "提取到版本号: $VERSION"
}

# ====================================================
# 主流程
# ====================================================
main() {
    echo_color "green" "启动 WeChatWin 版本检测脚本"
    
    # 捕获中断信号
    trap "echo_color red '脚本被用户中断'; exit 130" INT
    
    install_depends
    download_wechat
    
    # 准备文件
    VERSION_DIR="WeChatWin/$VERSION"
    SOURCE_FILE="${TEMP_PATH}/temp/WeChatWin.exe"
    TARGET_FILE="$VERSION_DIR/WeChatWin-$VERSION.exe"
    
    # 移动文件到版本目录
    mkdir -p "$VERSION_DIR"
    cp "$SOURCE_FILE" "$TARGET_FILE"
    
    # 计算 SHA256 并准备发布文件
    NOW_SUM256=$(prepare_files "$PLATFORM" "$VERSION" "$TARGET_FILE" "$VERSION_DIR" "$WEBSITE_URL")
    
    # 获取最新发布信息
    RELEASE_INFO=$(get_latest_release_info "$PLATFORM" "win")
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
        VERSION_TAG="${VERSION}-win"
        if [ "${VERSION}-win" = "$LATEST_VERSION" ]; then
            VERSION_TAG="${VERSION}-win_$(date -u '+%Y%m%d%H%M%S')"
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
