#!/usr/bin/env bash
set -Eeuo pipefail
REPO_OWNER="TonyStarkJr2021"
REPO_NAME="komari-auto-load-rules"
BRANCH="main"
URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/src/komari-auto-load-rules.py"
TARGET="/usr/local/bin/komari-auto-load-rules.py"
[[ $(id -u) -eq 0 ]] || { echo "请使用 root 用户运行。"; exit 1; }
[[ -f "$TARGET" ]] || { echo "未检测到已安装程序，请先运行 install.sh。"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "缺少 curl。"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "缺少 python3。"; exit 1; }
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
curl -fsSL "$URL" -o "$TMP"
python3 -m py_compile "$TMP"
cp "$TARGET" "${TARGET}.bak"
install -m 700 "$TMP" "$TARGET"
"$TARGET"
systemctl restart komari-auto-load-rules.timer
echo "更新完成；旧版本备份：${TARGET}.bak"
