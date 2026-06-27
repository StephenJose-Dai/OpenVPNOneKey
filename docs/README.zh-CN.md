<div align="center">

[English](../README.md) | **简体中文** | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Русский](README.ru.md)

</div>

---

# OpenVPN 管理脚本

> 全功能 OpenVPN 服务端管理脚本 — 一键部署、用户管理、限速、双重认证、IPv4/IPv6 双栈，支持所有主流 Linux 发行版。

<div align="center">

![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)
![OpenVPN](https://img.shields.io/badge/OpenVPN-2.5%2B-orange)
![Platform](https://img.shields.io/badge/Platform-Linux-lightgrey?logo=linux)

</div>

---

## 目录

- [功能特性](#功能特性)
- [支持的发行版](#支持的发行版)
- [快速开始](#快速开始)
- [网络拓扑](#网络拓扑)
- [命令参考](#命令参考)
- [安装向导](#安装向导)
- [客户端配置文件](#客户端配置文件)
- [服务端架构](#服务端架构)
- [认证机制](#认证机制)
- [路由模式](#路由模式)
- [限速机制](#限速机制)
- [并发登录控制](#并发登录控制)
- [目录结构](#目录结构)
- [日志系统](#日志系统)
- [光猫与路由器配置](#光猫与路由器配置)
- [常见问题](#常见问题)
- [备份与恢复](#备份与恢复)
- [安全建议](#安全建议)

---

## 功能特性

| 功能 | 说明 |
|------|------|
| 🛡️ **双重认证** | 客户端证书（第一关）+ 用户名密码（第二关），缺一不可 |
| ⚡ **4 个服务进程** | TUN-UDP / TUN-TCP / TAP-UDP / TAP-TCP，同端口不同协议 |
| 📁 **4 份客户端配置** | 每用户自动生成 4 份 `.ovpn` 文件 |
| 🚦 **按用户限速** | 下载用 OpenVPN shaper，上传用 tc+ifb，各自独立 |
| 🔢 **并发控制** | 限制同账号同时在线设备数，超出自动踢人 |
| 🌍 **IPv4/IPv6/双栈** | 全部支持，双栈指定具体 IP 时启用独立进程 |
| 🔄 **路由模式** | `split`（仅内网）或 `global`（所有流量），按用户设置 |
| 📋 **详细日志** | 认证、连接、会话、IP 分配日志，均带时间戳和用户信息 |
| 🔁 **开机自启** | 4 个 systemd 服务，服务器重启自动恢复 |
| 🗑️ **一键卸载** | 8 步彻底清除所有文件、服务、规则、软件包 |
| 🐧 **多发行版** | 自动检测系统类型和包管理器 |
| 🔑 **99 年证书** | 默认 99 年有效期，不用担心过期 |

---

## 支持的发行版

| 系列 | 发行版 | 包管理器 |
|------|--------|---------|
| **Debian 系** | Ubuntu 16.04–24.04、Debian 9–12、Kali、Raspberry Pi OS、Linux Mint | `apt` |
| **RHEL 系** | CentOS 6–9、Rocky Linux 8/9、AlmaLinux 8/9、RHEL 7–9、Fedora、Amazon Linux 2/2023 | `yum` / `dnf` |
| **Arch 系** | Arch Linux、Manjaro、EndeavourOS | `pacman` |
| **SUSE 系** | openSUSE Leap/Tumbleweed、SLES | `zypper` |
| **Alpine** | Alpine Linux 3.x | `apk` |

> 若仓库中没有 `easy-rsa 3.x`（如 CentOS 7），脚本会自动从 GitHub 下载安装 v3.1.7。

---

## 快速开始

```bash
# 1. 下载脚本
wget -O openvpn-manager.sh https://your-host/openvpn-manager.sh

# 2. 赋予执行权限
chmod +x openvpn-manager.sh

# 3. 安装（需要 root 权限）
sudo ./openvpn-manager.sh install

# 4. 创建第一个用户
sudo ./openvpn-manager.sh adduser
```

---

## 网络拓扑

```
公网
    │
光猫（192.168.1.1）── 端口映射 1194+1195 UDP+TCP ──►
    │
路由器（WAN: 192.168.1.2 / LAN: 192.168.0.1）── DMZ ──►
    │
VPN 服务器（192.168.0.49）← 在这台机器上运行本脚本
```

`split` 模式下，客户端连接后可以访问 `192.168.0.x`（内网）和 `192.168.1.x`（光猫网段）。

---

## 命令参考

```
sudo ./openvpn-manager.sh <命令>
```

### 安装与卸载

| 命令 | 说明 |
|------|------|
| `install` | 交互式 7 步安装向导 |
| `uninstall` | 8 步彻底卸载（输入 `YES` 确认） |

### 用户管理

| 命令 | 说明 |
|------|------|
| `adduser` | 创建新用户（6 步向导，生成 4 份 `.ovpn`） |
| `user list` | 列出所有用户 |
| `user info <用户名>` | 查看用户详情和在线会话 |
| `user disable <用户名>` | 禁用账号 |
| `user enable <用户名>` | 启用账号 |
| `user delete <用户名>` | 删除用户并吊销证书 |
| `user passwd <用户名>` | 修改密码 |
| `user kick <用户名>` | 踢出所有在线会话 |
| `user set-mode <用户名> <global\|split>` | 修改路由模式 |
| `user set-maxconn <用户名> <N>` | 设置最大并发设备数 |
| `user set-speed <用户名>` | 修改限速（交互式） |

### 日志查询

| 命令 | 说明 |
|------|------|
| `log online` | 当前在线用户 |
| `log conn [用户名] [行数]` | 连接/断开日志 |
| `log auth [用户名] [行数]` | 认证日志（含失败原因） |
| `log detail [用户名] [行数]` | 详细会话事件 |
| `log all [行数]` | 全部日志 |

### 服务管理

| 命令 | 说明 |
|------|------|
| `status` | 查看 4 个进程的运行状态 |
| `restart` | 重启全部 4 个进程 |

---

## 安装向导

7 步交互式安装：

| 步骤 | 内容 | 默认值 |
|------|------|--------|
| 1/7 | 安装目录 | `/www/OpenVPN` |
| 2/7 | TUN 端口 / TAP 端口 | `1194` / `1195` |
| 3/7 | 监听协议（IPv4/IPv6/双栈）+ 地址 | IPv4 / `0.0.0.0` |
| 4/7 | 服务器公网 IP 或域名（自动检测） | — |
| 5/7 | 证书有效期（年） | `99` |
| 6/7 | 确认安装 | — |
| 7/7 | 执行安装 + 创建第一个用户 | — |

**公网 IP 自动检测服务（按顺序尝试）：**
`ipv4.ddnsip.cn` → `api.ipify.org` → `icanhazip.com` → `api4.my-ip.io` → `ip4.seeip.org` → `ipecho.net/plain` → `myip.ipip.net` → `members.3322.org` → `4.ipw.cn` → `ip.tool.lu` → `ifconfig.me`

---

## 客户端配置文件

每个用户生成 4 份 `.ovpn` 文件，存放在 `/www/OpenVPN/clients/<用户名>/`：

| 文件 | 设备 | 协议 | 推荐场景 |
|------|------|------|---------|
| `*-tun-udp.ovpn` | tun | UDP | **首选** — 性能最佳，延迟最低 |
| `*-tun-tcp.ovpn` | tun | TCP | UDP 被防火墙封锁时的备选 |
| `*-tap-udp.ovpn` | tap | UDP | 二层桥接（局域网游戏、NetBIOS） |
| `*-tap-tcp.ovpn` | tap | TCP | TAP + 防火墙穿透 |

每份文件完全自包含（CA 证书、用户证书、用户私钥、TLS-Auth 密钥均已内嵌），用户导入后输入用户名和密码即可连接。

**推荐客户端：** [OpenVPN Connect](https://openvpn.net/client/)（Windows/macOS/iOS/Android）

> ⚠️ 日常使用建议选 UDP 配置 — TCP over TCP 会导致双重重传开销，速度明显下降。

---

## 服务端架构

```
VPN 服务器
├── openvpn-tun-udp.service  端口 1194/UDP  子网 10.8.0.0/24
├── openvpn-tun-tcp.service  端口 1194/TCP  子网 10.8.1.0/24
├── openvpn-tap-udp.service  端口 1195/UDP  子网 10.9.0.0/24
└── openvpn-tap-tcp.service  端口 1195/TCP  子网 10.9.1.0/24
```

每个进程独立使用一个 `/24` 子网，避免多个进程绑定同一子网时产生的 ARP 混乱和回包路径不唯一问题。

---

## 认证机制

```
客户端发起连接
    │
    ▼
【第一关】TLS 握手 + 客户端证书验证
    ├── 证书无效 / 非本 CA 签发  →  拒绝（不弹密码框）
    ├── 证书已吊销（在 CRL 中）  →  拒绝
    └── 证书有效 ─────────────────────────────────────────────►
                                                              │
                                                              ▼
                                               【第二关】用户名 + 密码验证
                                                   ├── 用户不存在  →  拒绝
                                                   ├── 账号已禁用  →  拒绝
                                                   ├── 密码错误    →  拒绝
                                                   └── 验证通过  ──►  连接建立
```

密码以 **SHA-256 + 随机 salt** 哈希存储，明文不落盘。

---

## 路由模式

### split（分流，默认）
只有访问内网的流量走 VPN，上网流量走本地，不影响正常网速。

```
push "route 192.168.0.0 255.255.255.0"
push "route 192.168.1.0 255.255.255.0"
```

### global（全局）
所有流量（含上网）均通过 VPN 服务端转发。

```
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
```

修改模式：`sudo ./openvpn-manager.sh user set-mode alice global`

---

## 限速机制

| 方向 | 方式 | 备注 |
|------|------|------|
| 下载（服务端→客户端） | OpenVPN `shaper`（写入 CCD 文件） | 下次重连生效，断开后自动失效 |
| 上传（客户端→服务端） | `tc + ifb` 整形 VPN 接口 | 绑定接口名，不依赖 IP |

**速度格式：** `10mbit` / `512kbit` / `1gbit` / `0` 或直接回车 = 不限速

---

## 并发登录控制

| 设置 | 行为 |
|------|------|
| `maxconn = 1` | 新设备登录时，向旧会话发送 SIGHUP 将其踢出 |
| `maxconn > 1` | 超出上限时，随机踢出一个现有会话 |

会话文件位于：`/www/OpenVPN/etc/openvpn/sessions/<用户名>.sessions`

---

## 目录结构

```
/www/OpenVPN/
├── clients/<用户名>/          # 每用户 4 份 .ovpn
├── easy-rsa/pki/              # CA、证书、私钥、CRL
├── etc/openvpn/
│   ├── server-tun-udp.conf    # 4 个服务端配置
│   ├── server-tun-tcp.conf
│   ├── server-tap-udp.conf
│   ├── server-tap-tcp.conf
│   ├── users.db               # 用户数据库（权限 600）
│   ├── ccd-tun/ ccd-tap/      # 每用户 CCD 文件
│   ├── sessions/              # 在线会话状态文件
│   └── scripts/               # 钩子脚本
│       ├── auth-user-pass.sh
│       ├── client-connect.sh
│       ├── client-disconnect.sh
│       ├── learn-address.sh
│       └── iptables-setup.sh
└── logs/
    ├── auth.log
    ├── connections.log
    ├── detail.log
    ├── address.log
    └── tun-udp.log  tun-tcp.log  tap-udp.log  tap-tcp.log
```

---

## 日志系统

| 文件 | 内容 |
|------|------|
| `auth.log` | AUTH_SUCCESS / AUTH_FAIL（含失败原因） |
| `connections.log` | CONNECT / DISCONNECT / KICK（含流量和时长） |
| `detail.log` | SESSION_START / SESSION_END |
| `address.log` | VPN IP 分配记录 |
| `*.log` | 各进程 OpenVPN 原始日志 |

```
[2026-06-27 10:05:00] AUTH_SUCCESS user=alice client_ip=1.2.3.4
[2026-06-27 10:05:01] CONNECT user=alice client_ip=1.2.3.4:45678 vpn_ip=10.8.0.2
[2026-06-27 10:06:00] KICK user=bob reason=single_device_limit kicked_ip=5.6.7.8 by=9.10.11.12
```

---

## 光猫与路由器配置

### 光猫端口映射（共 4 条规则）

| 协议 | 外部端口 | 内部 IP | 内部端口 |
|------|---------|--------|---------|
| UDP | 1194 | 192.168.1.2 | 1194 |
| TCP | 1194 | 192.168.1.2 | 1194 |
| UDP | 1195 | 192.168.1.2 | 1195 |
| TCP | 1195 | 192.168.1.2 | 1195 |

内部 IP 填路由器的 WAN 口地址，路由器的 DMZ 设置会将流量自动转发到 VPN 服务器。

### 路由器
将 `192.168.0.49`（VPN 服务器）设置为 **DMZ 主机**。

---

## 常见问题

**AUTH_FAIL — 用户不存在**
```bash
grep "^alice|status=" /www/OpenVPN/etc/openvpn/users.db
```

**"Failed to stat CRL file"**
```bash
chmod 644 /www/OpenVPN/etc/openvpn/crl.pem
systemctl restart openvpn-tun-udp openvpn-tun-tcp openvpn-tap-udp openvpn-tap-tcp
```

**连接成功但访问不了内网**
```bash
cat /proc/sys/net/ipv4/ip_forward              # 必须为 1
iptables -t nat -L POSTROUTING -n -v           # NAT 规则必须存在
grep "^push" /www/OpenVPN/etc/openvpn/server-tun-udp.conf
```

**网速慢**
- 优先使用 `tun-udp` — 速度最快
- 检查压缩配置：应为 `allow-compression asym`，而非 `comp-lzo adaptive`

**更换服务器 IP/域名后重新生成配置**
```bash
sudo ./openvpn-manager.sh user set-mode alice split
```

---

## 备份与恢复

```bash
# 备份（包含所有证书、配置、用户数据）
tar -czf openvpn-backup-$(date +%Y%m%d).tar.gz /www/OpenVPN

# 恢复
tar -xzf openvpn-backup-20260627.tar.gz -C /
systemctl restart openvpn-tun-udp openvpn-tun-tcp openvpn-tap-udp openvpn-tap-tcp
```

---

## 安全建议

1. **定期更换密码** — `user passwd <用户名>`
2. **及时删除闲置账号** — `user delete <用户名>` 同时吊销证书
3. **关注认证失败日志** — `log auth` 可发现暴力破解迹象
4. **备份 PKI** — 丢失 `easy-rsa/pki/` 意味着丢失所有证书，无法找回
5. **保持系统更新** — `apt upgrade openvpn`（或对应命令）
6. **妥善保管 .ovpn 文件** — 提醒用户不要随意分享配置文件

---

## 许可证

[MIT](../LICENSE)
