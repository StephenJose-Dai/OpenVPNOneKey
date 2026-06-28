<img src="https://www.president.gov.tw/images/president/flag.jpg" width="221" height="148">

<div align="center">

**[English](README.md)** | [简体中文](docs/README.zh-CN.md) | [繁體中文](docs/README.zh-TW.md) | [日本語](docs/README.ja.md) | [한국어](docs/README.ko.md) | [Русский](docs/README.ru.md)

</div>

---

# OpenVPN Manager

> A full-featured OpenVPN server management script — deploy, manage users, speed limits, dual authentication, IPv4/IPv6 dual-stack, all major Linux distributions.

<div align="center">

![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)
![OpenVPN](https://img.shields.io/badge/OpenVPN-2.5%2B-orange)
![Platform](https://img.shields.io/badge/Platform-Linux-lightgrey?logo=linux)

</div>

---

## Table of Contents

- [Features](#features)
- [Supported Distributions](#supported-distributions)
- [Quick Start](#quick-start)
- [Network Topology](#network-topology)
- [Commands](#commands)
- [Install Wizard](#install-wizard)
- [Client Config Files](#client-config-files)
- [Server Architecture](#server-architecture)
- [Authentication](#authentication)
- [Routing Modes](#routing-modes)
- [Speed Limiting](#speed-limiting)
- [Concurrent Login Control](#concurrent-login-control)
- [Directory Structure](#directory-structure)
- [Log System](#log-system)
- [Modem / Router Setup](#modem--router-setup)
- [Troubleshooting](#troubleshooting)
- [Backup & Restore](#backup--restore)
- [Security Notes](#security-notes)

---

## Features

| Feature | Description |
|---------|-------------|
| 🛡️ **Dual Authentication** | Client certificate (1st) + username/password (2nd). Both required. |
| ⚡ **4 Server Processes** | TUN-UDP / TUN-TCP / TAP-UDP / TAP-TCP, same port different protocol |
| 📁 **4 Client Configs** | Auto-generates 4 `.ovpn` files per user |
| 🚦 **Per-User Speed Limits** | Download via shaper, upload via tc+ifb |
| 🔢 **Concurrent Control** | Limit simultaneous devices, auto-kick when exceeded |
| 🌍 **IPv4 / IPv6 / Dual-stack** | All modes, specific IPs use separate processes |
| 🔄 **Routing Modes** | `split` (LAN only) or `global` (all traffic) per user |
| 📋 **Detailed Logging** | Auth, connection, session, IP allocation logs |
| 🔁 **Systemd Autostart** | 4 systemd services, start on boot |
| 🗑️ **Full Uninstall** | 8-step clean removal |
| 🐧 **Multi-Distro** | Auto-detects OS and package manager |
| 🔑 **99-Year Certs** | Default 99-year validity, no expiry surprises |

---

## Supported Distributions

| Family | Distributions | Package Manager |
|--------|--------------|----------------|
| **Debian** | Ubuntu 16.04–24.04, Debian 9–12, Kali, Raspberry Pi OS, Linux Mint | `apt` |
| **RHEL** | CentOS 6–9, Rocky 8/9, AlmaLinux 8/9, RHEL 7–9, Fedora, Amazon Linux 2/2023 | `yum` / `dnf` |
| **Arch** | Arch Linux, Manjaro, EndeavourOS | `pacman` |
| **SUSE** | openSUSE Leap/Tumbleweed, SLES | `zypper` |
| **Alpine** | Alpine Linux 3.x | `apk` |

> If `easy-rsa 3.x` is unavailable in the repo (e.g. CentOS 7), the script automatically downloads v3.1.7 from GitHub.

---

## Quick Start

```bash
# 1. Download
wget https://github.com/StephenJose-Dai/OpenVPNOneKey/archive/refs/tags/V26.6.281056.zip

# 2. unzip
unzip V26.6.281056.zip

# 3. Make executable
cd OpenVPNOneKey-26.6.281056
chmod +x openvpn-manager.sh

# 4. Install (requires root)
sudo ./openvpn-manager.sh install

# 5. Create your first user
sudo ./openvpn-manager.sh adduser
```

---

## Network Topology

```
Internet
    │
Modem (192.168.1.1)  ── port-forward 1194+1195 UDP+TCP ──►
    │
Router (WAN: 192.168.1.2 / LAN: 192.168.0.1)  ── DMZ ──►
    │
VPN Server (192.168.0.49)   ← run this script here
```

In `split` mode, clients can reach `192.168.0.x` (LAN) and `192.168.1.x` (modem subnet) through the VPN.

---

## Commands

```
sudo ./openvpn-manager.sh <command>
```

### Install / Uninstall

| Command | Description |
|---------|-------------|
| `install` | Interactive 7-step install wizard |
| `uninstall` | 8-step full removal (type `YES` to confirm) |

### User Management

| Command | Description |
|---------|-------------|
| `adduser` | Create new user (6-step wizard) |
| `user list` | List all users |
| `user info <name>` | User details and active sessions |
| `user disable <name>` | Disable account |
| `user enable <name>` | Re-enable account |
| `user delete <name>` | Delete user and revoke certificate |
| `user passwd <name>` | Change password |
| `user kick <name>` | Disconnect all active sessions |
| `user set-mode <name> <global\|split>` | Change routing mode |
| `user set-maxconn <name> <N>` | Set max concurrent devices |
| `user set-speed <name>` | Change speed limits (interactive) |

### Logs

| Command | Description |
|---------|-------------|
| `log online` | Currently connected users |
| `log conn [user] [lines]` | Connection / disconnect log |
| `log auth [user] [lines]` | Auth success/failure log |
| `log detail [user] [lines]` | Detailed session events |
| `log all [lines]` | All logs combined |

### Services

| Command | Description |
|---------|-------------|
| `status` | Show status of all 4 processes |
| `restart` | Restart all 4 processes |

---

## Install Wizard

7-step interactive setup:

| Step | Setting | Default |
|------|---------|---------|
| 1/7 | Install directory | `/www/OpenVPN` |
| 2/7 | TUN port / TAP port | `1194` / `1195` |
| 3/7 | Listen protocol + address | IPv4 / `0.0.0.0` |
| 4/7 | Public IP or domain (auto-detected) | — |
| 5/7 | Certificate validity (years) | `99` |
| 6/7 | Confirm | — |
| 7/7 | Install + create first user | — |

**IP auto-detection services (in order):**
`ipv4.ddnsip.cn` → `api.ipify.org` → `icanhazip.com` → `api4.my-ip.io` → `ip4.seeip.org` → `ipecho.net/plain` → `myip.ipip.net` → `members.3322.org` → `4.ipw.cn` → `ip.tool.lu` → `ifconfig.me`

---

## Client Config Files

4 `.ovpn` files generated per user at `/www/OpenVPN/clients/<username>/`:

| File | Device | Protocol | Recommended Use |
|------|--------|----------|----------------|
| `*-tun-udp.ovpn` | tun | UDP | **Best performance** — use this first |
| `*-tun-tcp.ovpn` | tun | TCP | When UDP is blocked by firewall |
| `*-tap-udp.ovpn` | tap | UDP | Layer-2 bridging (LAN games, NetBIOS) |
| `*-tap-tcp.ovpn` | tap | TCP | TAP + firewall bypass |

Each file is self-contained (CA cert, user cert, user key, TLS-Auth key embedded).

**Recommended clients:** [OpenVPN Connect](https://openvpn.net/client/) (Windows/macOS/iOS/Android)

> ⚠️ Avoid TCP configs for daily use — TCP-over-TCP causes double retransmission overhead.

---

## Server Architecture

```
VPN Server
├── openvpn-tun-udp.service  port 1194/UDP  subnet 10.8.0.0/24
├── openvpn-tun-tcp.service  port 1194/TCP  subnet 10.8.1.0/24
├── openvpn-tap-udp.service  port 1195/UDP  subnet 10.9.0.0/24
└── openvpn-tap-tcp.service  port 1195/TCP  subnet 10.9.1.0/24
```

Each process has its own `/24` subnet to avoid ARP conflicts and ensure unique return paths.

---

## Authentication

```
Client connects
    │
    ▼
[Stage 1] TLS + Client Certificate
    ├── Invalid / not from this CA  → REJECT (no password prompt)
    ├── Revoked in CRL              → REJECT
    └── Valid ──────────────────────────────────────────────►
                                                            │
                                                            ▼
                                             [Stage 2] Username + Password
                                                 ├── Not found  → REJECT
                                                 ├── Disabled   → REJECT
                                                 ├── Wrong pass → REJECT
                                                 └── OK ──────► Connected
```

Passwords stored as **SHA-256 + random salt**. Plaintext never stored.

---

## Routing Modes

### split (default)
Only LAN traffic goes through VPN. Internet uses local connection.

```
push "route 192.168.0.0 255.255.255.0"
push "route 192.168.1.0 255.255.255.0"
```

### global
All traffic goes through VPN (including internet).

```
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
```

Change mode: `sudo ./openvpn-manager.sh user set-mode alice global`

---

## Speed Limiting

| Direction | Method | Notes |
|-----------|--------|-------|
| Download (server→client) | OpenVPN `shaper` in CCD | Takes effect on next reconnect |
| Upload (client→server) | `tc + ifb` on VPN interface | Bound to interface name, not IP |

**Format:** `10mbit` / `512kbit` / `1gbit` / `0` or Enter = unlimited

---

## Concurrent Login Control

| Setting | Behavior |
|---------|----------|
| `maxconn = 1` | New login kicks existing session (SIGHUP) |
| `maxconn > 1` | One random existing session is kicked when limit exceeded |

Session files: `/www/OpenVPN/etc/openvpn/sessions/<username>.sessions`

---

## Directory Structure

```
/www/OpenVPN/
├── clients/<username>/          # 4x .ovpn files per user
├── easy-rsa/pki/                # CA, certs, keys, CRL
├── etc/openvpn/
│   ├── server-tun-udp.conf      # 4 server configs
│   ├── server-tun-tcp.conf
│   ├── server-tap-udp.conf
│   ├── server-tap-tcp.conf
│   ├── users.db                 # User database (mode 600)
│   ├── ccd-tun/ ccd-tap/        # Per-user CCD files
│   ├── sessions/                # Active session state
│   └── scripts/                 # Hook scripts
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

## Log System

| File | Contents |
|------|----------|
| `auth.log` | AUTH_SUCCESS / AUTH_FAIL (with reason) |
| `connections.log` | CONNECT / DISCONNECT / KICK |
| `detail.log` | SESSION_START / SESSION_END |
| `address.log` | VPN IP allocation |
| `*.log` | Raw OpenVPN process output |

```
[2026-06-27 10:05:00] AUTH_SUCCESS user=alice client_ip=1.2.3.4
[2026-06-27 10:05:01] CONNECT user=alice client_ip=1.2.3.4:45678 vpn_ip=10.8.0.2
[2026-06-27 10:06:00] KICK user=bob reason=single_device_limit kicked_ip=5.6.7.8 by=9.10.11.12
```

---

## Modem / Router Setup

### Modem port forwarding (4 rules)

| Protocol | External Port | Internal IP | Internal Port |
|----------|--------------|-------------|---------------|
| UDP | 1194 | 192.168.1.2 | 1194 |
| TCP | 1194 | 192.168.1.2 | 1194 |
| UDP | 1195 | 192.168.1.2 | 1195 |
| TCP | 1195 | 192.168.1.2 | 1195 |

Internal IP = router WAN address. Router DMZ forwards everything to VPN server.

### Router
Set `192.168.0.49` as **DMZ host**.

---

## Troubleshooting

**AUTH_FAIL — user not found**
```bash
grep "^alice|status=" /www/OpenVPN/etc/openvpn/users.db
```

**"Failed to stat CRL file"**
```bash
chmod 644 /www/OpenVPN/etc/openvpn/crl.pem
systemctl restart openvpn-tun-udp openvpn-tun-tcp openvpn-tap-udp openvpn-tap-tcp
```

**Connected but can't reach LAN**
```bash
cat /proc/sys/net/ipv4/ip_forward              # must be 1
iptables -t nat -L POSTROUTING -n -v           # NAT rules must exist
grep "^push" /www/OpenVPN/etc/openvpn/server-tun-udp.conf
```

**Slow speed**
- Use `tun-udp` — fastest option
- Verify compression: should be `allow-compression asym`

**Re-generate .ovpn after changing server IP/domain**
```bash
sudo ./openvpn-manager.sh user set-mode alice split
```

---

## Backup & Restore

```bash
# Backup
tar -czf openvpn-backup-$(date +%Y%m%d).tar.gz /www/OpenVPN

# Restore
tar -xzf openvpn-backup-20260627.tar.gz -C /
systemctl restart openvpn-tun-udp openvpn-tun-tcp openvpn-tap-udp openvpn-tap-tcp
```

---

## Security Notes

1. **Rotate passwords** — `user passwd <name>`
2. **Delete unused accounts** — `user delete <name>` revokes cert too
3. **Monitor auth failures** — `log auth` reveals brute-force attempts
4. **Backup PKI** — losing `easy-rsa/pki/` means losing all certs
5. **Keep packages updated** — `apt upgrade openvpn` (or equivalent)
6. **Protect .ovpn files** — remind users not to share config files

---

## License

[MIT](LICENSE)

<div align="center">

If you found this project helpful, please give it a ⭐ Star!

[![Star History Chart](https://api.star-history.com/svg?repos=StephenJose-Dai/OpenVPNOneKey&type=Date)](https://star-history.com/#StephenJose-Dai/OpenVPNOneKey&Date)

</div>
