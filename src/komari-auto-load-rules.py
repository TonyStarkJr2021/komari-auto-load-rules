#!/usr/bin/env python3

import json
import os
import re
import sqlite3
import subprocess
import sys
import urllib.request
from datetime import datetime

CONFIG_FILE = "/etc/komari-auto-load-rules.conf"
API_KEY_FILE = "/root/.config/komari/api_key"
STATE_DIR = "/var/lib/komari-auto-load-rules"
STATE_FILE = os.path.join(STATE_DIR, "state.json")
LOAD_API = "/api/admin/notification/load/"
EDIT_API = "/api/admin/notification/load/edit"
GIB = 1024 ** 3
RAM_SPLIT = int(1.5 * GIB)
DISK_SPLIT = 20 * GIB

RULES = {
    "CPU高负载": {"metric": "cpu", "threshold": 90, "ratio": 0.8, "interval": 10},
    "RAM高负载": {"metric": "ram", "threshold": 90, "ratio": 0.8, "interval": 10},
    "小内存RAM高负载": {"metric": "ram", "threshold": 95, "ratio": 0.8, "interval": 10},
    "磁盘空间不足": {"metric": "disk", "threshold": 90, "ratio": 0.9, "interval": 60},
    "小磁盘空间不足": {"metric": "disk", "threshold": 85, "ratio": 0.9, "interval": 60},
}


def log(message):
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{now}] {message}", flush=True)


def load_config():
    if not os.path.exists(CONFIG_FILE):
        raise RuntimeError(f"配置文件不存在：{CONFIG_FILE}")
    config = {}
    with open(CONFIG_FILE, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            config[key.strip()] = value.strip()
    for key in ("KOMARI_SERVICE", "DB_PATH", "FALLBACK_PORT"):
        if not config.get(key):
            raise RuntimeError(f"配置缺少：{key}")
    return config


CONFIG = load_config()
KOMARI_SERVICE = CONFIG["KOMARI_SERVICE"]
DB_PATH = CONFIG["DB_PATH"]
FALLBACK_PORT = int(CONFIG["FALLBACK_PORT"])


def read_api_key():
    if not os.path.exists(API_KEY_FILE):
        raise RuntimeError(f"API Key 文件不存在：{API_KEY_FILE}")
    with open(API_KEY_FILE, "r", encoding="utf-8") as f:
        key = f.read().strip()
    if not key:
        raise RuntimeError("API Key 文件为空")
    return key


API_KEY = read_api_key()


def detect_port():
    try:
        result = subprocess.run(
            ["systemctl", "show", KOMARI_SERVICE, "-p", "ExecStart", "--value"],
            capture_output=True, text=True, timeout=5, check=False,
        )
        text = result.stdout or ""
        patterns = [
            r'(?:-l|--listen)\s*[= ]\s*[^ ;}]*:(\d{1,5})',
            r'(?:-l|--listen)\s*[= ]\s*:(\d{1,5})',
        ]
        for pattern in patterns:
            match = re.search(pattern, text)
            if match:
                port = int(match.group(1))
                if 1 <= port <= 65535:
                    return port
    except Exception:
        pass
    return FALLBACK_PORT


def candidate_api_bases():
    port = detect_port()
    return [f"http://127.0.0.1:{port}", f"http://[::1]:{port}"]


def api_request(path, method="GET", payload=None):
    headers = {"Authorization": f"Bearer {API_KEY}", "Accept": "application/json"}
    data = None
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"
    last_error = None
    for base in candidate_api_bases():
        req = urllib.request.Request(base + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=15) as response:
                body = response.read().decode("utf-8")
            result = json.loads(body)
            if result.get("status") != "success":
                raise RuntimeError("Komari API 返回失败：" + body)
            return result
        except Exception as e:
            last_error = e
    raise RuntimeError(f"无法访问 Komari API：{last_error}")


def read_clients():
    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True, timeout=10)
    conn.row_factory = sqlite3.Row
    try:
        return conn.execute(
            """
            SELECT uuid, name, mem_total, disk_total
            FROM clients
            WHERE uuid IS NOT NULL AND uuid != ''
            ORDER BY name
            """
        ).fetchall()
    finally:
        conn.close()


def get_current_rules():
    result = api_request(LOAD_API)
    return {item["name"]: item for item in (result.get("data") or []) if item.get("name")}


def normalize_clients(value):
    if not value:
        return []
    if isinstance(value, list):
        return sorted(str(x) for x in value)
    try:
        parsed = json.loads(value)
        if isinstance(parsed, list):
            return sorted(str(x) for x in parsed)
    except Exception:
        pass
    return []


def default_state():
    return {
        "version": 3,
        "excluded": {"cpu": [], "ram": [], "disk": []},
        "last_applied": {"cpu": [], "ram": [], "disk": []},
    }


def load_state():
    if not os.path.exists(STATE_FILE):
        return default_state(), True
    with open(STATE_FILE, "r", encoding="utf-8") as f:
        state = json.load(f)
    if state.get("version") not in (2, 3):
        raise RuntimeError(f"不支持的状态文件版本：{state.get('version')}")
    state["version"] = 3
    for metric in ("cpu", "ram", "disk"):
        state.setdefault("excluded", {}).setdefault(metric, [])
        state.setdefault("last_applied", {}).setdefault(metric, [])
    return state, False


def save_state(state):
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    temp = STATE_FILE + ".tmp"
    with open(temp, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)
    os.chmod(temp, 0o600)
    os.replace(temp, STATE_FILE)
    os.chmod(STATE_FILE, 0o600)


def current_metric_members(rules):
    return {
        "cpu": set(normalize_clients(rules["CPU高负载"].get("clients"))),
        "ram": set(normalize_clients(rules["RAM高负载"].get("clients"))) |
               set(normalize_clients(rules["小内存RAM高负载"].get("clients"))),
        "disk": set(normalize_clients(rules["磁盘空间不足"].get("clients"))) |
                set(normalize_clients(rules["小磁盘空间不足"].get("clients"))),
    }


def detect_manual_changes(state, current, existing, names, first_run):
    excluded = {m: set(state["excluded"][m]) & existing for m in ("cpu", "ram", "disk")}
    if first_run:
        log("首次运行状态记忆模式：以当前自动配置建立基线")
        return excluded
    for metric in ("cpu", "ram", "disk"):
        previous = set(state["last_applied"][metric]) & existing
        actual = set(current[metric]) & existing
        for uuid in sorted(previous - actual):
            excluded[metric].add(uuid)
            log(f"检测到人工关闭 {metric.upper()}：{names.get(uuid, uuid)}")
        for uuid in sorted(actual - previous):
            if uuid in excluded[metric]:
                excluded[metric].discard(uuid)
                log(f"检测到人工恢复 {metric.upper()}：{names.get(uuid, uuid)}")
    return excluded


def build_groups(clients, excluded):
    groups = {name: [] for name in RULES}
    enabled = {"cpu": set(), "ram": set(), "disk": set()}
    pending_ram, pending_disk = [], []
    for client in clients:
        uuid = str(client["uuid"])
        name = client["name"] or uuid
        memory = int(client["mem_total"] or 0)
        disk = int(client["disk_total"] or 0)
        if uuid not in excluded["cpu"]:
            groups["CPU高负载"].append(uuid)
            enabled["cpu"].add(uuid)
        if uuid not in excluded["ram"]:
            if memory > 0:
                enabled["ram"].add(uuid)
                groups["小内存RAM高负载" if memory < RAM_SPLIT else "RAM高负载"].append(uuid)
            else:
                pending_ram.append(name)
        if uuid not in excluded["disk"]:
            if disk > 0:
                enabled["disk"].add(uuid)
                groups["小磁盘空间不足" if disk < DISK_SPLIT else "磁盘空间不足"].append(uuid)
            else:
                pending_disk.append(name)
    for key in groups:
        groups[key] = sorted(set(groups[key]))
    return groups, enabled, pending_ram, pending_disk


def num_equal(a, b):
    try:
        return abs(float(a) - float(b)) < 0.000001
    except Exception:
        return False


def build_updates(current, groups):
    missing = [name for name in RULES if name not in current]
    if missing:
        raise RuntimeError("缺少规则：" + "、".join(missing))
    updates = []
    for name, desired in RULES.items():
        rule = current[name]
        actual_clients = normalize_clients(rule.get("clients"))
        try:
            actual_interval = int(rule.get("interval") or 0)
        except Exception:
            actual_interval = 0
        changed = (
            actual_clients != groups[name]
            or rule.get("metric") != desired["metric"]
            or not num_equal(rule.get("threshold"), desired["threshold"])
            or not num_equal(rule.get("ratio"), desired["ratio"])
            or actual_interval != desired["interval"]
        )
        if changed:
            updates.append({
                "id": rule["id"], "name": name, "metric": desired["metric"],
                "threshold": desired["threshold"], "ratio": desired["ratio"],
                "clients": groups[name], "interval": desired["interval"],
            })
    return updates


def main():
    clients = read_clients()

    # V3.1.1：允许在 0 个 VPS 的全新 Komari 主控上完成安装。
    # 规则会保持为空，等以后 Agent 加入后由定时任务自动分类并同步。
    if not clients:
        log("当前暂无 VPS：将保持空规则并等待新节点加入")

    existing = {str(c["uuid"]) for c in clients}
    names = {str(c["uuid"]): (c["name"] or str(c["uuid"])) for c in clients}
    rules = get_current_rules()
    for required in RULES:
        if required not in rules:
            raise RuntimeError(f"缺少规则：{required}")
    state, first_run = load_state()
    actual = current_metric_members(rules)
    excluded = detect_manual_changes(state, actual, existing, names, first_run)
    groups, enabled, pending_ram, pending_disk = build_groups(clients, excluded)
    log(f"当前节点总数：{len(clients)}")
    log(f"CPU监控：{len(groups['CPU高负载'])} 台")
    log(f"RAM常规组：{len(groups['RAM高负载'])} 台")
    log(f"RAM小内存组：{len(groups['小内存RAM高负载'])} 台")
    log(f"Disk常规组：{len(groups['磁盘空间不足'])} 台")
    log(f"Disk小磁盘组：{len(groups['小磁盘空间不足'])} 台")
    log(f"人工排除：CPU {len(excluded['cpu'])} / RAM {len(excluded['ram'])} / Disk {len(excluded['disk'])}")
    if pending_ram:
        log("尚未上报 RAM：" + "、".join(pending_ram))
    if pending_disk:
        log("尚未上报 Disk：" + "、".join(pending_disk))
    updates = build_updates(rules, groups)
    if updates:
        log("需要更新：" + "、".join(item["name"] for item in updates))
        api_request(EDIT_API, method="POST", payload={"notifications": updates})
        log(f"同步成功，共更新 {len(updates)} 条规则")
    else:
        log("规则已经是最新状态，无需修改")
    state["version"] = 3
    state["excluded"] = {m: sorted(excluded[m]) for m in ("cpu", "ram", "disk")}
    state["last_applied"] = {m: sorted(enabled[m]) for m in ("cpu", "ram", "disk")}
    save_state(state)
    if first_run:
        log("V3.1.1 状态文件初始化完成")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        log(f"ERROR: {e}")
        sys.exit(1)
