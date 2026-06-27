<div align="center">

[English](../README.md) | [简体中文](README.zh-CN.md) | **繁體中文** | [日本語](README.ja.md) | [한국어](README.ko.md) | [Русский](README.ru.md)

</div>

---

# OpenVPN 管理腳本

> 全功能 OpenVPN 伺服器管理腳本 — 一鍵部署、使用者管理、限速、雙重認證、IPv4/IPv6 雙棧，支援所有主流 Linux 發行版。

<div align="center">

![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)
![OpenVPN](https://img.shields.io/badge/OpenVPN-2.5%2B-orange)
![Platform](https://img.shields.io/badge/Platform-Linux-lightgrey?logo=linux)

</div>

---

## 目錄

- [功能特性](#功能特性)
- [支援的發行版](#支援的發行版)
- [快速開始](#快速開始)
- [網路拓撲](#網路拓撲)
- [指令參考](#指令參考)
- [安裝精靈](#安裝精靈)
- [用戶端設定檔](#用戶端設定檔)
- [伺服器架構](#伺服器架構)
- [認證機制](#認證機制)
- [路由模式](#路由模式)
- [限速機制](#限速機制)
- [並發登入控制](#並發登入控制)
- [目錄結構](#目錄結構)
- [日誌系統](#日誌系統)
- [數據機與路由器設定](#數據機與路由器設定)
- [常見問題](#常見問題)
- [備份與還原](#備份與還原)
- [安全建議](#安全建議)

---

## 功能特性

| 功能 | 說明 |
|------|------|
| 🛡️ **雙重認證** | 用戶端憑證（第一關）+ 使用者名稱密碼（第二關），缺一不可 |
| ⚡ **4 個伺服器程序** | TUN-UDP / TUN-TCP / TAP-UDP / TAP-TCP，同埠號不同協議 |
| 📁 **4 份用戶端設定** | 每位使用者自動產生 4 份 `.ovpn` 檔案 |
| 🚦 **按使用者限速** | 下載用 OpenVPN shaper，上傳用 tc+ifb，各自獨立 |
| 🔢 **並發控制** | 限制同帳號同時上線裝置數，超出自動踢人 |
| 🌍 **IPv4/IPv6/雙棧** | 全部支援，雙棧指定具體 IP 時啟用獨立程序 |
| 🔄 **路由模式** | `split`（僅內網）或 `global`（所有流量），按使用者設定 |
| 📋 **詳細日誌** | 認證、連線、會話、IP 分配日誌 |
| 🔁 **開機自啟** | 4 個 systemd 服務，伺服器重啟自動恢復 |
| 🗑️ **一鍵解除安裝** | 8 步徹底清除所有檔案、服務、規則、套件 |
| 🐧 **多發行版** | 自動偵測系統類型和套件管理器 |
| 🔑 **99 年憑證** | 預設 99 年有效期，不用擔心過期 |

---

## 支援的發行版

| 系列 | 發行版 | 套件管理器 |
|------|--------|-----------|
| **Debian 系** | Ubuntu 16.04–24.04、Debian 9–12、Kali、Raspberry Pi OS、Linux Mint | `apt` |
| **RHEL 系** | CentOS 6–9、Rocky Linux 8/9、AlmaLinux 8/9、RHEL 7–9、Fedora、Amazon Linux 2/2023 | `yum` / `dnf` |
| **Arch 系** | Arch Linux、Manjaro、EndeavourOS | `pacman` |
| **SUSE 系** | openSUSE Leap/Tumbleweed、SLES | `zypper` |
| **Alpine** | Alpine Linux 3.x | `apk` |

> 若套件庫中沒有 `easy-rsa 3.x`（如 CentOS 7），腳本會自動從 GitHub 下載安裝 v3.1.7。

---

## 快速開始

```bash
# 1. 下載腳本
wget -O openvpn-manager.sh https://your-host/openvpn-manager.sh

# 2. 賦予執行權限
chmod +x openvpn-manager.sh

# 3. 安裝（需要 root 權限）
sudo ./openvpn-manager.sh install

# 4. 建立第一個使用者
sudo ./openvpn-manager.sh adduser
```

---

## 網路拓撲

```
公網
    │
數據機（192.168.1.1）── 連接埠映射 1194+1195 UDP+TCP ──►
    │
路由器（WAN: 192.168.1.2 / LAN: 192.168.0.1）── DMZ ──►
    │
VPN 伺服器（192.168.0.49）← 在這台機器上執行本腳本
```

`split` 模式下，用戶端連線後可以存取 `192.168.0.x`（內網）和 `192.168.1.x`（數據機網段）。

---

## 指令參考

```
sudo ./openvpn-manager.sh <指令>
```

### 安裝與解除安裝

| 指令 | 說明 |
|------|------|
| `install` | 互動式 7 步安裝精靈 |
| `uninstall` | 8 步徹底解除安裝（輸入 `YES` 確認） |

### 使用者管理

| 指令 | 說明 |
|------|------|
| `adduser` | 建立新使用者（6 步精靈，產生 4 份 `.ovpn`） |
| `user list` | 列出所有使用者 |
| `user info <名稱>` | 查看使用者詳情和上線會話 |
| `user disable <名稱>` | 停用帳號 |
| `user enable <名稱>` | 啟用帳號 |
| `user delete <名稱>` | 刪除使用者並撤銷憑證 |
| `user passwd <名稱>` | 修改密碼 |
| `user kick <名稱>` | 踢出所有上線會話 |
| `user set-mode <名稱> <global\|split>` | 修改路由模式 |
| `user set-maxconn <名稱> <N>` | 設定最大並發裝置數 |
| `user set-speed <名稱>` | 修改限速（互動式） |

### 日誌查詢

| 指令 | 說明 |
|------|------|
| `log online` | 目前上線使用者 |
| `log conn [名稱] [行數]` | 連線/中斷日誌 |
| `log auth [名稱] [行數]` | 認證日誌（含失敗原因） |
| `log detail [名稱] [行數]` | 詳細會話事件 |
| `log all [行數]` | 全部日誌 |

### 服務管理

| 指令 | 說明 |
|------|------|
| `status` | 查看 4 個程序的執行狀態 |
| `restart` | 重新啟動全部 4 個程序 |

---

## 安裝精靈

7 步互動式安裝：

| 步驟 | 內容 | 預設值 |
|------|------|--------|
| 1/7 | 安裝目錄 | `/www/OpenVPN` |
| 2/7 | TUN 埠號 / TAP 埠號 | `1194` / `1195` |
| 3/7 | 監聽協議（IPv4/IPv6/雙棧）+ 位址 | IPv4 / `0.0.0.0` |
| 4/7 | 伺服器公網 IP 或網域（自動偵測） | — |
| 5/7 | 憑證有效期（年） | `99` |
| 6/7 | 確認安裝 | — |
| 7/7 | 執行安裝 + 建立第一個使用者 | — |

**公網 IP 自動偵測服務（按順序嘗試）：**
`ipv4.ddnsip.cn` → `api.ipify.org` → `icanhazip.com` → `api4.my-ip.io` → `ip4.seeip.org` → `ipecho.net/plain` → `myip.ipip.net` → `members.3322.org` → `4.ipw.cn` → `ip.tool.lu` → `ifconfig.me`

---

## 用戶端設定檔

每位使用者產生 4 份 `.ovpn` 檔案，存放於 `/www/OpenVPN/clients/<使用者名稱>/`：

| 檔案 | 裝置 | 協議 | 建議使用場景 |
|------|------|------|------------|
| `*-tun-udp.ovpn` | tun | UDP | **首選** — 效能最佳，延遲最低 |
| `*-tun-tcp.ovpn` | tun | TCP | UDP 被防火牆封鎖時的備選 |
| `*-tap-udp.ovpn` | tap | UDP | 二層橋接（區域網路遊戲、NetBIOS） |
| `*-tap-tcp.ovpn` | tap | TCP | TAP + 防火牆穿透 |

每份檔案完全自包含（CA 憑證、使用者憑證、使用者私鑰、TLS-Auth 金鑰均已內嵌）。

**推薦用戶端：** [OpenVPN Connect](https://openvpn.net/client/)（Windows/macOS/iOS/Android）

---

## 伺服器架構

```
VPN 伺服器
├── openvpn-tun-udp.service  埠號 1194/UDP  子網路 10.8.0.0/24
├── openvpn-tun-tcp.service  埠號 1194/TCP  子網路 10.8.1.0/24
├── openvpn-tap-udp.service  埠號 1195/UDP  子網路 10.9.0.0/24
└── openvpn-tap-tcp.service  埠號 1195/TCP  子網路 10.9.1.0/24
```

每個程序獨立使用一個 `/24` 子網路，避免多個程序綁定同一子網路時產生的 ARP 混亂問題。

---

## 認證機制

```
用戶端發起連線
    │
    ▼
【第一關】TLS 握手 + 用戶端憑證驗證
    ├── 憑證無效 / 非本 CA 簽發  →  拒絕（不彈出密碼框）
    ├── 憑證已撤銷（在 CRL 中）  →  拒絕
    └── 憑證有效 ─────────────────────────────────────►
                                                      │
                                                      ▼
                                       【第二關】使用者名稱 + 密碼驗證
                                           ├── 使用者不存在  →  拒絕
                                           ├── 帳號已停用    →  拒絕
                                           ├── 密碼錯誤      →  拒絕
                                           └── 驗證通過    ──►  連線建立
```

密碼以 **SHA-256 + 隨機 salt** 雜湊儲存，明文不落盤。

---

## 路由模式

### split（分流，預設）
只有存取內網的流量走 VPN，上網流量走本地，不影響正常網速。

### global（全域）
所有流量（含上網）均透過 VPN 伺服器轉發。

修改模式：`sudo ./openvpn-manager.sh user set-mode alice global`

---

## 限速機制

| 方向 | 方式 | 備註 |
|------|------|------|
| 下載（伺服器→用戶端） | OpenVPN `shaper` | 下次重新連線生效 |
| 上傳（用戶端→伺服器） | `tc + ifb` 整形 | 綁定介面名稱，不依賴 IP |

**速度格式：** `10mbit` / `512kbit` / `1gbit` / `0` 或直接按 Enter = 不限速

---

## 並發登入控制

| 設定 | 行為 |
|------|------|
| `maxconn = 1` | 新裝置登入時踢出現有會話 |
| `maxconn > 1` | 超出上限時隨機踢出一個現有會話 |

---

## 目錄結構

```
/www/OpenVPN/
├── clients/<使用者名稱>/      # 每位使用者 4 份 .ovpn
├── easy-rsa/pki/              # CA、憑證、私鑰、CRL
├── etc/openvpn/
│   ├── server-tun-udp.conf    # 4 個伺服器設定
│   ├── server-tun-tcp.conf
│   ├── server-tap-udp.conf
│   ├── server-tap-tcp.conf
│   ├── users.db               # 使用者資料庫（權限 600）
│   ├── ccd-tun/ ccd-tap/      # 每位使用者 CCD 檔案
│   ├── sessions/              # 上線會話狀態檔案
│   └── scripts/               # 鉤子腳本
└── logs/
    ├── auth.log  connections.log  detail.log  address.log
    └── tun-udp.log  tun-tcp.log  tap-udp.log  tap-tcp.log
```

---

## 日誌系統

```
[2026-06-27 10:05:00] AUTH_SUCCESS user=alice client_ip=1.2.3.4
[2026-06-27 10:05:01] CONNECT user=alice client_ip=1.2.3.4:45678 vpn_ip=10.8.0.2
[2026-06-27 10:06:00] KICK user=bob reason=single_device_limit kicked_ip=5.6.7.8 by=9.10.11.12
```

---

## 數據機與路由器設定

### 數據機連接埠映射（共 4 條規則）

| 協議 | 外部埠號 | 內部 IP | 內部埠號 |
|------|---------|--------|---------|
| UDP | 1194 | 192.168.1.2 | 1194 |
| TCP | 1194 | 192.168.1.2 | 1194 |
| UDP | 1195 | 192.168.1.2 | 1195 |
| TCP | 1195 | 192.168.1.2 | 1195 |

### 路由器
將 `192.168.0.49` 設定為 **DMZ 主機**。

---

## 常見問題

**AUTH_FAIL — 使用者不存在**
```bash
grep "^alice|status=" /www/OpenVPN/etc/openvpn/users.db
```

**"Failed to stat CRL file"**
```bash
chmod 644 /www/OpenVPN/etc/openvpn/crl.pem
systemctl restart openvpn-tun-udp openvpn-tun-tcp openvpn-tap-udp openvpn-tap-tcp
```

**連線成功但存取不了內網**
```bash
cat /proc/sys/net/ipv4/ip_forward   # 必須為 1
iptables -t nat -L POSTROUTING -n -v
grep "^push" /www/OpenVPN/etc/openvpn/server-tun-udp.conf
```

---

## 備份與還原

```bash
# 備份
tar -czf openvpn-backup-$(date +%Y%m%d).tar.gz /www/OpenVPN

# 還原
tar -xzf openvpn-backup-20260627.tar.gz -C /
systemctl restart openvpn-tun-udp openvpn-tun-tcp openvpn-tap-udp openvpn-tap-tcp
```

---

## 安全建議

1. **定期更換密碼** — `user passwd <名稱>`
2. **及時刪除閒置帳號** — `user delete <名稱>` 同時撤銷憑證
3. **關注認證失敗日誌** — `log auth` 可發現暴力破解跡象
4. **備份 PKI** — 遺失 `easy-rsa/pki/` 代表遺失所有憑證
5. **保持系統更新** — `apt upgrade openvpn`（或對應指令）

---

## 授權條款

[MIT](../LICENSE)
