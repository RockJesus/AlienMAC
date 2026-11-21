#!/bin/bash
# AlienMAC 一键编译脚本
# 在 macOS 上运行: chmod +x build.sh && ./build.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== AlienMAC 编译脚本 ==="
echo ""

# 检查 Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo "错误: 未安装 Xcode 命令行工具"
    echo "请先安装 Xcode: https://developer.apple.com/xcode/"
    exit 1
fi

# 检查 XcodeGen
if ! command -v xcodegen &> /dev/null; then
    echo "未检测到 XcodeGen，正在安装..."
    if command -v brew &> /dev/null; then
        brew install xcodegen
    else
        echo "错误: 未安装 Homebrew"
        echo "请先安装 Homebrew: https://brew.sh"
        echo "或手动安装 XcodeGen: brew install xcodegen"
        exit 1
    fi
fi

echo "[1/3] 生成 Xcode 项目..."
xcodegen generate

echo ""
echo "[2/3] 编译 Release 版本..."
xcodebuild \
    -project AlienMAC.xcodeproj \
    -scheme AlienMAC \
    -configuration Release \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    build

echo ""
echo "[3/3] 完成!"
APP_PATH="build/Build/Products/Release/AlienMAC.app"
if [ -d "$APP_PATH" ]; then
    echo "App 已生成: $APP_PATH"
    echo ""
    echo "运行以下命令打开:"
    echo "  open $APP_PATH"
    echo ""
    echo "或复制到应用程序:"
    echo "  cp -R $APP_PATH /Applications/"
else
    echo "警告: 未找到编译产物，请检查上方错误信息"
    exit 1
fi
