<div align="center">

[English](../README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | **日本語** | [한국어](README.ko.md) | [Русский](README.ru.md)

</div>

---

# OpenVPN 管理スクリプト

> フル機能の OpenVPN サーバー管理スクリプト — ワンコマンドでデプロイ、ユーザー管理、速度制限、二要素認証、IPv4/IPv6 デュアルスタック対応。すべての主要 Linux ディストリビューションをサポート。

<div align="center">

![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)
![OpenVPN](https://img.shields.io/badge/OpenVPN-2.5%2B-orange)
![Platform](https://img.shields.io/badge/Platform-Linux-lightgrey?logo=linux)

</div>

---

## 目次

- [機能](#機能)
- [対応ディストリビューション](#対応ディストリビューション)
- [クイックスタート](#クイックスタート)
- [ネットワーク構成](#ネットワーク構成)
- [コマンドリファレンス](#コマンドリファレンス)
- [インストールウィザード](#インストールウィザード)
- [クライアント設定ファイル](#クライアント設定ファイル)
- [サーバーアーキテクチャ](#サーバーアーキテクチャ)
- [認証フロー](#認証フロー)
- [ルーティングモード](#ルーティングモード)
- [速度制限](#速度制限)
- [同時接続制御](#同時接続制御)
- [ディレクトリ構造](#ディレクトリ構造)
- [ログシステム](#ログシステム)
- [ルーター設定](#ルーター設定)
- [トラブルシューティング](#トラブルシューティング)
- [バックアップと復元](#バックアップと復元)
- [セキュリティ注意事項](#セキュリティ注意事項)

---

## 機能

| 機能 | 説明 |
|------|------|
| 🛡️ **二要素認証** | クライアント証明書（第1段階）+ ユーザー名/パスワード（第2段階） |
| ⚡ **4つのサーバープロセス** | TUN-UDP / TUN-TCP / TAP-UDP / TAP-TCP |
| 📁 **4つのクライアント設定** | ユーザーごとに4つの `.ovpn` ファイルを自動生成 |
| 🚦 **ユーザーごとの速度制限** | ダウンロードは shaper、アップロードは tc+ifb |
| 🔢 **同時接続制御** | 同一アカウントの同時デバイス数を制限 |
| 🌍 **IPv4/IPv6/デュアルスタック** | すべてのモードに対応 |
| 🔄 **ルーティングモード** | `split`（LANのみ）または `global`（全トラフィック） |
| 📋 **詳細ログ** | 認証、接続、セッション、IPアドレス割り当てログ |
| 🔁 **自動起動** | 4つの systemd サービス |
| 🗑️ **完全アンインストール** | 8ステップで完全削除 |
| 🐧 **マルチディストリビューション** | OSとパッケージマネージャーを自動検出 |
| 🔑 **99年証明書** | デフォルト有効期限99年 |

---

## 対応ディストリビューション

| 系列 | ディストリビューション | パッケージマネージャー |
|------|----------------------|----------------------|
| **Debian系** | Ubuntu 16.04–24.04、Debian 9–12、Kali、Raspberry Pi OS | `apt` |
| **RHEL系** | CentOS 6–9、Rocky Linux 8/9、AlmaLinux 8/9、RHEL 7–9、Fedora、Amazon Linux 2/2023 | `yum` / `dnf` |
| **Arch系** | Arch Linux、Manjaro、EndeavourOS | `pacman` |
| **SUSE系** | openSUSE Leap/Tumbleweed、SLES | `zypper` |
| **Alpine** | Alpine Linux 3.x | `apk` |

---

## クイックスタート

```bash
# 1. ダウンロード
wget -O openvpn-manager.sh https://your-host/openvpn-manager.sh

# 2. 実行権限を付与
chmod +x openvpn-manager.sh

# 3. インストール（root権限が必要）
sudo ./openvpn-manager.sh install

# 4. 最初のユーザーを作成
sudo ./openvpn-manager.sh adduser
```

---

## ネットワーク構成

```
インターネット
    │
モデム（192.168.1.1）── ポートフォワード 1194+1195 UDP+TCP ──►
    │
ルーター（WAN: 192.168.1.2 / LAN: 192.168.0.1）── DMZ ──►
    │
VPN サーバー（192.168.0.49）← このスクリプトをここで実行
```

---

## コマンドリファレンス

### インストール / アンインストール

| コマンド | 説明 |
|---------|------|
| `install` | 7ステップのインタラクティブインストール |
| `uninstall` | 8ステップの完全削除（`YES` で確認） |

### ユーザー管理

| コマンド | 説明 |
|---------|------|
| `adduser` | 新しいユーザーを作成 |
| `user list` | 全ユーザーを一覧表示 |
| `user info <名前>` | ユーザー詳細とアクティブセッション |
| `user disable <名前>` | アカウントを無効化 |
| `user enable <名前>` | アカウントを有効化 |
| `user delete <名前>` | ユーザーを削除し証明書を失効 |
| `user passwd <名前>` | パスワードを変更 |
| `user kick <名前>` | 全アクティブセッションを切断 |
| `user set-mode <名前> <global\|split>` | ルーティングモードを変更 |
| `user set-maxconn <名前> <N>` | 最大同時接続デバイス数を設定 |
| `user set-speed <名前>` | 速度制限を変更 |

### ログ

| コマンド | 説明 |
|---------|------|
| `log online` | 現在接続中のユーザー |
| `log conn [名前] [行数]` | 接続/切断ログ |
| `log auth [名前] [行数]` | 認証ログ |
| `log detail [名前] [行数]` | 詳細セッションイベント |
| `log all [行数]` | 全ログ |

### サービス

| コマンド | 説明 |
|---------|------|
| `status` | 4つのプロセスの状態を表示 |
| `restart` | 4つのプロセスを再起動 |

---

## インストールウィザード

| ステップ | 設定内容 | デフォルト値 |
|---------|---------|------------|
| 1/7 | インストールディレクトリ | `/www/OpenVPN` |
| 2/7 | TUNポート / TAPポート | `1194` / `1195` |
| 3/7 | リッスンプロトコル + アドレス | IPv4 / `0.0.0.0` |
| 4/7 | 公開IP またはドメイン（自動検出） | — |
| 5/7 | 証明書有効期間（年） | `99` |
| 6/7 | インストールの確認 | — |
| 7/7 | インストール実行 + 最初のユーザー作成 | — |

---

## クライアント設定ファイル

ユーザーごとに4つの `.ovpn` ファイルが `/www/OpenVPN/clients/<ユーザー名>/` に生成されます：

| ファイル | デバイス | プロトコル | 推奨用途 |
|---------|---------|---------|---------|
| `*-tun-udp.ovpn` | tun | UDP | **最推奨** — 最高のパフォーマンス |
| `*-tun-tcp.ovpn` | tun | TCP | UDPがブロックされた場合の代替 |
| `*-tap-udp.ovpn` | tap | UDP | レイヤー2ブリッジ |
| `*-tap-tcp.ovpn` | tap | TCP | TAP + ファイアウォール回避 |

---

## サーバーアーキテクチャ

```
VPN サーバー
├── openvpn-tun-udp.service  ポート 1194/UDP  サブネット 10.8.0.0/24
├── openvpn-tun-tcp.service  ポート 1194/TCP  サブネット 10.8.1.0/24
├── openvpn-tap-udp.service  ポート 1195/UDP  サブネット 10.9.0.0/24
└── openvpn-tap-tcp.service  ポート 1195/TCP  サブネット 10.9.1.0/24
```

各プロセスは独自の `/24` サブネットを使用してARPの競合を防止します。

---

## 認証フロー

```
クライアントが接続
    │
    ▼
【第1段階】TLS + クライアント証明書の検証
    ├── 無効な証明書         → 拒否
    ├── 失効済み証明書       → 拒否
    └── 有効 ─────────────────────────────────────►
                                                  │
                                                  ▼
                                   【第2段階】ユーザー名 + パスワード
                                       ├── ユーザーが存在しない → 拒否
                                       ├── アカウント無効       → 拒否
                                       ├── パスワードが違う     → 拒否
                                       └── OK ──────────────►  接続確立
```

パスワードは **SHA-256 + ランダムソルト** でハッシュ化。平文は保存されません。

---

## ルーティングモード

### split（デフォルト）
LANトラフィックのみVPNを経由。インターネットトラフィックはローカル接続を使用。

### global
すべてのトラフィック（インターネット含む）がVPNを経由。

モード変更：`sudo ./openvpn-manager.sh user set-mode alice global`

---

## 速度制限

**フォーマット：** `10mbit` / `512kbit` / `1gbit` / `0` または Enter = 無制限

---

## バックアップと復元

```bash
# バックアップ
tar -czf openvpn-backup-$(date +%Y%m%d).tar.gz /www/OpenVPN

# 復元
tar -xzf openvpn-backup-20260627.tar.gz -C /
systemctl restart openvpn-tun-udp openvpn-tun-tcp openvpn-tap-udp openvpn-tap-tcp
```

---

## ライセンス

[MIT](../LICENSE)
