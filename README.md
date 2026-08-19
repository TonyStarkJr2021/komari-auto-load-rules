<div align="center">

# 🚀 Komari Auto Load Rules

**Komari CPU / RAM / Disk 负载通知规则自动管理工具**

自动分组 · 动态同步 · 独立人工排除/恢复 · 多 Linux 发行版支持

![Version](https://img.shields.io/badge/version-v3.1.1-blue)
![Python](https://img.shields.io/badge/python-3.x-blue)
![Linux](https://img.shields.io/badge/Linux-systemd-orange)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

---

## ✨ 功能特性

- 🔍 自动识别 Komari 主控 systemd 服务
- 📂 自动识别 Komari 程序、数据库和监听端口
- 🔑 API Key 交互式录入，仅保存在本机
- ⚙️ 自动创建 CPU / RAM / Disk 共 5 条基础负载规则
- ➕ 新 VPS 自动加入监控
- ➖ 删除 VPS 自动清理
- 🏷️ VPS 改名不影响规则关联
- 🧠 RAM / Disk 扩容后自动重新分组
- 🎛️ CPU / RAM / Disk 可分别人工关闭
- 💾 自动记忆人工关闭状态，不会被下一次同步重新添加
- ♻️ 后台重新勾选后自动恢复对应监控项
- ⏱️ systemd Timer 每 10 分钟自动同步
- 🆕 支持 0 VPS 状态安装，后续新增节点自动接管

---

## 📊 默认负载规则

| 监控项 | VPS 条件 | 阈值 | 时间占比 | 通知间隔 |
|:---:|:---:|:---:|:---:|:---:|
| CPU | 全部 VPS | 90% | 0.8 | 10 分钟 |
| RAM | ≥ 1.5 GB | 90% | 0.8 | 10 分钟 |
| RAM | < 1.5 GB | 95% | 0.8 | 10 分钟 |
| Disk | ≥ 20 GB | 90% | 0.9 | 60 分钟 |
| Disk | < 20 GB | 85% | 0.9 | 60 分钟 |

脚本会根据 VPS 的实际内存和磁盘容量自动选择对应规则。

---

## 🐧 支持环境

当前版本要求 **Komari 主控以 systemd service 方式运行**。

已适配以下包管理器：

| Linux 发行版 | 包管理器 |
|---|:---:|
| Debian / Ubuntu / Debian 系 | `apt` |
| Rocky Linux / AlmaLinux / Fedora / CentOS Stream | `dnf` |
| 旧 CentOS / RHEL 系 | `yum` |
| Arch Linux | `pacman` |
| openSUSE | `zypper` |

> [!NOTE]
> Alpine / OpenRC 当前暂不支持。

---

## 📋 安装前准备

安装前请确认：

1. Komari 主控已经正常运行
2. 使用 `root` 用户执行安装
3. 已在 Komari 后台生成 API Key

> [!CAUTION]
> API Key 拥有较高的 Komari 管理权限，请勿提交至 GitHub 或公开分享。

---

## 🚀 一键安装

使用 `root` 用户执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/TonyStarkJr2021/komari-auto-load-rules/main/install.sh)
```

安装器会自动完成：

```text
检测 Linux 发行版
        ↓
检测包管理器及依赖
        ↓
识别 Komari systemd 服务
        ↓
识别 Komari 程序与数据库
        ↓
自动识别 Komari 监听端口
        ↓
验证 / 保存 API Key
        ↓
初始化 5 条基础负载规则
        ↓
安装自动同步程序
        ↓
创建 systemd Timer
        ↓
首次同步
```

即使 Komari 当前 **没有任何 VPS 节点**，安装也可以正常完成。

后续添加 VPS 后，定时同步程序会自动识别并加入对应的负载通知规则。

---

## 🔄 更新

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/TonyStarkJr2021/komari-auto-load-rules/main/update.sh)
```

更新核心同步程序时不会清除：

- API Key
- 人工排除状态
- Komari 数据
- 已有 VPS 配置

---

## 🗑️ 卸载

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/TonyStarkJr2021/komari-auto-load-rules/main/uninstall.sh)
```

默认不会删除 Komari 本身，也不会主动删除 Komari 后台已有的负载规则。

---

## 🔄 手动执行同步

无需等待 systemd Timer，可以立即执行一次同步：

```bash
/usr/local/bin/komari-auto-load-rules.py
```

---

## ⏱️ 查看自动同步状态

```bash
systemctl status komari-auto-load-rules.timer
```

默认同步周期：

```text
每 10 分钟
```

---

## 📜 查看运行日志

```bash
journalctl -u komari-auto-load-rules.service -n 100 --no-pager
```

---

## 🎛️ 人工关闭 / 恢复监控

本项目支持对单台 VPS 的：

**CPU / RAM / Disk 分别进行人工关闭和恢复。**

### 关闭某一项

例如不希望某台 VPS 接收 RAM 高负载通知：

1. 打开 Komari 后台
2. 找到对应 RAM 负载规则
3. 取消该 VPS
4. 保存规则

脚本下一次同步时会识别该变化，并记录为：

```text
人工排除：RAM
```

以后自动同步不会重新把该 VPS 加回 RAM 规则。

CPU 和 Disk 仍然可以继续正常监控。

### 恢复某一项

如果以后希望恢复 RAM 监控：

1. 在对应 RAM 规则中重新勾选该 VPS
2. 保存规则
3. 等待下一次自动同步

脚本会识别为人工恢复，并根据 VPS **当前 RAM 容量**自动放入正确的 RAM 分组。

CPU、RAM、Disk 三项状态相互独立。

---

## 🧠 自动分组逻辑

### RAM

```text
RAM ≥ 1.5 GB
      │
      ├── 是 → RAM 常规组（90%）
      │
      └── 否 → RAM 小内存组（95%）
```

### Disk

```text
Disk ≥ 20 GB
      │
      ├── 是 → Disk 常规组（90%）
      │
      └── 否 → Disk 小磁盘组（85%）
```

如果 VPS 后续扩容 RAM 或 Disk，脚本会自动重新判断并迁移到正确的规则组。

---

## 📁 本地文件

安装后主要文件位置：

```text
/root/.config/komari/api_key
/etc/komari-auto-load-rules.conf
/usr/local/bin/komari-auto-load-rules.py
/var/lib/komari-auto-load-rules/state.json
```

其中：

| 文件 | 用途 |
|---|---|
| `api_key` | 保存 Komari API Key |
| `komari-auto-load-rules.conf` | 本项目运行配置 |
| `komari-auto-load-rules.py` | 核心同步程序 |
| `state.json` | 保存人工排除/恢复状态 |

> [!IMPORTANT]
> 如果迁移 Komari Auto Load Rules 并希望保留人工排除状态，请备份 `state.json`。

---

## 🔐 安全说明

本项目不会主动上传：

- Komari API Key
- Komari 数据库
- VPS IP
- Agent Token

Komari 管理 API 默认通过主控服务器本机回环地址访问：

```text
127.0.0.1
```

API Key 仅保存在主控服务器本地。

---

## 🛠️ 项目结构

```text
komari-auto-load-rules/
├── src/
│   └── komari-auto-load-rules.py
├── install.sh
├── update.sh
├── uninstall.sh
├── README.md
├── LICENSE
└── .gitignore
```

---

## 📄 License

本项目采用 [MIT License](LICENSE)。

---

<div align="center">

**Komari Auto Load Rules**

让 Komari VPS 负载通知规则自动维护。

</div>
