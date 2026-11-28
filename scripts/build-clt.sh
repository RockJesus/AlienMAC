#!/usr/bin/env bash
# AlienMAC 免 Xcode 构建：只用 Command Line Tools 的 swiftc，一条命令出 .app + .dmg + .zip
#
# 用法：
#   scripts/build-clt.sh              # 全量编译并打包
#   scripts/build-clt.sh --no-dmg     # 只出 .app（调试用，快一点）
#
# 不需要 Xcode、不需要 xcodegen、不需要 xcodebuild。
# 产物落在 build/：AlienMAC.app / AlienMAC-<版本>.dmg / AlienMAC-<版本>.app.zip
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="build/AlienMAC.app"
BIN="build/AlienMAC-bin"

if ! command -v swiftc >/dev/null 2>&1; then
    echo "找不到 swiftc：先装 Command Line Tools（xcode-select --install）" >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
echo "=== 免 Xcode 构建 AlienMAC $VERSION ==="

mkdir -p build

echo "· 编译 $(find Sources -name '*.swift' | wc -l | tr -d ' ') 个源文件"
# -wmo 全模块优化；--target 固定到本机架构，Intel 机也照编
find Sources -name '*.swift' -print0 \
  | xargs -0 swiftc -O -wmo \
      -target "x86_64-apple-macos13.0" \
      -framework IOKit -framework CoreFoundation -framework Carbon -framework Network \
      -o "$BIN"

echo "· 组装 app 包"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AlienMAC"

# Info.plist 里的 $(BUILD_SETTING) 由 Xcode 展开，CLT 路径下自己替换掉
sed -e 's/$(DEVELOPMENT_LANGUAGE)/zh-Hans/g' \
    -e 's/$(EXECUTABLE_NAME)/AlienMAC/g' \
    -e 's/$(PRODUCT_BUNDLE_IDENTIFIER)/com.alienmac.AlienMAC/g' \
    -e 's/$(PRODUCT_NAME)/AlienMAC/g' \
    Resources/Info.plist > "$APP/Contents/Info.plist"

for f in Resources/*; do
    base=$(basename "$f")
    case "$base" in
        Info.plist|AlienMAC.entitlements) continue ;;
    esac
    cp -R "$f" "$APP/Contents/Resources/"
done

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "· 签名（ad-hoc）"
codesign --force --sign - "$APP"
codesign --verify "$APP"

if [ "${1:-}" = "--no-dmg" ]; then
    echo "完成：$APP（$(du -sh "$APP" | cut -f1)）"
    exit 0
fi

echo "· 打 dmg / zip"
rm -f "build/AlienMAC-$VERSION.dmg" "build/AlienMAC-$VERSION.app.zip"
hdiutil create -quiet -volname AlienMAC -srcfolder "$APP" -ov -format UDZO "build/AlienMAC-$VERSION.dmg"
ditto -c -k --keepParent "$APP" "build/AlienMAC-$VERSION.app.zip"

echo "完成："
ls -l "build/AlienMAC-$VERSION.dmg" "build/AlienMAC-$VERSION.app.zip" | awk '{print "  " $9 "  " $5 " B"}'
