#!/usr/bin/env bash
set -Eeuo pipefail
[[ $(id -u) -eq 0 ]] || { echo "请使用 root 用户运行。"; exit 1; }
systemctl disable --now komari-auto-load-rules.timer 2>/dev/null || true
rm -f /etc/systemd/system/komari-auto-load-rules.timer /etc/systemd/system/komari-auto-load-rules.service
systemctl daemon-reload
rm -f /usr/local/bin/komari-auto-load-rules.py /etc/komari-auto-load-rules.conf
read -rp "是否删除 CPU/RAM/Disk 人工排除记忆？[y/N]: " x
[[ "$x" =~ ^[Yy]$ ]] && rm -rf /var/lib/komari-auto-load-rules
read -rp "是否删除本机保存的 Komari API Key？[y/N]: " x
[[ "$x" =~ ^[Yy]$ ]] && rm -f /root/.config/komari/api_key
echo "卸载完成。Komari 本身及 Komari 内的负载规则未删除。"
