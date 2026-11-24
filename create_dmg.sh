#!/bin/bash
# ============================================================
# AlienMAC 一键编译 + DMG 安装包制作脚本
# 在黑苹果 macOS 上运行: chmod +x create_dmg.sh && ./create_dmg.sh
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="AlienMAC"
VERSION="1.10.5"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
BUILD_DIR="build"
APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
DMG_STAGING="${BUILD_DIR}/dmg-staging"
DMG_TMP="${BUILD_DIR}/tmp.dmg"
DMG_FINAL="${BUILD_DIR}/${DMG_NAME}"

echo "============================================"
echo "  AlienMAC DMG 安装包制作"
echo "============================================"
echo ""

# ----------------------------------------------------------
# 1. 检查环境
# ----------------------------------------------------------
echo "[1/6] 检查编译环境..."

if ! command -v xcodebuild &> /dev/null; then
    echo "错误: 未安装 Xcode 命令行工具"
    echo "请先安装 Xcode: https://developer.apple.com/xcode/"
    exit 1
fi

if ! command -v xcodegen &> /dev/null; then
    echo "未检测到 XcodeGen，正在安装..."
    if command -v brew &> /dev/null; then
        brew install xcodegen
    else
        echo "错误: 未安装 Homebrew，请先安装: https://brew.sh"
        exit 1
    fi
fi

if ! command -v hdiutil &> /dev/null; then
    echo "错误: 未找到 hdiutil（macOS 系统工具）"
    exit 1
fi

echo "  ✓ Xcode: $(xcodebuild -version | head -1)"
echo "  ✓ XcodeGen: $(xcodegen --version 2>/dev/null || echo 'ok')"
echo "  ✓ hdiutil: 可用"
echo ""

# ----------------------------------------------------------
# 2. 生成 Xcode 项目
# ----------------------------------------------------------
echo "[2/6] 生成 Xcode 项目..."
xcodegen generate
echo "  ✓ 项目已生成"
echo ""

# ----------------------------------------------------------
# 3. 编译 Release
# ----------------------------------------------------------
echo "[3/6] 编译 Release 版本..."
xcodebuild \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    clean build \
    | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)" || true

if [ ! -d "$APP_PATH" ]; then
    echo ""
    echo "错误: 编译失败，未找到 ${APP_PATH}"
    echo "请运行 xcodebuild 查看完整错误信息"
    exit 1
fi

echo "  ✓ 编译成功: ${APP_PATH}"
echo ""

# ----------------------------------------------------------
# 4. 清理旧的 DMG 临时文件
# ----------------------------------------------------------
echo "[4/6] 准备 DMG 打包目录..."
rm -rf "${DMG_STAGING}"
rm -f "${DMG_TMP}"
rm -f "${DMG_FINAL}"
mkdir -p "${DMG_STAGING}"

# 复制 App
cp -R "${APP_PATH}" "${DMG_STAGING}/"

# 创建 Applications 快捷方式（拖拽安装）
ln -s /Applications "${DMG_STAGING}/Applications"

# 创建 DMG 背景图目录
mkdir -p "${DMG_STAGING}/.background"

# 生成简洁的 DMG 背景图（SVG 转 PNG 需要 rsvg-convert 或 sips，这里用纯脚本创建一个简单背景）
# 使用 sips 创建一个纯色背景
BACKGROUND_PNG="${DMG_STAGING}/.background/background.png"
if command -v sips &> /dev/null; then
    # 创建一个 600x400 的深色背景
    python3 -c "
import struct, zlib, os

def create_png(width, height, rgb, path):
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    header = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
    raw = b''
    for y in range(height):
        raw += b'\x00'  # filter byte
        for x in range(width):
            # 渐变背景
            t = y / height
            r = int(rgb[0] * (1 - t*0.3))
            g = int(rgb[1] * (1 - t*0.3))
            b = int(rgb[2] * (1 - t*0.3))
            raw += bytes([r, g, b])
    idat = chunk(b'IDAT', zlib.compress(raw))
    iend = chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(header + ihdr + idat + iend)

create_png(600, 420, (30, 30, 40), '${BACKGROUND_PNG}')
" 2>/dev/null || echo "  (跳过自定义背景图)"
fi

echo "  ✓ 打包目录已准备"
echo ""

# ----------------------------------------------------------
# 5. 创建 DMG
# ----------------------------------------------------------
echo "[5/6] 创建 DMG 磁盘映像..."

# 计算所需大小
APP_SIZE=$(du -sm "${APP_PATH}" | awk '{print $1}')
DMG_SIZE=$((APP_SIZE + 20))  # 额外 20MB 余量

hdiutil create \
    -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "${DMG_STAGING}" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    -size "${DMG_SIZE}m" \
    "${DMG_TMP}" \
    > /dev/null

echo "  ✓ 临时 DMG 已创建"

# ----------------------------------------------------------
# 6. 美化 DMG（设置窗口布局和背景）
# ----------------------------------------------------------
echo "[6/6] 配置 DMG 窗口布局..."

# 挂载 DMG
MOUNT_POINT=$(hdiutil attach "${DMG_TMP}" -nobrowse -readonly | grep Apple_HFS | awk '{print $3}')
if [ -z "$MOUNT_POINT" ]; then
    MOUNT_POINT="/Volumes/${APP_NAME} ${VERSION}"
fi

sleep 1

# 使用 AppleScript 设置窗口外观
osascript <<EOF 2>/dev/null || true
tell application "Finder"
    tell disk "${APP_NAME} ${VERSION}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 720, 540}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set background picture of viewOptions to file ".background:background.png"
        set position of item "${APP_NAME}.app" of container window to {180, 200}
        set position of item "Applications" of container window to {460, 200}
        close
        open
    end tell
end tell
EOF

sleep 1

# 卸载 DMG
hdiutil detach "${MOUNT_POINT}" -quiet 2>/dev/null || hdiutil detach "${MOUNT_POINT}" -force -quiet 2>/dev/null || true

sleep 1

# 压缩为最终 DMG（只读压缩格式）
hdiutil convert "${DMG_TMP}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "${DMG_FINAL}" \
    > /dev/null

# 清理临时文件
rm -f "${DMG_TMP}"
rm -rf "${DMG_STAGING}"

echo "  ✓ DMG 已完成"
echo ""

# ----------------------------------------------------------
# 完成
# ----------------------------------------------------------
DMG_SIZE=$(du -h "${DMG_FINAL}" | awk '{print $1}')
echo "============================================"
echo "  打包完成!"
echo "============================================"
echo ""
echo "  文件: ${DMG_FINAL}"
echo "  大小: ${DMG_SIZE}"
echo ""
echo "  安装方法:"
echo "  1. 双击 ${DMG_NAME} 挂载"
echo "  2. 将 ${APP_NAME}.app 拖入 Applications 文件夹"
echo "  3. 从启动台或应用程序打开"
echo ""
echo "  如提示'无法打开，因为无法验证开发者'，执行:"
echo "  xattr -cr /Applications/${APP_NAME}.app"
echo ""

# 自动在 Finder 中显示
open -R "${DMG_FINAL}" 2>/dev/null || true
