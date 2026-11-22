#!/usr/bin/env bash
# 仓库脱敏自检：令牌、私网 IP、邮箱、手机号、绝对用户路径、私有子域名、私钥。
# 只扫描 git 跟踪的文本文件；图片/视频单独看元数据。
set -uo pipefail
cd "$(dirname "$0")/.."

FAIL=0
scan() {
  local label="$1" pattern="$2"
  local hits
  hits=$(git ls-files -z \
    | grep -zvE '\.(png|icns|mp4|app)$' \
    | xargs -0 grep -nIE "$pattern" 2>/dev/null \
    | grep -vE 'shields\.io|apple\.com/DTDs|https://rockjesus\.cn|作者博客|github\.com/RockJesus|com\.alienmac|removeObject|set\(password' || true)
  if [ -n "$hits" ]; then
    echo "❌ $label"
    echo "$hits" | sed 's/^/   /'
    FAIL=1
  else
    echo "✅ $label"
  fi
}

scan "GitHub / 云厂商令牌" 'ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{12,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{20,}'
scan "私钥文件头" '-----BEGIN [A-Z ]*PRIVATE KEY-----'
scan "邮箱地址" '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
scan "IPv4 字面量" '\b((25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})\b'
scan "手机号" '\b1[3-9][0-9]{9}\b'
scan "绝对用户路径" '/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+|[A-Za-z]:\\\\Users\\\\'
scan "私有子域名" '(ha|fn|dyc|[a-z0-9-]+)\.rockjesus\.cn'
scan "MQTT 明文密码落盘" 'defaults\.set\([^)]*AlienMAC\.haPass'

if [ "$FAIL" -ne 0 ]; then
  echo ""
  echo "脱敏自检未通过：请删掉命中内容后重试。"
  exit 1
fi
echo ""
echo "全部通过。"
