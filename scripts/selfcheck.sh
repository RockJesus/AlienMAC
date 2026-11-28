#!/usr/bin/env bash
# AlienMAC 免 Xcode 自检：把不依赖外部框架的纯逻辑编成命令行程序跑一遍
#
# 用法：scripts/selfcheck.sh
# 退出码 0 = 全过；非 0 = 有断言失败（可直接当 CI 用）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v swiftc >/dev/null 2>&1; then
    echo "找不到 swiftc：先装 Command Line Tools（xcode-select --install）" >&2
    exit 1
fi

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

swiftc -O \
    -target "x86_64-apple-macos13.0" \
    -framework IOKit \
    Sources/Services/PeripheralLightSender.swift \
    Sources/Services/FXMouseCodec.swift \
    Tools/selfcheck/main.swift \
    -o "$OUT/selfcheck"

"$OUT/selfcheck"
