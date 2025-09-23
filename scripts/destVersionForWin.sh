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

    # 创建临时目录并清理旧文件
    rm -rf "$TEMP_PATH/temp"
    mkdir -p "$TEMP_PATH/temp"
    
    local download_url="$WEBSITE_URL"
    if [ -n "$1" ]; then
        download_url="$1"
    fi

    echo_color "yellow" "正在从 $download_url 下载..."
    
    # 使用 curl 替代 wget，添加更多的错误处理
    if ! curl -L --retry 3 --retry-delay 5 -o "${TEMP_PATH}/temp/WeChatWin.exe" "$download_url"; then
        echo_color "red" "下载失败，请检查网络连接和下载链接"
        exit 1
    fi
    
    if [ ! -s "${TEMP_PATH}/temp/WeChatWin.exe" ]; then
        echo_color "red" "下载的文件为空"
        exit 1
    fi
    
    echo_color "yellow" "解压并提取版本信息"
    
    # 列出安装包内容
    if ! 7z l "${TEMP_PATH}/temp/WeChatWin.exe" > "${TEMP_PATH}/temp/7z_list.log" 2>&1; then
        echo_color "red" "无法读取 WeChatWin.exe 内容，日志:"
        cat "${TEMP_PATH}/temp/7z_list.log"
        exit 1
    fi
    
    # 从安装包内容中提取版本号
    VERSION=$(grep -o '\[[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+\]' "${TEMP_PATH}/temp/7z_list.log" | head -1 | tr -d '[]')
    
    if [ -z "$VERSION" ]; then
        # 尝试从文件版本信息中提取
        VERSION=$(grep "FileVersion:" "${TEMP_PATH}/temp/7z_list.log" | head -1 | awk -F': ' '{print $2}' | tr -d '\r')
        
        if [ -z "$VERSION" ]; then
            echo_color "red" "无法提取版本信息，安装包内容:"
            cat "${TEMP_PATH}/temp/7z_list.log"
            exit 1
        fi
    fi
    
    # 提取主程序文件
    echo_color "yellow" "提取版本 $VERSION 的主程序"
    
    mkdir -p "${TEMP_PATH}/temp/extracted"
    
    # 先检查文件是否存在且大小合适
    if [ ! -f "${TEMP_PATH}/temp/WeChatWin.exe" ] || [ ! -s "${TEMP_PATH}/temp/WeChatWin.exe" ]; then
        echo_color "red" "安装包文件不存在或为空"
        exit 1
    fi
    
    # 首先尝试带方括号的版本目录
    EXTRACT_PATH="\[${VERSION}\]/*"
    if ! 7z x -y "${TEMP_PATH}/temp/WeChatWin.exe" -o"${TEMP_PATH}/temp/extracted" "$EXTRACT_PATH" > "${TEMP_PATH}/temp/7z_extract.log" 2>&1; then
        echo_color "yellow" "尝试不带方括号的版本目录..."
        EXTRACT_PATH="${VERSION}/*"
        if ! 7z x -y "${TEMP_PATH}/temp/WeChatWin.exe" -o"${TEMP_PATH}/temp/extracted" "$EXTRACT_PATH" > "${TEMP_PATH}/temp/7z_extract.log" 2>&1; then
            echo_color "yellow" "尝试完整解压..."
            if ! 7z x -y "${TEMP_PATH}/temp/WeChatWin.exe" -o"${TEMP_PATH}/temp/extracted" > "${TEMP_PATH}/temp/7z_extract.log" 2>&1; then
                echo_color "red" "提取文件失败，日志:"
                cat "${TEMP_PATH}/temp/7z_extract.log"
                exit 1
            fi
        fi
    fi
    
    # 验证文件是否成功提取
    if [ ! -d "${TEMP_PATH}/temp/extracted/[${VERSION}]" ] && [ ! -d "${TEMP_PATH}/temp/extracted/${VERSION}" ]; then
        echo_color "yellow" "警告：未找到版本目录，显示提取的文件列表:"
        ls -la "${TEMP_PATH}/temp/extracted/"
    fi
    
    if [ -z "$VERSION" ]; then
        echo_color "red" "无法提取版本信息，目录内容:"
        ls -la "${TEMP_PATH}/temp/install/"
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
    
    # 复制版本文件列表
    echo "Files included in version $VERSION:" > "$VERSION_DIR/files_list.txt"
    7z l "${TEMP_PATH}/temp/WeChatWin.exe" | grep "\[${VERSION}\]/" >> "$VERSION_DIR/files_list.txt"
    
    # 计算 SHA256 并准备发布文件
    NOW_SUM256=$(prepare_files "$PLATFORM" "$VERSION" "$TARGET_FILE" "$VERSION_DIR" "$WEBSITE_URL")
    
    # 获取最新发布信息
    RELEASE_INFO=$(get_latest_release_info "$PLATFORM" "win")
    if [ -n "$RELEASE_INFO" ]; then
        LATEST_VERSION=$(echo "$RELEASE_INFO" | cut -d':' -f1)
        LATEST_SUM256=$(echo "$RELEASE_INFO" | cut -d':' -f2)
    fi
    
    # 获取当前日期时间
    CURRENT_DATE=$(date -u '+%Y%m%d')
    
    # 检查版本更新和哈希值
    if [ "${VERSION}-win" = "$LATEST_VERSION" ]; then
        if [ "$NOW_SUM256" = "$LATEST_SUM256" ]; then
            echo_color "green" "当前版本哈希值一致，无需更新"
            exit 0
        else
            echo_color "yellow" "检测到相同版本号但哈希值不同，进行额外验证..."
            
            # 记录文件大小
            local FILE_SIZE=$(stat -f%z "$TARGET_FILE")
            echo_color "yellow" "当前文件大小: $FILE_SIZE bytes"
            
            # 二次下载验证
            local TEMP_FILE="${TEMP_PATH}/temp/WeChatWin_verify.exe"
            echo_color "yellow" "开始二次下载验证..."
            if ! curl -L --retry 3 --retry-delay 5 -o "$TEMP_FILE" "$WEBSITE_URL"; then
                echo_color "red" "二次下载验证失败"
                exit 1
            fi
            
            # 计算二次下载文件的哈希值
            local VERIFY_SUM256=$(shasum -a 256 "$TEMP_FILE" | awk '{print $1}')
            
            # 比较两次下载的哈希值
            if [ "$NOW_SUM256" = "$VERIFY_SUM256" ]; then
                echo_color "yellow" "二次验证成功，哈希值一致，准备创建新发布..."
                VERSION_TAG="${VERSION}-win_${CURRENT_DATE}"
                
                # 创建一个 issue 来通知管理员
                gh issue create \
                    --title "检测到相同版本号但哈希值变化 [${VERSION}-win]" \
                    --body "**版本信息**
- 版本号: ${VERSION}-win
- 原始哈希值: ${LATEST_SUM256}
- 新哈希值: ${NOW_SUM256}
- 文件大小: ${FILE_SIZE} bytes
- 下载链接: ${WEBSITE_URL}
- 时间: $(date -u '+%Y-%m-%d %H:%M:%S') UTC

二次下载验证已通过，新旧哈希值不同，可能是官方更新了安装包。" || echo_color "yellow" "Issue 创建失败，继续执行..."
            else
                echo_color "red" "二次验证失败，两次下载的哈希值不一致"
                echo_color "red" "首次: $NOW_SUM256"
                echo_color "red" "二次: $VERIFY_SUM256"
                exit 1
            fi
            
            # 检查是否已存在当天的发布
            local try_count=1
            while gh release view "v${VERSION_TAG}" &>/dev/null; do
                VERSION_TAG="${VERSION}-win_${CURRENT_DATE}_${try_count}"
                try_count=$((try_count + 1))
            done
        fi
    else
        echo_color "yellow" "检测到新版本，创建发布..."
        VERSION_TAG="${VERSION}-win"
        
        # 检查标签是否已存在
        if gh release view "v${VERSION_TAG}" &>/dev/null; then
            echo_color "yellow" "发布标签已存在，添加日期后缀..."
            VERSION_TAG="${VERSION}-win_${CURRENT_DATE}"
            
            # 检查是否已存在当天的发布
            local try_count=1
            while gh release view "v${VERSION_TAG}" &>/dev/null; do
                VERSION_TAG="${VERSION}-win_${CURRENT_DATE}_${try_count}"
                try_count=$((try_count + 1))
            done
        fi
    fi
    
    echo_color "green" "使用发布标签: v${VERSION_TAG}"
    
    # 创建发布
    create_github_release "$PLATFORM" "$VERSION" "$VERSION_TAG" \
        "$TARGET_FILE" \
        "$TARGET_FILE.sha256" \
        "$NOW_SUM256"
        
    echo_color "green" "版本 $VERSION 发布成功"
    
    # 清理临时文件
    echo_color "yellow" "清理临时文件"
    rm -rf "${TEMP_PATH}/temp"
    rm -f "${TEMP_PATH}/temp/WeChatWin_verify.exe" 2>/dev/null || true
}

main
