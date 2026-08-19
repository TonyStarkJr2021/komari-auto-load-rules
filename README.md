# Komari Auto Load Rules

> 当前版本：**v3.1.1**

为 Komari 自动维护 CPU / RAM / Disk 负载通知规则，支持多种 **systemd Linux** 发行版。

## 支持环境

当前公开版要求 Komari 主控以 **systemd service** 运行。Komari 官方一键安装器本身也面向 systemd 发行版。

已适配安装依赖的包管理器：

- Debian / Ubuntu / Debian 系：`apt`
- Rocky Linux / AlmaLinux / Fedora / CentOS Stream：`dnf`
- 旧 CentOS / RHEL 系：`yum`
- Arch Linux：`pacman`
- openSUSE：`zypper`

> Alpine / OpenRC 当前不支持。

## 功能

- 自动识别 Komari 主控 systemd 服务
- 自动识别 Komari 程序、数据库和监听端口
- API Key 交互式录入并仅保存在本机
- 自动创建 5 条基础负载规则
- 支持 0 节点安装：可先部署本项目，之后再添加 VPS
- 新 VPS 自动加入
- 删除 VPS 自动清理
- VPS 改名不影响规则关联
- RAM / Disk 扩容后自动重新分组
- CPU / RAM / Disk 三项可以分别人工关闭
- 人工关闭后自动记忆，不会被下一次同步加回
- 后台重新勾选后自动恢复该监控项
- systemd Timer 每 10 分钟自动同步

## 默认规则

| 类型 | 条件 | 阈值 | 时间占比 | 通知间隔 |
|---|---|---:|---:|---:|
| CPU | 全部 VPS | 90% | 0.8 | 10 分钟 |
| RAM | ≥ 1.5 GB | 90% | 0.8 | 10 分钟 |
| RAM | < 1.5 GB | 95% | 0.8 | 10 分钟 |
| Disk | ≥ 20 GB | 90% | 0.9 | 60 分钟 |
| Disk | < 20 GB | 85% | 0.9 | 60 分钟 |

## 安装前准备

1. Komari 主控已经正常运行。
2. 使用 root 执行安装。
3. 在 Komari 后台生成 API Key。
4. **不要求预先添加 VPS**；0 节点也可以完成安装，之后新增 VPS 会自动加入规则。
5. API Key 不要提交到 GitHub，也不要公开分享。

## 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/TonyStarkJr2021/komari-auto-load-rules/main/install.sh)
```

安装器会自动识别发行版、包管理器、Komari 服务、程序路径、数据库和监听端口。自动检测失败时才会要求手工输入。

如果当前 Komari 还没有任何 VPS，安装仍会正常完成；5 条规则先保持为空，systemd Timer 会继续运行，之后新增节点会自动分类并加入对应规则。

## 更新

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/TonyStarkJr2021/komari-auto-load-rules/main/update.sh)
```

更新核心同步程序时不会清除 API Key、人工排除状态和 Komari 数据。

## 卸载

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/TonyStarkJr2021/komari-auto-load-rules/main/uninstall.sh)
```

默认不会删除 Komari 本身或 Komari 后台中的负载规则。

## 手动同步

```bash
/usr/local/bin/komari-auto-load-rules.py
```

## 查看 Timer

```bash
systemctl status komari-auto-load-rules.timer
```

## 查看日志

```bash
journalctl -u komari-auto-load-rules.service -n 100 --no-pager
```

## 人工关闭 / 恢复某一项监控

在 Komari 后台对应规则中取消某台 VPS 并保存。脚本下一次运行会把该操作记忆为人工关闭。例如只取消 RAM，则 CPU 和 Disk 继续正常监控。

若要恢复，在任意对应 RAM 规则中重新勾选该 VPS。下一次同步会识别为人工恢复，并根据当前 RAM 容量自动放入正确的 RAM 分组。

## 本地文件

```text
/root/.config/komari/api_key
/etc/komari-auto-load-rules.conf
/usr/local/bin/komari-auto-load-rules.py
/var/lib/komari-auto-load-rules/state.json
```

如需迁移并保留人工排除状态，请备份 `state.json`。

## 安全说明

脚本不会主动上传 API Key、Komari 数据库、VPS IP 或 Agent Token。管理 API 默认通过 Komari 主控本机回环地址访问。

## License

MIT


## v3.1.1

- 修复全新 Komari 主控在 **0 个 VPS** 时首次同步直接报错、导致安装失败的问题。
- 现在可以先安装本项目，再添加 Komari Agent。
- 当 VPS 数量为 0 时，规则保持为空；新增节点后会由定时任务自动分类并同步。
