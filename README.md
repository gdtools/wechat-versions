# WeChat 版本收集

本项目自动收集并保存 Windows 和 Mac 平台的微信安装包，用于版本存档和研究目的。

## 项目特点

- 自动下载最新版本的 Windows 和 Mac 微信客户端
- 计算安装包的 SHA256 哈希值用于完整性校验
- 保存所有历史版本以便追溯和比较
- 通过 GitHub Actions 实现全自动化流程
- 支持版本冲突检测和处理

## 目录结构

```
├── README.md                     # 项目说明文档
├── WeChatWin                     # Windows 微信版本存储目录
│   └── [版本号]                  # 按版本号归类的安装包
│       ├── WeChatWin-[版本号].exe      # Windows 安装包
│       └── WeChatWin-[版本号].exe.sha256  # 安装包哈希和元信息
├── WeChatMac                     # Mac 微信版本存储目录
│   └── [版本号]                  # 按版本号归类的安装包
│       ├── WeChatMac-[版本号].dmg      # Mac 安装包
│       └── WeChatMac-[版本号].dmg.sha256  # 安装包哈希和元信息
└── scripts                       # 自动化脚本目录
    ├── common.sh                 # 公共函数库
    ├── destVersionForWin.sh      # Windows 版本检测与发布脚本
    └── destVersionForMac.sh      # Mac 版本检测与发布脚本
```

## 相关项目

* [Mac微信收集](https://github.com/zsbai/wechat-versions)
* [Windows x86 微信版本收集](https://github.com/tom-snow/wechat-windows-versions-x86)

## 使用方法

### 获取特定版本

直接从本仓库的 Releases 页面下载对应平台和版本的安装包。

### 环境准备

1. 安装必要依赖：
```bash
# Mac 通用依赖
brew install wget curl git gh

# Windows 版本额外依赖
brew install p7zip
```

2. GitHub CLI 认证：
```bash
gh auth login
```

3. 设置脚本执行权限：
```bash
chmod +x scripts/common.sh
chmod +x scripts/destVersionForMac.sh
chmod +x scripts/destVersionForWin.sh
```

### 运行脚本

如需手动运行版本检测脚本:

```bash
# 检测 Windows 微信版本更新
./scripts/destVersionForWin.sh

# 检测 Mac 微信版本更新
./scripts/destVersionForMac.sh
```

### 脚本功能说明

- 自动检测并安装缺失依赖
- 智能获取最新版本下载链接
- 自动提取版本信息
- 计算并验证 SHA256 校验和
- 自动处理版本冲突
- 创建 GitHub Release
- 自动清理临时文件

## 说明

- 项目使用 GitHub Actions 自动下载最新版本微信安装包，计算哈希值并发布到仓库
- 所有安装包均从官方渠道获取，确保安全性
- **注意**: 3.5.0.46 版本以前的部分安装包来自 [web.archive.org](https://web.archive.org/web/*/https://pc.weixin.qq.com/)

## 版本历史

各版本更新日志可参见 [微信更新日志](https://weixin.qq.com/cgi-bin/readtemplate?lang=zh_CN&t=weixin_faq_list&head=true)

## 免责声明

本项目仅用于研究和存档目的，所有安装包版权归腾讯公司所有。如有任何问题或侵权，请提交 Issue 告知，我们将及时处理。
