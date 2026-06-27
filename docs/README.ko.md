<div align="center">

[English](../README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | **한국어** | [Русский](README.ru.md)

</div>

---

# OpenVPN 관리 스크립트

> 완전한 기능의 OpenVPN 서버 관리 스크립트 — 원클릭 배포, 사용자 관리, 속도 제한, 이중 인증, IPv4/IPv6 듀얼 스택. 모든 주요 Linux 배포판을 지원합니다.

<div align="center">

![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)
![OpenVPN](https://img.shields.io/badge/OpenVPN-2.5%2B-orange)
![Platform](https://img.shields.io/badge/Platform-Linux-lightgrey?logo=linux)

</div>

---

## 목차

- [기능](#기능)
- [지원 배포판](#지원-배포판)
- [빠른 시작](#빠른-시작)
- [네트워크 토폴로지](#네트워크-토폴로지)
- [명령어 참조](#명령어-참조)
- [설치 마법사](#설치-마법사)
- [클라이언트 설정 파일](#클라이언트-설정-파일)
- [서버 아키텍처](#서버-아키텍처)
- [인증 흐름](#인증-흐름)
- [라우팅 모드](#라우팅-모드)
- [속도 제한](#속도-제한)
- [동시 접속 제어](#동시-접속-제어)
- [디렉토리 구조](#디렉토리-구조)
- [로그 시스템](#로그-시스템)
- [라우터 설정](#라우터-설정)
- [문제 해결](#문제-해결)
- [백업 및 복원](#백업-및-복원)
- [보안 권고사항](#보안-권고사항)

---

## 기능

| 기능 | 설명 |
|------|------|
| 🛡️ **이중 인증** | 클라이언트 인증서(1단계) + 사용자명/비밀번호(2단계) |
| ⚡ **4개 서버 프로세스** | TUN-UDP / TUN-TCP / TAP-UDP / TAP-TCP |
| 📁 **4개 클라이언트 설정** | 사용자당 4개의 `.ovpn` 파일 자동 생성 |
| 🚦 **사용자별 속도 제한** | 다운로드는 shaper, 업로드는 tc+ifb |
| 🔢 **동시 접속 제어** | 동일 계정의 동시 디바이스 수 제한 |
| 🌍 **IPv4/IPv6/듀얼 스택** | 모든 모드 지원 |
| 🔄 **라우팅 모드** | `split`(LAN만) 또는 `global`(전체 트래픽) |
| 📋 **상세 로그** | 인증, 연결, 세션, IP 할당 로그 |
| 🔁 **자동 시작** | 4개의 systemd 서비스 |
| 🗑️ **완전 삭제** | 8단계 완전 제거 |
| 🐧 **멀티 배포판** | OS 및 패키지 관리자 자동 감지 |
| 🔑 **99년 인증서** | 기본 유효기간 99년 |

---

## 지원 배포판

| 계열 | 배포판 | 패키지 관리자 |
|------|--------|-------------|
| **Debian 계열** | Ubuntu 16.04–24.04, Debian 9–12, Kali, Raspberry Pi OS, Linux Mint | `apt` |
| **RHEL 계열** | CentOS 6–9, Rocky Linux 8/9, AlmaLinux 8/9, RHEL 7–9, Fedora, Amazon Linux 2/2023 | `yum` / `dnf` |
| **Arch 계열** | Arch Linux, Manjaro, EndeavourOS | `pacman` |
| **SUSE 계열** | openSUSE Leap/Tumbleweed, SLES | `zypper` |
| **Alpine** | Alpine Linux 3.x | `apk` |

---

## 빠른 시작

```bash
# 1. 다운로드
wget -O openvpn-manager.sh https://your-host/openvpn-manager.sh

# 2. 실행 권한 부여
chmod +x openvpn-manager.sh

# 3. 설치 (root 권한 필요)
sudo ./openvpn-manager.sh install

# 4. 첫 번째 사용자 생성
sudo ./openvpn-manager.sh adduser
```

---

## 네트워크 토폴로지

```
인터넷
    │
모뎀 (192.168.1.1)  ── 포트 포워딩 1194+1195 UDP+TCP ──►
    │
라우터 (WAN: 192.168.1.2 / LAN: 192.168.0.1)  ── DMZ ──►
    │
VPN 서버 (192.168.0.49)   ← 이 스크립트를 여기서 실행
```

---

## 명령어 참조

### 설치 / 삭제

| 명령어 | 설명 |
|--------|------|
| `install` | 7단계 인터랙티브 설치 마법사 |
| `uninstall` | 8단계 완전 삭제 (`YES` 입력으로 확인) |

### 사용자 관리

| 명령어 | 설명 |
|--------|------|
| `adduser` | 새 사용자 생성 (6단계 마법사) |
| `user list` | 모든 사용자 목록 |
| `user info <이름>` | 사용자 상세 정보 및 활성 세션 |
| `user disable <이름>` | 계정 비활성화 |
| `user enable <이름>` | 계정 활성화 |
| `user delete <이름>` | 사용자 삭제 및 인증서 폐기 |
| `user passwd <이름>` | 비밀번호 변경 |
| `user kick <이름>` | 모든 활성 세션 강제 종료 |
| `user set-mode <이름> <global\|split>` | 라우팅 모드 변경 |
| `user set-maxconn <이름> <N>` | 최대 동시 디바이스 수 설정 |
| `user set-speed <이름>` | 속도 제한 변경 |

### 로그

| 명령어 | 설명 |
|--------|------|
| `log online` | 현재 접속 중인 사용자 |
| `log conn [이름] [줄수]` | 연결/해제 로그 |
| `log auth [이름] [줄수]` | 인증 로그 |
| `log detail [이름] [줄수]` | 세션 상세 이벤트 |
| `log all [줄수]` | 전체 로그 |

### 서비스

| 명령어 | 설명 |
|--------|------|
| `status` | 4개 프로세스 상태 표시 |
| `restart` | 4개 프로세스 재시작 |

---

## 설치 마법사

| 단계 | 설정 | 기본값 |
|------|------|--------|
| 1/7 | 설치 디렉토리 | `/www/OpenVPN` |
| 2/7 | TUN 포트 / TAP 포트 | `1194` / `1195` |
| 3/7 | 수신 프로토콜 + 주소 | IPv4 / `0.0.0.0` |
| 4/7 | 공인 IP 또는 도메인 (자동 감지) | — |
| 5/7 | 인증서 유효기간 (년) | `99` |
| 6/7 | 설치 확인 | — |
| 7/7 | 설치 실행 + 첫 번째 사용자 생성 | — |

---

## 클라이언트 설정 파일

사용자당 4개의 `.ovpn` 파일이 `/www/OpenVPN/clients/<사용자명>/`에 생성됩니다:

| 파일 | 디바이스 | 프로토콜 | 권장 용도 |
|------|---------|---------|---------|
| `*-tun-udp.ovpn` | tun | UDP | **최우선 권장** — 최고 성능 |
| `*-tun-tcp.ovpn` | tun | TCP | UDP가 차단된 경우 대안 |
| `*-tap-udp.ovpn` | tap | UDP | 레이어 2 브리징 |
| `*-tap-tcp.ovpn` | tap | TCP | TAP + 방화벽 우회 |

---

## 서버 아키텍처

```
VPN 서버
├── openvpn-tun-udp.service  포트 1194/UDP  서브넷 10.8.0.0/24
├── openvpn-tun-tcp.service  포트 1194/TCP  서브넷 10.8.1.0/24
├── openvpn-tap-udp.service  포트 1195/UDP  서브넷 10.9.0.0/24
└── openvpn-tap-tcp.service  포트 1195/TCP  서브넷 10.9.1.0/24
```

---

## 인증 흐름

```
클라이언트 연결 시도
    │
    ▼
【1단계】TLS + 클라이언트 인증서 검증
    ├── 유효하지 않은 인증서  →  거부
    ├── 폐기된 인증서         →  거부
    └── 유효 ─────────────────────────────────────────►
                                                      │
                                                      ▼
                                       【2단계】사용자명 + 비밀번호
                                           ├── 사용자 없음    →  거부
                                           ├── 계정 비활성화  →  거부
                                           ├── 비밀번호 틀림  →  거부
                                           └── 확인 ────────►  연결 성립
```

비밀번호는 **SHA-256 + 랜덤 솔트**로 해시 저장. 평문은 저장되지 않습니다.

---

## 라우팅 모드

### split (기본값)
LAN 트래픽만 VPN을 통과. 인터넷 트래픽은 로컬 연결 사용.

### global
모든 트래픽(인터넷 포함)이 VPN을 통과.

모드 변경: `sudo ./openvpn-manager.sh user set-mode alice global`

---

## 속도 제한

**형식:** `10mbit` / `512kbit` / `1gbit` / `0` 또는 Enter = 무제한

---

## 백업 및 복원

```bash
# 백업
tar -czf openvpn-backup-$(date +%Y%m%d).tar.gz /www/OpenVPN

# 복원
tar -xzf openvpn-backup-20260627.tar.gz -C /
systemctl restart openvpn-tun-udp openvpn-tun-tcp openvpn-tap-udp openvpn-tap-tcp
```

---

## 라이선스

[MIT](../LICENSE)
