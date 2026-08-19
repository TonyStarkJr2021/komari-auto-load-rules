#!/usr/bin/env bash
set -Eeuo pipefail

APP_VERSION="3.1.1"
REPO_OWNER="TonyStarkJr2021"
REPO_NAME="komari-auto-load-rules"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"
PY_URL="${RAW_BASE}/src/komari-auto-load-rules.py"

API_KEY_DIR="/root/.config/komari"
API_KEY_FILE="${API_KEY_DIR}/api_key"
CONFIG_FILE="/etc/komari-auto-load-rules.conf"
PY_SCRIPT="/usr/local/bin/komari-auto-load-rules.py"
STATE_DIR="/var/lib/komari-auto-load-rules"
SERVICE_FILE="/etc/systemd/system/komari-auto-load-rules.service"
TIMER_FILE="/etc/systemd/system/komari-auto-load-rules.timer"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}[INFO]${NC} $*"; }
success(){ echo -e "${GREEN}[OK]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
error(){ echo -e "${RED}[ERROR]${NC} $*"; }
trap 'error "安装失败，出错行：${LINENO}"' ERR

[[ $(id -u) -eq 0 ]] || { error "请使用 root 用户运行。"; exit 1; }
command -v systemctl >/dev/null 2>&1 || { error "当前系统不是受支持的 systemd 环境。"; exit 1; }
[[ -d /run/systemd/system ]] || { error "systemd 当前未作为 init 运行。"; exit 1; }

echo
echo "=================================================="
echo " Komari Auto Load Rules V${APP_VERSION}"
echo " Multi-Distro / systemd"
echo "=================================================="
echo

OS_ID="unknown"; OS_NAME="Linux"
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-unknown}"; OS_NAME="${PRETTY_NAME:-${NAME:-Linux}}"
fi
success "Linux：${OS_NAME}"

install_dependencies(){
  local need_sqlite=0 need_curl=0 need_python=0 need_ss=0
  command -v sqlite3 >/dev/null 2>&1 || need_sqlite=1
  command -v curl >/dev/null 2>&1 || need_curl=1
  command -v python3 >/dev/null 2>&1 || need_python=1
  command -v ss >/dev/null 2>&1 || need_ss=1
  (( need_sqlite || need_curl || need_python || need_ss )) || { success "依赖已满足。"; return; }

  if command -v apt-get >/dev/null 2>&1; then
    info "包管理器：apt"
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      $([[ $need_sqlite -eq 1 ]] && echo sqlite3) \
      $([[ $need_curl -eq 1 ]] && echo curl) \
      $([[ $need_python -eq 1 ]] && echo python3) \
      $([[ $need_ss -eq 1 ]] && echo iproute2)
  elif command -v dnf >/dev/null 2>&1; then
    info "包管理器：dnf"
    dnf install -y \
      $([[ $need_sqlite -eq 1 ]] && echo sqlite) \
      $([[ $need_curl -eq 1 ]] && echo curl) \
      $([[ $need_python -eq 1 ]] && echo python3) \
      $([[ $need_ss -eq 1 ]] && echo iproute)
  elif command -v yum >/dev/null 2>&1; then
    info "包管理器：yum"
    yum install -y \
      $([[ $need_sqlite -eq 1 ]] && echo sqlite) \
      $([[ $need_curl -eq 1 ]] && echo curl) \
      $([[ $need_python -eq 1 ]] && echo python3) \
      $([[ $need_ss -eq 1 ]] && echo iproute)
  elif command -v pacman >/dev/null 2>&1; then
    info "包管理器：pacman"
    pacman -Sy --noconfirm --needed \
      $([[ $need_sqlite -eq 1 ]] && echo sqlite) \
      $([[ $need_curl -eq 1 ]] && echo curl) \
      $([[ $need_python -eq 1 ]] && echo python) \
      $([[ $need_ss -eq 1 ]] && echo iproute2)
  elif command -v zypper >/dev/null 2>&1; then
    info "包管理器：zypper"
    zypper --non-interactive install \
      $([[ $need_sqlite -eq 1 ]] && echo sqlite3) \
      $([[ $need_curl -eq 1 ]] && echo curl) \
      $([[ $need_python -eq 1 ]] && echo python3) \
      $([[ $need_ss -eq 1 ]] && echo iproute2)
  else
    error "未识别到受支持的包管理器（apt/dnf/yum/pacman/zypper）。"
    exit 1
  fi
  command -v sqlite3 >/dev/null 2>&1 || { error "sqlite3 安装失败。"; exit 1; }
  command -v curl >/dev/null 2>&1 || { error "curl 安装失败。"; exit 1; }
  command -v python3 >/dev/null 2>&1 || { error "python3 安装失败。"; exit 1; }
  command -v ss >/dev/null 2>&1 || { error "ss/iproute2 安装失败。"; exit 1; }
  success "依赖安装完成。"
}
install_dependencies

detect_service(){
  local s exec
  while read -r s; do
    [[ -n "$s" ]] || continue
    exec="$(systemctl show "$s" -p ExecStart --value 2>/dev/null || true)"
    if [[ "$exec" =~ (^|[[:space:]])server([[:space:]]|$) ]] && [[ "$exec" == *komari* ]]; then
      echo "$s"; return 0
    fi
  done < <(systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -i komari || true)
  return 1
}

info "检测 Komari 主控服务..."
if KOMARI_SERVICE="$(detect_service)"; then success "服务：${KOMARI_SERVICE}"; else
  warn "无法自动识别 Komari 主控服务。"
  read -rp "请输入 systemd 服务名 [komari.service]: " KOMARI_SERVICE
  KOMARI_SERVICE="${KOMARI_SERVICE:-komari.service}"
fi
systemctl cat "$KOMARI_SERVICE" >/dev/null 2>&1 || { error "找不到服务：${KOMARI_SERVICE}"; exit 1; }
EXEC_START="$(systemctl show "$KOMARI_SERVICE" -p ExecStart --value 2>/dev/null || true)"
[[ -n "$EXEC_START" ]] || { error "无法读取 Komari ExecStart。"; exit 1; }

KOMARI_BINARY="$(printf '%s\n' "$EXEC_START" | grep -oE '/[^ ;{}"]*komari([^ ;{}"]*)?' | head -n1 || true)"
if [[ -z "$KOMARI_BINARY" || ! -f "$KOMARI_BINARY" ]]; then
  warn "无法自动识别 Komari 程序路径。"; read -rp "请输入 Komari 二进制完整路径: " KOMARI_BINARY
fi
[[ -f "$KOMARI_BINARY" ]] || { error "Komari 程序不存在：${KOMARI_BINARY}"; exit 1; }
KOMARI_DIR="$(dirname "$KOMARI_BINARY")"; success "程序：${KOMARI_BINARY}"

detect_db(){
  local f
  for f in "${KOMARI_DIR}/data/komari.db" "/opt/komari/data/komari.db" "/usr/local/komari/data/komari.db" "/var/lib/komari/komari.db"; do
    [[ -f "$f" ]] && { echo "$f"; return 0; }
  done
  find "$KOMARI_DIR" /opt /usr/local /var/lib /root -maxdepth 5 -type f -name komari.db 2>/dev/null | head -n1
}
DB_PATH="$(detect_db || true)"
if [[ -z "$DB_PATH" ]]; then warn "无法自动识别 komari.db。"; read -rp "请输入 komari.db 完整路径: " DB_PATH; fi
[[ -f "$DB_PATH" ]] || { error "数据库不存在：${DB_PATH}"; exit 1; }
DATA_DIR="$(dirname "$DB_PATH")"; BACKUP_DIR="${DATA_DIR}/backup"; success "数据库：${DB_PATH}"

detect_port(){
  local port pid
  port="$(printf '%s\n' "$EXEC_START" | grep -oE -- '(-l|--listen)([ =]+)[^ ;}]+' | head -n1 | grep -oE '[0-9]{1,5}$' || true)"
  if [[ "$port" =~ ^[0-9]+$ ]] && (( port>=1 && port<=65535 )); then echo "$port"; return 0; fi
  pid="$(systemctl show "$KOMARI_SERVICE" -p MainPID --value 2>/dev/null || true)"
  if [[ "$pid" =~ ^[0-9]+$ && "$pid" != 0 ]]; then
    port="$(ss -lntp 2>/dev/null | grep "pid=${pid}," | awk '{print $4}' | sed -E 's/.*:([0-9]+)$/\1/' | head -n1 || true)"
    if [[ "$port" =~ ^[0-9]+$ ]] && (( port>=1 && port<=65535 )); then echo "$port"; return 0; fi
  fi
  return 1
}
if KOMARI_PORT="$(detect_port)"; then success "监听端口：${KOMARI_PORT}"; else
  warn "无法自动识别监听端口。"; read -rp "请输入 Komari 监听端口: " KOMARI_PORT
fi
[[ "$KOMARI_PORT" =~ ^[0-9]+$ ]] && (( KOMARI_PORT>=1 && KOMARI_PORT<=65535 )) || { error "端口不合法。"; exit 1; }

mkdir -p "$API_KEY_DIR"; chmod 700 "$API_KEY_DIR"
USE_OLD=N
if [[ -s "$API_KEY_FILE" ]]; then read -rp "检测到已有 API Key，继续使用？[Y/n]: " USE_OLD; USE_OLD="${USE_OLD:-Y}"; fi
if [[ ! "$USE_OLD" =~ ^[Yy]$ ]]; then
  read -rsp "请输入 Komari API Key（输入不会显示）: " KOMARI_API_KEY; echo
  [[ -n "$KOMARI_API_KEY" ]] || { error "API Key 不能为空。"; exit 1; }
  printf '%s\n' "$KOMARI_API_KEY" > "$API_KEY_FILE"; chmod 600 "$API_KEY_FILE"; unset KOMARI_API_KEY
fi
API_KEY="$(<"$API_KEY_FILE")"

test_api(){ curl -fsS --connect-timeout 5 --max-time 10 -H "Authorization: Bearer ${API_KEY}" "$1/api/admin/notification/load/" 2>/dev/null | grep -q '"status":"success"'; }
if test_api "http://127.0.0.1:${KOMARI_PORT}"; then API_BASE="http://127.0.0.1:${KOMARI_PORT}";
elif test_api "http://[::1]:${KOMARI_PORT}"; then API_BASE="http://[::1]:${KOMARI_PORT}";
else error "Komari API 验证失败，请检查 API Key 和端口。"; exit 1; fi
success "API 验证成功：${API_BASE}"

cat > "$CONFIG_FILE" <<EOF
KOMARI_SERVICE=${KOMARI_SERVICE}
DB_PATH=${DB_PATH}
FALLBACK_PORT=${KOMARI_PORT}
EOF
chmod 600 "$CONFIG_FILE"

for TABLE in clients load_notifications; do
  [[ "$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='${TABLE}';")" == 1 ]] || { error "数据库缺少 ${TABLE} 表。"; exit 1; }
done

RULES_MISSING=0
for RULE_NAME in "CPU高负载" "RAM高负载" "小内存RAM高负载" "磁盘空间不足" "小磁盘空间不足"; do
  [[ "$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM load_notifications WHERE name='${RULE_NAME}';")" != 0 ]] || { RULES_MISSING=1; break; }
done

if [[ $RULES_MISSING -eq 1 ]]; then
  info "初始化缺失负载规则..."; mkdir -p "$BACKUP_DIR"
  BACKUP_FILE="${BACKUP_DIR}/komari-auto-load-$(date +%Y%m%d_%H%M%S).db"
  systemctl stop "$KOMARI_SERVICE"
  sqlite3 "$DB_PATH" ".backup '${BACKUP_FILE}'"
  sqlite3 "$DB_PATH" <<'SQL'
BEGIN IMMEDIATE;
INSERT INTO load_notifications(name,clients,metric,threshold,ratio,interval) SELECT 'CPU高负载','[]','cpu',90,0.8,10 WHERE NOT EXISTS (SELECT 1 FROM load_notifications WHERE name='CPU高负载');
INSERT INTO load_notifications(name,clients,metric,threshold,ratio,interval) SELECT 'RAM高负载','[]','ram',90,0.8,10 WHERE NOT EXISTS (SELECT 1 FROM load_notifications WHERE name='RAM高负载');
INSERT INTO load_notifications(name,clients,metric,threshold,ratio,interval) SELECT '小内存RAM高负载','[]','ram',95,0.8,10 WHERE NOT EXISTS (SELECT 1 FROM load_notifications WHERE name='小内存RAM高负载');
INSERT INTO load_notifications(name,clients,metric,threshold,ratio,interval) SELECT '磁盘空间不足','[]','disk',90,0.9,60 WHERE NOT EXISTS (SELECT 1 FROM load_notifications WHERE name='磁盘空间不足');
INSERT INTO load_notifications(name,clients,metric,threshold,ratio,interval) SELECT '小磁盘空间不足','[]','disk',85,0.9,60 WHERE NOT EXISTS (SELECT 1 FROM load_notifications WHERE name='小磁盘空间不足');
COMMIT;
SQL
  systemctl start "$KOMARI_SERVICE"; sleep 3
  systemctl is-active --quiet "$KOMARI_SERVICE" || { error "Komari 重启失败。"; exit 1; }
  success "基础规则初始化完成，备份：${BACKUP_FILE}"
else success "5 条基础规则已存在。"; fi

info "下载核心同步程序..."
curl -fsSL "$PY_URL" -o "$PY_SCRIPT"; chmod 700 "$PY_SCRIPT"; python3 -m py_compile "$PY_SCRIPT"
mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"; success "核心程序安装完成。"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Komari Automatic Load Rule Sync
After=network-online.target ${KOMARI_SERVICE}
Wants=network-online.target
Requires=${KOMARI_SERVICE}

[Service]
Type=oneshot
User=root
ExecStart=${PY_SCRIPT}
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
NoNewPrivileges=true
PrivateTmp=true
EOF

cat > "$TIMER_FILE" <<'EOF'
[Unit]
Description=Komari Automatic Load Rule Sync Timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=10min
AccuracySec=30s
Persistent=true

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
info "执行首次同步..."; "$PY_SCRIPT"
systemctl enable --now komari-auto-load-rules.timer

echo
echo "=================================================="
echo " Komari Auto Load Rules V${APP_VERSION} 安装完成"
echo "=================================================="
echo "系统：${OS_NAME}"
echo "服务：${KOMARI_SERVICE}"
echo "数据库：${DB_PATH}"
echo "端口：${KOMARI_PORT}"
echo "同步周期：每 10 分钟"
echo
success "安装完成。"
