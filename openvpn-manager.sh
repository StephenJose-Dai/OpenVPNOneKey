#!/bin/bash
# =============================================================================
# OpenVPN 全功能管理脚本
# 服务端:4个进程(TUN-UDP/TUN-TCP/TAP-UDP/TAP-TCP),同port不同协议
# Client:每用户生成专属4份 .ovpn,存放在 clients/<Username>/ 目录下
# 认证:客户端证书(第一关)+ Username密码(第二关),双重认证
# 安装路径:默认 /www/OpenVPN(安装时可自定义)
# port:默认 1194(TUN)and 1195(TAP),安装时可自定义
# Services:openvpn-tun.service / openvpn-tap.service(含 socket,autostart)
# =============================================================================

set -euo pipefail

# ─── global路径(安装时由向导设置,非安装操作时从配置文件读取)─────────────────
# 默认值,Install wizard可覆盖
INSTALL_DIR="/www/OpenVPN"

# 以下路径由 INSTALL_DIR 派生,init_paths 函数统一初始化
OPENVPN_BASE=""
EASYRSA_DIR=""
PKI_DIR=""
CCD_DIR_TUN=""
CCD_DIR_TAP=""
CLIENT_DIR=""
SCRIPTS_DIR=""
LOG_DIR=""
SESSION_DIR=""
CONFIG_DB=""
SERVER_CONF_TUN=""
SERVER_CONF_TAP=""
SYSTEMD_TUN=""
SYSTEMD_TAP=""
SYSTEMD_TUN_SOCKET=""
SYSTEMD_TAP_SOCKET=""

# ─── port(安装时由向导设置)────────────────────────────────────────────────
PORT_TUN=1194
PORT_TAP=1195

# ─── Protocoland地址(安装时由向导设置)───────────────────────────────────────
# LISTEN_PROTO:    ipv4 / ipv6 / dual
# LISTEN_ADDR_V4:  IPv4 Listen addr,默认 0.0.0.0(所有IPv4网卡)
# LISTEN_ADDR_V6:  IPv6 Listen addr,默认 ::(所有IPv6网卡)
# dual Mode下若两个地址均为具体IP,则各跑独立进程分别绑定;
# 若任一为通配(0.0.0.0 / ::),则用 :: 单进程dual-stack绑定即可
LISTEN_PROTO="ipv4"
LISTEN_ADDR_V4="0.0.0.0"
LISTEN_ADDR_V6="::"

# ─── 网络 ─────────────────────────────────────────────────────────────────────
# 4个进程各用独立子网,避免多个进程绑同一IP导致ARP/路由混乱
VPN_SUBNET_TUN_UDP="10.8.0.0"    # TUN-UDP
VPN_SUBNET_TUN_TCP="10.8.1.0"    # TUN-TCP
VPN_SUBNET_TAP_UDP="10.9.0.0"    # TAP-UDP
VPN_SUBNET_TAP_TCP="10.9.1.0"    # TAP-TCP
VPN_MASK="255.255.255.0"
# 兼容旧引用
VPN_SUBNET_TUN="10.8.0.0"
VPN_MASK_TUN="255.255.255.0"
VPN_SUBNET_TAP="10.9.0.0"
VPN_MASK_TAP="255.255.255.0"

# 内网路由(用于splitMode推送)
LAN_SUBNET="192.168.0.0"
LAN_MASK="255.255.255.0"
MODEM_SUBNET="192.168.1.0"
MODEM_MASK="255.255.255.0"

# ─── 颜色 ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
title()   { echo -e "\n${BLUE}═══ $* ═══${NC}\n"; }

# =============================================================================
# 辅助函数
# =============================================================================

# 根据 INSTALL_DIR 初始化所有派生路径变量
init_paths() {
    OPENVPN_BASE="$INSTALL_DIR/etc/openvpn"
    EASYRSA_DIR="$INSTALL_DIR/easy-rsa"
    PKI_DIR="$EASYRSA_DIR/pki"
    CCD_DIR_TUN="$OPENVPN_BASE/ccd-tun"
    CCD_DIR_TAP="$OPENVPN_BASE/ccd-tap"
    CLIENT_DIR="$INSTALL_DIR/clients"
    SCRIPTS_DIR="$OPENVPN_BASE/scripts"
    LOG_DIR="$INSTALL_DIR/logs"
    SESSION_DIR="$OPENVPN_BASE/sessions"
    CONFIG_DB="$OPENVPN_BASE/users.db"
    # 4个进程配置文件(TUN/TAP 各有 UDP and TCP 进程,共用同一port号)
    SERVER_CONF_TUN="$OPENVPN_BASE/server-tun-udp.conf"      # TUN UDP process
    SERVER_CONF_TUN_TCP="$OPENVPN_BASE/server-tun-tcp.conf"  # TUN TCP process (same port)
    SERVER_CONF_TAP="$OPENVPN_BASE/server-tap-udp.conf"      # TAP UDP process
    SERVER_CONF_TAP_TCP="$OPENVPN_BASE/server-tap-tcp.conf"  # TAP TCP process (same port)
    SYSTEMD_TUN="/etc/systemd/system/openvpn-tun-udp.service"
    SYSTEMD_TUN_TCP="/etc/systemd/system/openvpn-tun-tcp.service"
    SYSTEMD_TAP="/etc/systemd/system/openvpn-tap-udp.service"
    SYSTEMD_TAP_TCP="/etc/systemd/system/openvpn-tap-tcp.service"
    SYSTEMD_TUN_SOCKET="/etc/systemd/system/openvpn-tun-udp.socket"
    SYSTEMD_TAP_SOCKET="/etc/systemd/system/openvpn-tap-udp.socket"
    # dual-stack双进程Mode(dual 且各指定具体IP时启用)
    SERVER_CONF_TUN_V4="$OPENVPN_BASE/server-tun-v4-udp.conf"
    SERVER_CONF_TUN_V6="$OPENVPN_BASE/server-tun-v6-udp.conf"
    SERVER_CONF_TAP_V4="$OPENVPN_BASE/server-tap-v4-udp.conf"
    SERVER_CONF_TAP_V6="$OPENVPN_BASE/server-tap-v6-udp.conf"
    SYSTEMD_TUN_V4="/etc/systemd/system/openvpn-tun-v4-udp.service"
    SYSTEMD_TUN_V6="/etc/systemd/system/openvpn-tun-v6-udp.service"
    SYSTEMD_TAP_V4="/etc/systemd/system/openvpn-tap-v4-udp.service"
    SYSTEMD_TAP_V6="/etc/systemd/system/openvpn-tap-v6-udp.service"
}

# 从已安装的配置文件读取 INSTALL_DIR / PORT_TUN / PORT_TAP
# 非安装命令(adduser,user,log 等)调用时自动加载
load_config() {
    # 尝试从默认位置或环境变量找到安装记录
    local cfg=""
    for try_dir in "$INSTALL_DIR" "/www/OpenVPN" "/opt/OpenVPN" "/usr/local/OpenVPN"; do
        local try_db="$try_dir/etc/openvpn/users.db"
        if [[ -f "$try_db" ]]; then
            cfg="$try_db"
            INSTALL_DIR="$try_dir"
            break
        fi
    done

    if [[ -z "$cfg" ]]; then
        # 还没安装过,先初始化默认路径
        init_paths
        return 0
    fi

    init_paths  # init paths with found INSTALL_DIR
    CONFIG_DB="$cfg"

    # 读取安装时保存的portand监听设置
    local saved_tun saved_tap saved_proto saved_addr
    saved_tun=$(grep -E "^_server_\|port_tun=" "$cfg" 2>/dev/null | tail -1 | cut -d= -f2-)
    saved_tap=$(grep -E "^_server_\|port_tap=" "$cfg" 2>/dev/null | tail -1 | cut -d= -f2-)
    saved_proto=$(grep -E "^_server_\|listen_proto=" "$cfg" 2>/dev/null | tail -1 | cut -d= -f2-)
    local saved_v4 saved_v6
    saved_v4=$(grep -E "^_server_\|listen_addr_v4=" "$cfg" 2>/dev/null | tail -1 | cut -d= -f2-)
    saved_v6=$(grep -E "^_server_\|listen_addr_v6=" "$cfg" 2>/dev/null | tail -1 | cut -d= -f2-)
    [[ -n "$saved_tun" ]]   && PORT_TUN="$saved_tun"
    [[ -n "$saved_tap" ]]   && PORT_TAP="$saved_tap"
    [[ -n "$saved_proto" ]] && LISTEN_PROTO="$saved_proto"
    [[ -n "$saved_v4" ]]    && LISTEN_ADDR_V4="$saved_v4"
    [[ -n "$saved_v6" ]]    && LISTEN_ADDR_V6="$saved_v6"
}

check_root() {
    [[ $EUID -eq 0 ]] || { error "Please run as root"; exit 1; }
}

detect_os() {
    # 读取系统标识文件,精确识别发行版and版本
    OS=""
    OS_VERSION=""
    OS_FAMILY=""   # debian / rhel / arch / suse / alpine
    PKG_MGR=""     # apt-get / apt / dnf / yum / pacman / zypper / apk

    # 优先读取标准化的 /etc/os-release
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        OS="${ID,,}"           # lowercase: ubuntu/debian/centos/rhel/fedora...
        OS_VERSION="${VERSION_ID:-}"
        OS_NAME="${NAME:-$ID}"
    elif [[ -f /etc/redhat-release ]]; then
        OS=$(sed "s/[ \t].*//;q" /etc/redhat-release | tr "[:upper:]" "[:lower:]")
        OS_VERSION=$(grep -oE "[0-9]+\.[0-9]+" /etc/redhat-release | head -1)
        OS_NAME=$(cat /etc/redhat-release)
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
        OS_VERSION=$(cat /etc/debian_version)
        OS_NAME="Debian $OS_VERSION"
    else
        error "Unsupported OS"
        exit 1
    fi

    # 根据 OS 判断家族and包管理器
    case "$OS" in
        ubuntu|debian|linuxmint|pop|elementary|kali|raspbian|devuan)
            OS_FAMILY="debian"
            # 优先用 apt,旧版用 apt-get
            if command -v apt &>/dev/null; then
                PKG_MGR="apt"
            else
                PKG_MGR="apt-get"
            fi
            ;;
        centos|rhel|rocky|almalinux|ol|scientific)
            OS_FAMILY="rhel"
            # CentOS/RHEL 8+ 用 dnf,7 及以下用 yum
            local ver_major="${OS_VERSION%%.*}"
            if [[ -n "$ver_major" ]] && (( ver_major >= 8 )) && command -v dnf &>/dev/null; then
                PKG_MGR="dnf"
            else
                PKG_MGR="yum"
            fi
            ;;
        fedora)
            OS_FAMILY="rhel"
            PKG_MGR="dnf"
            ;;
        arch|manjaro|endeavouros|garuda)
            OS_FAMILY="arch"
            PKG_MGR="pacman"
            ;;
        opensuse*|sles)
            OS_FAMILY="suse"
            PKG_MGR="zypper"
            ;;
        alpine)
            OS_FAMILY="alpine"
            PKG_MGR="apk"
            ;;
        amzn)
            # Amazon Linux 2 类似 RHEL 7,Amazon Linux 2023 类似 Fedora
            OS_FAMILY="rhel"
            local ver_major="${OS_VERSION%%.*}"
            if [[ "$ver_major" == "2023" ]] && command -v dnf &>/dev/null; then
                PKG_MGR="dnf"
            else
                PKG_MGR="yum"
            fi
            ;;
        *)
            # 兜底:按文件存在判断
            if command -v apt-get &>/dev/null; then
                OS_FAMILY="debian"; PKG_MGR="apt-get"
            elif command -v dnf &>/dev/null; then
                OS_FAMILY="rhel"; PKG_MGR="dnf"
            elif command -v yum &>/dev/null; then
                OS_FAMILY="rhel"; PKG_MGR="yum"
            elif command -v pacman &>/dev/null; then
                OS_FAMILY="arch"; PKG_MGR="pacman"
            elif command -v zypper &>/dev/null; then
                OS_FAMILY="suse"; PKG_MGR="zypper"
            elif command -v apk &>/dev/null; then
                OS_FAMILY="alpine"; PKG_MGR="apk"
            else
                error "No supported package manager found"
                exit 1
            fi
            ;;
    esac

    info "Detected OS: ${OS_NAME:-$OS} ${OS_VERSION}  (family: ${OS_FAMILY}, pkg mgr: ${PKG_MGR})"
}

get_public_ip() {
    local ip=""
    local timeout=4

    # Detection services (domestic + international)
    local services=(
        "https://ipv4.ddnsip.cn"
        "https://api.ipify.org"
        "https://icanhazip.com"
        "https://api4.my-ip.io/ip"
        "https://ip4.seeip.org"
        "https://ipecho.net/plain"
        "http://myip.ipip.net"
        "http://members.3322.org/dyndns/getip"
        "https://4.ipw.cn"
        "http://ip.tool.lu"
        "https://ifconfig.me"
    )

    # prefer curl, fallback to wget
    local fetch_cmd=""
    if command -v curl &>/dev/null; then
        fetch_cmd="curl"
    elif command -v wget &>/dev/null; then
        fetch_cmd="wget"
    fi

    if [[ -n "$fetch_cmd" ]]; then
        for url in "${services[@]}"; do
            if [[ "$fetch_cmd" == "curl" ]]; then
                ip=$(curl -s --max-time "$timeout" --connect-timeout 3 -4 \
                     "$url" 2>/dev/null) || ip=""
            else
                ip=$(wget -qO- --timeout="$timeout" --tries=1 \
                     "$url" 2>/dev/null) || ip=""
            fi
            ip=$(echo "$ip" | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" | head -1)
            if _is_public_ip "$ip"; then
                echo "$ip"
                return 0
            fi
        done
    fi

    # Fallback: guess from routing table (only works if server has public IP)
    local route_ip=""
    # Use cut instead of awk to avoid $7 being interpreted by bash under set -u
    route_ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP '(?<=src )\S+' | head -1) || route_ip=""
    if _is_public_ip "$route_ip"; then
        echo "$route_ip"
        return 0
    fi

    echo ""
    return 1
}

# 检查是否是合法的公网 IPv4 地址(排除私有/保留地址段)
_is_public_ip() {
    local ip="${1:-}"
    [[ -z "$ip" ]] && return 1
    # 基本格式检查
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    # 排除私有and保留地址
    [[ "$ip" =~ ^10\. ]]          && return 1
    [[ "$ip" =~ ^192\.168\. ]]    && return 1
    [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] && return 1
    [[ "$ip" =~ ^127\. ]]         && return 1
    [[ "$ip" =~ ^169\.254\. ]]    && return 1
    [[ "$ip" =~ ^0\. ]]           && return 1
    [[ "$ip" =~ ^255\. ]]         && return 1
    [[ "$ip" == "0.0.0.0" ]]      && return 1
    return 0
}

# users.db 格式:username|attr=value
db_get() {
    grep -E "^${1}\|${2}=" "$CONFIG_DB" 2>/dev/null | tail -1 | cut -d= -f2- || echo ""
}
db_set() {
    sed -i "/^${1}|${2}=/d" "$CONFIG_DB" 2>/dev/null || true
    echo "${1}|${2}=${3}" >> "$CONFIG_DB"
}
db_user_exists() {
    grep -q "^${1}|status=" "$CONFIG_DB" 2>/dev/null
}

# =============================================================================
# 安装依赖(覆盖主流 Linux 发行版新旧版本)
# =============================================================================

install_dependencies() {
    title "Installing dependencies"
    info "pkg mgr: $PKG_MGR  family: $OS_FAMILY"

    case "$OS_FAMILY" in
        # ── Debian 系(Ubuntu / Debian / Mint / Kali 等)────────────────────
        debian)
            $PKG_MGR update -qq 2>/dev/null || apt-get update -qq
            # easy-rsa 在 Debian 9 / Ubuntu 16.04 以下可能叫 easy-rsa 2.x
            # 尽量装 easy-rsa(3.x),Failed则后续手动处理
            $PKG_MGR install -y \
                openvpn \
                easy-rsa \
                iptables \
                curl \
                ca-certificates \
                openssl \
                iproute2 \
                net-tools \
                bridge-utils \
                2>/dev/null || true
            # 部分老版本 Ubuntu/Debian 没有 easy-rsa 包,用 wget 下载
            if ! command -v easyrsa &>/dev/null && \
               [[ ! -f /usr/share/easy-rsa/easyrsa ]]; then
                warn "easy-rsa not found, installing manually..."
                _install_easyrsa_manual
            fi
            ;;

        # ── RHEL 系(CentOS / Rocky / AlmaLinux / Fedora / Amazon Linux)────
        rhel)
            # EPEL 提供 openvpn and easy-rsa(CentOS/RHEL/Rocky/Alma 需要)
            # Fedora 自带,不需要 EPEL
            if [[ "$OS" != "fedora" && "$OS" != "amzn" ]]; then
                if [[ "$PKG_MGR" == "dnf" ]]; then
                    dnf install -y epel-release 2>/dev/null || \
                    dnf install -y \
                        "https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E %rhel).noarch.rpm" \
                        2>/dev/null || true
                    # RHEL 8+ 还需要启用 powertools / crb
                    local ver_major="${OS_VERSION%%.*}"
                    if (( ver_major >= 8 )); then
                        dnf config-manager --set-enabled powertools 2>/dev/null || \
                        dnf config-manager --set-enabled crb 2>/dev/null || true
                    fi
                else
                    yum install -y epel-release 2>/dev/null || true
                fi
            fi

            $PKG_MGR install -y \
                openvpn \
                easy-rsa \
                iptables \
                iptables-services \
                curl \
                ca-certificates \
                openssl \
                iproute \
                net-tools \
                bridge-utils \
                2>/dev/null || true

            # 部分 RHEL/CentOS 7 的 easy-rsa 是 2.x,需要手动装 3.x
            if ! command -v easyrsa &>/dev/null && \
               [[ ! -f /usr/share/easy-rsa/3/easyrsa ]] && \
               [[ ! -f /usr/share/easy-rsa/easyrsa ]]; then
                warn "easy-rsa 3.x not found, installing manually..."
                _install_easyrsa_manual
            fi

            # CentOS 7 / RHEL 7:启用并持久化 iptables
            if [[ "${OS_VERSION%%.*}" == "7" ]]; then
                systemctl enable iptables  2>/dev/null || true
                systemctl start  iptables  2>/dev/null || true
            fi
            ;;

        # ── Arch 系(Arch / Manjaro / EndeavourOS 等)────────────────────────
        arch)
            pacman -Sy --noconfirm \
                openvpn \
                easy-rsa \
                iptables \
                curl \
                openssl \
                iproute2 \
                net-tools \
                bridge-utils \
                2>/dev/null || true
            ;;

        # ── SUSE 系(openSUSE / SLES)────────────────────────────────────────
        suse)
            zypper --non-interactive refresh
            zypper --non-interactive install \
                openvpn \
                easy-rsa \
                iptables \
                curl \
                ca-certificates \
                openssl \
                iproute2 \
                net-tools \
                bridge-utils \
                2>/dev/null || true
            ;;

        # ── Alpine(轻量容器系统)────────────────────────────────────────────
        alpine)
            apk update
            apk add \
                openvpn \
                easy-rsa \
                iptables \
                curl \
                ca-certificates \
                openssl \
                iproute2 \
                net-tools \
                bridge \
                2>/dev/null || true
            ;;
    esac

    # 验证关键组件已安装
    local missing=()
    command -v openvpn  &>/dev/null || missing+=("openvpn")
    command -v openssl  &>/dev/null || missing+=("openssl")
    command -v iptables &>/dev/null || missing+=("iptables")
    command -v curl     &>/dev/null || missing+=("curl")

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Failed to install: ${missing[*]}"
        error "Please install manually and retry"
        exit 1
    fi

    success "Dependencies installed"
}

# 手动下载安装 easy-rsa 3.x(适用于包管理器没有或版本过旧的情况)
_install_easyrsa_manual() {
    local ver="3.1.7"
    local url="https://github.com/OpenVPN/easy-rsa/releases/download/v${ver}/EasyRSA-${ver}.tgz"
    local tmp="/tmp/easyrsa-${ver}.tgz"
    local dest="/usr/share/easy-rsa"

    info "Downloading easy-rsa v${ver}..."
    if curl -sL --max-time 30 "$url" -o "$tmp" 2>/dev/null; then
        mkdir -p "$dest"
        tar -xzf "$tmp" -C "$dest" --strip-components=1
        chmod +x "$dest/easyrsa"
        # 建立符号链接方便global调用
        ln -sf "$dest/easyrsa" /usr/local/bin/easyrsa 2>/dev/null || true
        rm -f "$tmp"
        success "easy-rsa v${ver} installed to: $dest"
    else
        error "Failed to download easy-rsa, check network"
        error "Or manually extract to /usr/share/easy-rsa/"
        exit 1
    fi
}

# =============================================================================
# 初始化目录
# =============================================================================

init_directories() {
    title "Initializing directories"
    for d in "$INSTALL_DIR" "$OPENVPN_BASE" \
              "$CCD_DIR_TUN" "$CCD_DIR_TAP" \
              "$CLIENT_DIR" "$SCRIPTS_DIR"; do
        mkdir -p "$d"
        chmod 750 "$d"
    done
    # logs and sessions:root 运行,755 足够
    for d in "$LOG_DIR" "$SESSION_DIR"; do
        mkdir -p "$d"
        chmod 755 "$d"
    done
    touch "$CONFIG_DB"
    chmod 600 "$CONFIG_DB"
    success "Directories created: $INSTALL_DIR"
}

# =============================================================================
# PKI 初始化(CA + 服务端证书,只生成一次)
# =============================================================================

init_pki() {
    local cert_years="${1:-99}"
    local cert_days=$(( cert_years * 365 ))
    title "Initializing PKI (validity ${cert_years}  years)"

    local easyrsa_bin=""
    for p in /usr/share/easy-rsa/easyrsa /usr/bin/easyrsa \
              /usr/local/share/easy-rsa/easyrsa; do
        [[ -x "$p" ]] && { easyrsa_bin="$p"; break; }
    done
    [[ -z "$easyrsa_bin" ]] && { error "easyrsa not found"; exit 1; }

    if [[ ! -d "$EASYRSA_DIR" ]]; then
        cp -r "$(dirname "$easyrsa_bin")" "$EASYRSA_DIR" 2>/dev/null || \
        cp -r /usr/share/easy-rsa "$EASYRSA_DIR" 2>/dev/null || true
        find "$EASYRSA_DIR" -name "easyrsa" | while IFS= read -r f; do chmod +x "$f"; done
    fi

    local easyrsa="$EASYRSA_DIR/easyrsa"
    [[ -x "$easyrsa" ]] || { error "EasyRSA not executable"; exit 1; }

    cat > "$EASYRSA_DIR/vars" <<VARS
set_var EASYRSA                 "$EASYRSA_DIR"
set_var EASYRSA_PKI             "$PKI_DIR"
set_var EASYRSA_DN              "cn_only"
set_var EASYRSA_REQ_COUNTRY     "CN"
set_var EASYRSA_REQ_PROVINCE    "Beijing"
set_var EASYRSA_REQ_CITY        "Beijing"
set_var EASYRSA_REQ_ORG         "MyVPN"
set_var EASYRSA_REQ_EMAIL       "admin@myvpn.local"
set_var EASYRSA_REQ_OU          "VPN"
set_var EASYRSA_CA_EXPIRE       ${cert_days}
set_var EASYRSA_CERT_EXPIRE     ${cert_days}
set_var EASYRSA_CRL_DAYS        ${cert_days}
set_var EASYRSA_KEY_SIZE        2048
set_var EASYRSA_DIGEST          "sha256"
set_var EASYRSA_BATCH           "1"
VARS

    if [[ -f "$PKI_DIR/ca.crt" ]]; then
        info "PKI already exists, skipping"
        return 0
    fi

    cd "$EASYRSA_DIR"
    EASYRSA_VARS_FILE="$EASYRSA_DIR/vars" "$easyrsa" init-pki
    info "Generating CA certificate(${cert_years}  years)..."
    EASYRSA_VARS_FILE="$EASYRSA_DIR/vars" "$easyrsa" --batch build-ca nopass
    info "Generating DH parameters(may take a few minutes)..."
    EASYRSA_VARS_FILE="$EASYRSA_DIR/vars" "$easyrsa" gen-dh
    info "Generating server certificate(shared by 4 processes)..."
    EASYRSA_VARS_FILE="$EASYRSA_DIR/vars" "$easyrsa" --batch build-server-full server nopass
    info "Generating TLS Auth key..."
    openvpn --genkey secret "$PKI_DIR/ta.key"
    info "Generating CRL..."
    EASYRSA_VARS_FILE="$EASYRSA_DIR/vars" "$easyrsa" gen-crl

    cp "$PKI_DIR/ca.crt"             "$OPENVPN_BASE/"
    cp "$PKI_DIR/issued/server.crt"  "$OPENVPN_BASE/"
    cp "$PKI_DIR/private/server.key" "$OPENVPN_BASE/"
    cp "$PKI_DIR/dh.pem"             "$OPENVPN_BASE/"
    cp "$PKI_DIR/ta.key"             "$OPENVPN_BASE/"
    cp "$PKI_DIR/crl.pem"            "$OPENVPN_BASE/"

    # 私钥只有 root 可读
    chmod 600 "$OPENVPN_BASE/server.key" "$OPENVPN_BASE/ta.key"
    # Public files (cert/CRL/DH) set to 644
    chmod 644 "$OPENVPN_BASE/ca.crt" "$OPENVPN_BASE/server.crt" \
              "$OPENVPN_BASE/dh.pem" "$OPENVPN_BASE/crl.pem"

    success "PKI initialized"
}

# =============================================================================
# 为用户签发独立客户端证书
# =============================================================================

create_user_cert() {
    local username="$1"
    local cert_years="${2:-99}"
    local cert_days=$(( cert_years * 365 ))
    local easyrsa="$EASYRSA_DIR/easyrsa"

    if [[ -f "$PKI_DIR/issued/${username}.crt" ]]; then
        info "Certificate already exists, skipping: $username"
        return 0
    fi
    info "Signing user cert: $username(${cert_years}  years)"
    cd "$EASYRSA_DIR"
    EASYRSA_CERT_EXPIRE="$cert_days" \
    EASYRSA_VARS_FILE="$EASYRSA_DIR/vars" \
    "$easyrsa" --batch build-client-full "$username" nopass
    success "Certificate issued: $username"
}

# =============================================================================
# 钩子脚本
# =============================================================================

generate_hook_scripts() {
    title "Generating hook scripts"

    # ── 认证脚本(via-env,OpenVPN 通过环境变量传入Username,密码,客户端IP)────────
    # heredoc 不加引号,$INSTALL_DIR 在生成时展开为实际安装路径,写死在脚本里
    cat > "$SCRIPTS_DIR/auth-user-pass.sh" <<'AUTH_SCRIPT'
#!/bin/bash
# OpenVPN 认证脚本,via-env Mode
# via-env 下 OpenVPN 通过环境变量传入:
#   $username   → Username
#   $password   → 密码
#   $trusted_ip → 客户端真实IP(via-file Mode下拿不到,via-env 才有)
INSTALL_DIR="__INSTALL_DIR__"
CONFIG_DB="$INSTALL_DIR/etc/openvpn/users.db"
AUTH_LOG="$INSTALL_DIR/logs/auth.log"
timestamp() { date "+%Y-%m-%d %H:%M:%S"; }
db_get() { grep -E "^${1}\|${2}=" "$CONFIG_DB" 2>/dev/null | tail -1 | cut -d= -f2- || echo ""; }

mkdir -p "$INSTALL_DIR/logs" 2>/dev/null || true

# via-env Mode:直接从环境变量读取,无需读文件
username="${username:-}"
password="${password:-}"
client_ip="${trusted_ip:-unknown}"
ts=$(timestamp)

stored_hash=$(db_get "$username" "password_hash")
if [[ -z "$stored_hash" ]]; then
    echo "[$ts] AUTH_FAIL user=${username} client_ip=${client_ip} reason=user_not_found" >> "$AUTH_LOG"
    exit 1
fi
acct_status=$(db_get "$username" "status")
if [[ "$acct_status" == "disabled" ]]; then
    echo "[$ts] AUTH_FAIL user=${username} client_ip=${client_ip} reason=account_disabled" >> "$AUTH_LOG"
    exit 1
fi
salt=$(db_get "$username" "salt")
input_hash=$(printf "%s" "${salt}${password}" | sha256sum | cut -d" " -f1)
if [[ "$input_hash" == "$stored_hash" ]]; then
    echo "[$ts] AUTH_SUCCESS user=${username} client_ip=${client_ip}" >> "$AUTH_LOG"
    exit 0
else
    echo "[$ts] AUTH_FAIL user=${username} client_ip=${client_ip} reason=wrong_password" >> "$AUTH_LOG"
    exit 1
fi
AUTH_SCRIPT
    sed -i "s|__INSTALL_DIR__|${INSTALL_DIR}|g" "$SCRIPTS_DIR/auth-user-pass.sh" 

    # ── client-connect(登录时:MaxConn检查 + 日志)─────────────────────────────
    cat > "$SCRIPTS_DIR/client-connect.sh" <<'CONNECT_SCRIPT'
#!/bin/bash
INSTALL_DIR="__INSTALL_DIR__"
SESSION_DIR="$INSTALL_DIR/etc/openvpn/sessions"
CONFIG_DB="$INSTALL_DIR/etc/openvpn/users.db"
LOG_FILE="$INSTALL_DIR/logs/connections.log"
DETAIL_LOG="$INSTALL_DIR/logs/detail.log"
timestamp() { date "+%Y-%m-%d %H:%M:%S"; }
db_get() { grep -E "^${1}\|${2}=" "$CONFIG_DB" 2>/dev/null | tail -1 | cut -d= -f2- || echo ""; }

USER="${common_name:-unknown}"
CLIENT_IP="${trusted_ip:-unknown}"
CLIENT_PORT="${trusted_port:-0}"
VPN_IP="${ifconfig_pool_remote_ip:-unknown}"
CONN_TIME=$(timestamp)
CONN_UNIX="${time_unix:-$(date +%s)}"

echo "[$CONN_TIME] CONNECT user=${USER} client_ip=${CLIENT_IP}:${CLIENT_PORT} vpn_ip=${VPN_IP}" >> "$LOG_FILE"

MAX_CONN=$(db_get "$USER" "max_conn")
MAX_CONN="${MAX_CONN:-1}"
SESSION_FILE="$SESSION_DIR/${USER}.sessions"
touch "$SESSION_FILE"
chmod 600 "$SESSION_FILE"

# 清理已失效会话
ALIVE=()
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    sess_pid=$(echo "$line" | cut -d"|" -f1)
    kill -0 "$sess_pid" 2>/dev/null && ALIVE+=("$line") || true
done < "$SESSION_FILE"

CURRENT=${#ALIVE[@]}
if (( CURRENT >= MAX_CONN )); then
    if (( MAX_CONN == 1 )); then
        OLD_PID=$(echo "${ALIVE[0]}" | cut -d"|" -f1)
        OLD_IP=$(echo "${ALIVE[0]}"  | cut -d"|" -f2)
        echo "[$CONN_TIME] KICK user=${USER} reason=single_device_limit kicked_ip=${OLD_IP} by=${CLIENT_IP}" >> "$LOG_FILE"
        kill -HUP "$OLD_PID" 2>/dev/null || true
        ALIVE=()
    else
        RAND_IDX=$(( RANDOM % CURRENT ))
        KICK_PID=$(echo "${ALIVE[$RAND_IDX]}" | cut -d"|" -f1)
        KICK_IP=$(echo "${ALIVE[$RAND_IDX]}"  | cut -d"|" -f2)
        echo "[$CONN_TIME] KICK user=${USER} reason=over_limit(${MAX_CONN}) kicked_ip=${KICK_IP} by=${CLIENT_IP}" >> "$LOG_FILE"
        kill -HUP "$KICK_PID" 2>/dev/null || true
        unset "ALIVE[$RAND_IDX]"
        ALIVE=("${ALIVE[@]}")
    fi
fi

ALIVE+=("$$|${CLIENT_IP}|${CONN_UNIX}|${VPN_IP}")
printf "%s\n" "${ALIVE[@]}" > "$SESSION_FILE"
echo "[$CONN_TIME] SESSION_START user=${USER} client=${CLIENT_IP}:${CLIENT_PORT} vpn_ip=${VPN_IP} pid=$$" >> "$DETAIL_LOG"

# 路由推送由服务端配置(splitMode)and CCD 文件(globalMode)处理
# client-connect: session management only

# ── UL limit:tc + ifb,针对 $dev 接口(连接级别,不依赖IP)────────────────
# 说明:
#   DL limit由 CCD 里的 shaper 指令Done,OpenVPN 内置支持,连接级别,不依赖IP
#   UL limit用 tc + ifb 对 $dev 接口做入方向整形:
#     $dev 是 OpenVPN 注入的该连接接口名(如 tun0/tap0),连接级别标识
#     通过 ifb 虚拟接口将入方向流量重定向后做 HTB 整形
#     连接断开时 disconnect 脚本清理规则,不会残留
apply_ul_limit() {
    local iface="${dev:-}"
    [[ -z "$iface" ]] && return 0
    command -v tc &>/dev/null || return 0
    command -v ip &>/dev/null || return 0

    local speed_ul
    speed_ul=$(db_get "$USER" "speed_ul")
    [[ -z "$speed_ul" ]] && return 0

    # 确保 ifb 内核模块已加载
    modprobe ifb numifbs=1 2>/dev/null || true

    # 查找或创建空闲 ifb 接口(避免多用户冲突)
    local ifb=""
    for candidate in ifb0 ifb1 ifb2 ifb3; do
        if ! ip link show "$candidate" 2>/dev/null | grep -q "UP"; then
            ifb="$candidate"
            break
        fi
        # 如果该 ifb 已被本连接的接口绑定,复用它
        if tc filter show dev "$iface" parent ffff: 2>/dev/null | grep -q "$candidate"; then
            ifb="$candidate"
            break
        fi
    done
    if [[ -z "$ifb" ]]; then
        # 动态添加新 ifb
        local num
        num=$(ip link show type ifb 2>/dev/null | wc -l)
        ifb="ifb${num}"
        ip link add "$ifb" type ifb 2>/dev/null || {
            echo "[$CONN_TIME] TC_WARN user=${USER} cannot create ifb, skipping ul limit" >> "$LOG_FILE"
            return 0
        }
    fi
    ip link set "$ifb" up 2>/dev/null || true

    # $dev 入方向:加 ingress qdisc,将所有流量 redirect 到 ifb
    tc qdisc show dev "$iface" handle ffff: 2>/dev/null | grep -q ingress || \
        tc qdisc add dev "$iface" handle ffff: ingress 2>/dev/null || true

    tc filter add dev "$iface" parent ffff: protocol ip \
        u32 match u32 0 0 \
        action mirred egress redirect dev "$ifb" 2>/dev/null || true

    # ifb 出方向:HTB 整形,限制速率 = 该用户UL limit
    tc qdisc show dev "$ifb" root 2>/dev/null | grep -q htb || \
        tc qdisc add dev "$ifb" root handle 1: htb default 1 2>/dev/null || true
    tc class replace dev "$ifb" parent 1: classid 1:1 \
        htb rate "$speed_ul" burst 64kbit 2>/dev/null || true

    # 将接口名保存到临时文件,供 disconnect 时精确清理(用PID做唯一标识)
    echo "${iface} ${ifb}" > "/tmp/ovpn_tc_${USER}_$$"
    chmod 600 "/tmp/ovpn_tc_${USER}_$$"

    echo "[$CONN_TIME] TC_UL_SET user=${USER} iface=${iface} ifb=${ifb} limit=${speed_ul} pid=$$" >> "$LOG_FILE"
}
apply_ul_limit

exit 0
CONNECT_SCRIPT
    sed -i "s|__INSTALL_DIR__|${INSTALL_DIR}|g" "$SCRIPTS_DIR/client-connect.sh"

    # ── client-disconnect(断开时:清理会话 + 日志)──────────────────────────
    cat > "$SCRIPTS_DIR/client-disconnect.sh" <<'DISCONNECT_SCRIPT'
#!/bin/bash
INSTALL_DIR="__INSTALL_DIR__"
SESSION_DIR="$INSTALL_DIR/etc/openvpn/sessions"
LOG_FILE="$INSTALL_DIR/logs/connections.log"
DETAIL_LOG="$INSTALL_DIR/logs/detail.log"
timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

USER="${common_name:-unknown}"
CLIENT_IP="${trusted_ip:-unknown}"
CLIENT_PORT="${trusted_port:-0}"
VPN_IP="${ifconfig_pool_remote_ip:-unknown}"
BYTES_SENT="${bytes_sent:-0}"
BYTES_RECV="${bytes_received:-0}"
DURATION="${time_duration:-0}"
DISC_TIME=$(timestamp)

echo "[$DISC_TIME] DISCONNECT user=${USER} client_ip=${CLIENT_IP}:${CLIENT_PORT} vpn_ip=${VPN_IP} tx=${BYTES_SENT}B rx=${BYTES_RECV}B duration=${DURATION}s" >> "$LOG_FILE"
echo "[$DISC_TIME] SESSION_END user=${USER} client=${CLIENT_IP}:${CLIENT_PORT} duration=${DURATION}s" >> "$DETAIL_LOG"

SESSION_FILE="$SESSION_DIR/${USER}.sessions"
if [[ -f "$SESSION_FILE" ]]; then
    grep -v "^$$|" "$SESSION_FILE" > "${SESSION_FILE}.tmp" 2>/dev/null || true
    mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
fi

# ── 清理该连接的 tc UL limit规则 ────────────────────────────────────────────
# 通过连接时保存的接口名文件来清理,完全不依赖IP
cleanup_ul_limit() {
    local tc_file="/tmp/openvpn_tc_${USER}_$$"
    [[ -f "$tc_file" ]] || return 0
    command -v tc &>/dev/null || return 0

    local iface ifb
    read -r iface ifb < "$tc_file"

    [[ -n "$iface" ]] && {
        # 清除 ingress qdisc(会一并删除所有 filter)
        tc qdisc del dev "$iface" handle ffff: ingress 2>/dev/null || true
    }

    [[ -n "$ifb" ]] && {
        # 清除 ifb 上的 qdisc
        tc qdisc del dev "$ifb" root 2>/dev/null || true
    }

    rm -f "$tc_file"
    echo "[$DISC_TIME] TC_CLEANUP user=${USER} iface=${iface:-unknown}" >> "$LOG_FILE"
}
cleanup_ul_limit

exit 0
DISCONNECT_SCRIPT
    sed -i "s|__INSTALL_DIR__|${INSTALL_DIR}|g" "$SCRIPTS_DIR/client-disconnect.sh"

    # ── learn-address(IP分配日志)───────────────────────────────────────────
    cat > "$SCRIPTS_DIR/learn-address.sh" <<'LEARN_SCRIPT'
#!/bin/bash
INSTALL_DIR="__INSTALL_DIR__"
ADDRESS_LOG="$INSTALL_DIR/logs/address.log"
DETAIL_LOG="$INSTALL_DIR/logs/detail.log"
timestamp() { date "+%Y-%m-%d %H:%M:%S"; }
OP="${1:-}"; ADDR="${2:-}"; USER="${3:-}"; TS=$(timestamp)
case "$OP" in
    add|update) echo "[$TS] ADDR_${OP^^} user=${USER} vpn_addr=${ADDR}" | tee -a "$ADDRESS_LOG" >> "$DETAIL_LOG" ;;
    delete)     echo "[$TS] ADDR_RELEASE user=${USER} vpn_addr=${ADDR}" >> "$ADDRESS_LOG" ;;
esac
exit 0
LEARN_SCRIPT
    sed -i "s|__INSTALL_DIR__|${INSTALL_DIR}|g" "$SCRIPTS_DIR/learn-address.sh"

    chmod +x "$SCRIPTS_DIR/"*.sh
    success "Hook scripts generated"
}

# =============================================================================
# iptables 规则(开放4个port,TCP/UDP各自对应)
# =============================================================================

generate_iptables_scripts() {
    local iface
    iface=$(ip route show default 2>/dev/null | grep -m1 "^default" | cut -d" " -f5)
    iface="${iface:-eth0}"

    cat > "$SCRIPTS_DIR/iptables-setup.sh" <<IPTS
#!/bin/bash
IFACE="${iface}"
echo 1 > /proc/sys/net/ipv4/ip_forward
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null || \
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p -q 2>/dev/null || true

_nat() { iptables -t nat -C POSTROUTING -s "\$1" -o \$IFACE -j MASQUERADE 2>/dev/null || \
         iptables -t nat -A POSTROUTING -s "\$1" -o \$IFACE -j MASQUERADE; }
_fwd() { iptables -C FORWARD -s "\$1" -j ACCEPT 2>/dev/null || \
         iptables -A FORWARD -s "\$1" -j ACCEPT; }

iptables -C FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT

# IPv4 NAT and转发(VPN隧道内是IPv4流量,所有协议Mode都需要)
_nat "10.8.0.0/24"; _fwd "10.8.0.0/24"
_nat "10.8.1.0/24"; _fwd "10.8.1.0/24"
_nat "10.9.0.0/24"; _fwd "10.9.0.0/24"
_nat "10.9.1.0/24"; _fwd "10.9.1.0/24"

# IPv4 INPUT port放行
iptables -C INPUT -p udp --dport ${PORT_TUN} -j ACCEPT 2>/dev/null || iptables -A INPUT -p udp --dport ${PORT_TUN} -j ACCEPT
iptables -C INPUT -p tcp --dport ${PORT_TUN} -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport ${PORT_TUN} -j ACCEPT
iptables -C INPUT -p udp --dport ${PORT_TAP} -j ACCEPT 2>/dev/null || iptables -A INPUT -p udp --dport ${PORT_TAP} -j ACCEPT
iptables -C INPUT -p tcp --dport ${PORT_TAP} -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport ${PORT_TAP} -j ACCEPT

# IPv6 INPUT port放行(IPv6 anddual-stackMode)
if [[ "${LISTEN_PROTO}" == "ipv6" || "${LISTEN_PROTO}" == "dual" ]]; then
    if command -v ip6tables &>/dev/null; then
        ip6tables -C FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
            ip6tables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
        ip6tables -C INPUT -p udp --dport ${PORT_TUN} -j ACCEPT 2>/dev/null || ip6tables -A INPUT -p udp --dport ${PORT_TUN} -j ACCEPT
        ip6tables -C INPUT -p tcp --dport ${PORT_TUN} -j ACCEPT 2>/dev/null || ip6tables -A INPUT -p tcp --dport ${PORT_TUN} -j ACCEPT
        ip6tables -C INPUT -p udp --dport ${PORT_TAP} -j ACCEPT 2>/dev/null || ip6tables -A INPUT -p udp --dport ${PORT_TAP} -j ACCEPT
        ip6tables -C INPUT -p tcp --dport ${PORT_TAP} -j ACCEPT 2>/dev/null || ip6tables -A INPUT -p tcp --dport ${PORT_TAP} -j ACCEPT
    fi
fi
echo "iptables rules set (proto: ${LISTEN_PROTO})"
IPTS
    chmod +x "$SCRIPTS_DIR/iptables-setup.sh"
}

# =============================================================================
# 服务端配置(2个进程)
# proto tcp-and-udp:每个进程同时接受 TCP and UDP,客户端用任意 proto 均可连
# =============================================================================

# 判断 dual Mode是否dual-process required
# 当 IPv4 and IPv6 地址都是具体地址(非通配)时,必须跑两个独立进程
_dual_needs_two_procs() {
    [[ "$LISTEN_PROTO" != "dual" ]] && return 1
    local v4="${LISTEN_ADDR_V4:-0.0.0.0}"
    local v6="${LISTEN_ADDR_V6:-::}"
    # 若任一为通配地址,单进程 :: dual-stack绑定即可
    [[ "$v4" == "0.0.0.0" || "$v6" == "::" ]] && return 1
    return 0  # Both are specific addresses → dual-process required
}

generate_server_confs() {
    # ── 架构说明 ─────────────────────────────────────────────────────────────────
    # OpenVPN 不支持 tcp-and-udp,正确做法是:
    #   同一port号,分别跑 proto udp and proto tcp 两个独立进程
    #   客户端 tun-udp 连 PORT_TUN/udp,tun-tcp 连 PORT_TUN/tcp,port相同协议不同
    #   这样用户看到的还是2个port,但实际跑4个进程
    #
    # $1=conf $2=dev $3=proto(udp/tcp/udp6/tcp6) $4=local $5=port $6=server指令
    # $7=CCD $8=IP池 $9=status日志 $10=run日志
    _gen_conf() {
        local conf="$1" dev="$2" proto="$3" local_addr="$4" port="$5" server_directive="$6"
        local ccd="$7" ipp="$8" status_log="$9" run_log="${10}"

        local run_user="root"
        local run_group="root"

        cat > "$conf" <<SERVER
port ${port}
proto ${proto}
local ${local_addr}
dev ${dev}

tls-version-min 1.0
tls-cipher TLS-DHE-RSA-WITH-AES-256-GCM-SHA384:TLS-DHE-RSA-WITH-AES-256-CBC-SHA256:TLS-DHE-RSA-WITH-AES-128-CBC-SHA:TLS-RSA-WITH-AES-256-GCM-SHA384:TLS-RSA-WITH-AES-256-CBC-SHA256:TLS-RSA-WITH-AES-128-CBC-SHA
cipher AES-256-CBC
auth SHA256
data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC
data-ciphers-fallback AES-256-CBC

ca   ${OPENVPN_BASE}/ca.crt
cert ${OPENVPN_BASE}/server.crt
key  ${OPENVPN_BASE}/server.key
dh   ${OPENVPN_BASE}/dh.pem
tls-auth ${OPENVPN_BASE}/ta.key 0
crl-verify ${OPENVPN_BASE}/crl.pem

verify-client-cert require
auth-user-pass-verify ${SCRIPTS_DIR}/auth-user-pass.sh via-env
username-as-common-name

duplicate-cn
topology subnet

${server_directive}
ifconfig-pool-persist ${ipp}

push "route ${LAN_SUBNET} ${LAN_MASK}"
push "route ${MODEM_SUBNET} ${MODEM_MASK}"

client-config-dir ${ccd}
client-to-client
keepalive 10 120

# Compression: disabled(OpenVPN 2.6+ default, avoids overhead)
# allow-compression asym: accept compressed but do not send
allow-compression asym

max-clients 200
persist-key
persist-tun
user ${run_user}
group ${run_group}

status ${status_log} 30
log-append ${run_log}
verb 3
mute 10

script-security 3
client-connect    ${SCRIPTS_DIR}/client-connect.sh
client-disconnect ${SCRIPTS_DIR}/client-disconnect.sh
learn-address     ${SCRIPTS_DIR}/learn-address.sh
SERVER
        # UDP Mode才加 explicit-exit-notify
        if [[ "$proto" == "udp" || "$proto" == "udp6" ]]; then
            echo "explicit-exit-notify 1" >> "$conf"
        fi
    }

    # 确定本机Listen addr
    local srv_local_v4="${LISTEN_ADDR_V4:-0.0.0.0}"
    local srv_local_v6="${LISTEN_ADDR_V6:-::}"

    case "$LISTEN_PROTO" in
        ipv6)
            # 只跑 IPv6 两个进程(udp6 + tcp6)
            _gen_conf "$SERVER_CONF_TUN" "tun" "udp6" "$srv_local_v6" "$PORT_TUN" \
                "server ${VPN_SUBNET_TUN} ${VPN_MASK_TUN}" \
                "$CCD_DIR_TUN" "${OPENVPN_BASE}/ipp-tun-udp.txt" \
                "${LOG_DIR}/tun-udp-status.log" "${LOG_DIR}/tun-udp.log"

            _gen_conf "$SERVER_CONF_TUN_TCP" "tun" "tcp6-server" "$srv_local_v6" "$PORT_TUN" \
                "server ${VPN_SUBNET_TUN} ${VPN_MASK_TUN}" \
                "$CCD_DIR_TUN" "${OPENVPN_BASE}/ipp-tun-tcp.txt" \
                "${LOG_DIR}/tun-tcp-status.log" "${LOG_DIR}/tun-tcp.log"

            _gen_conf "$SERVER_CONF_TAP" "tap" "udp6" "$srv_local_v6" "$PORT_TAP" \
                "server ${VPN_SUBNET_TAP} ${VPN_MASK_TAP}" \
                "$CCD_DIR_TAP" "${OPENVPN_BASE}/ipp-tap-udp.txt" \
                "${LOG_DIR}/tap-udp-status.log" "${LOG_DIR}/tap-udp.log"

            _gen_conf "$SERVER_CONF_TAP_TCP" "tap" "tcp6-server" "$srv_local_v6" "$PORT_TAP" \
                "server ${VPN_SUBNET_TAP} ${VPN_MASK_TAP}" \
                "$CCD_DIR_TAP" "${OPENVPN_BASE}/ipp-tap-tcp.txt" \
                "${LOG_DIR}/tap-tcp-status.log" "${LOG_DIR}/tap-tcp.log"
            success "IPv6 mode: 4 processes (udp6/tcp6)"
            ;;

        dual)
            # dual-stack::: 同时接受 IPv4 映射地址(Linux默认 IPV6_V6ONLY=0)
            # 用 udp6 / tcp6-server,自动接受 IPv4 and IPv6
            _gen_conf "$SERVER_CONF_TUN" "tun" "udp6" "::" "$PORT_TUN" \
                "server ${VPN_SUBNET_TUN} ${VPN_MASK_TUN}" \
                "$CCD_DIR_TUN" "${OPENVPN_BASE}/ipp-tun-udp.txt" \
                "${LOG_DIR}/tun-udp-status.log" "${LOG_DIR}/tun-udp.log"

            _gen_conf "$SERVER_CONF_TUN_TCP" "tun" "tcp6-server" "::" "$PORT_TUN" \
                "server ${VPN_SUBNET_TUN} ${VPN_MASK_TUN}" \
                "$CCD_DIR_TUN" "${OPENVPN_BASE}/ipp-tun-tcp.txt" \
                "${LOG_DIR}/tun-tcp-status.log" "${LOG_DIR}/tun-tcp.log"

            _gen_conf "$SERVER_CONF_TAP" "tap" "udp6" "::" "$PORT_TAP" \
                "server ${VPN_SUBNET_TAP} ${VPN_MASK_TAP}" \
                "$CCD_DIR_TAP" "${OPENVPN_BASE}/ipp-tap-udp.txt" \
                "${LOG_DIR}/tap-udp-status.log" "${LOG_DIR}/tap-udp.log"

            _gen_conf "$SERVER_CONF_TAP_TCP" "tap" "tcp6-server" "::" "$PORT_TAP" \
                "server ${VPN_SUBNET_TAP} ${VPN_MASK_TAP}" \
                "$CCD_DIR_TAP" "${OPENVPN_BASE}/ipp-tap-tcp.txt" \
                "${LOG_DIR}/tap-tcp-status.log" "${LOG_DIR}/tap-tcp.log"
            success "Dual-stack (:: single-process): 4 configs"
            ;;

        *)  # ipv4 default
            # 每个进程用独立子网,避免多接口绑同一IP导致ARP/路由混乱
            _gen_conf "$SERVER_CONF_TUN" "tun" "udp" "$srv_local_v4" "$PORT_TUN" \
                "server 10.8.0.0 255.255.255.0" \
                "$CCD_DIR_TUN" "${OPENVPN_BASE}/ipp-tun-udp.txt" \
                "${LOG_DIR}/tun-udp-status.log" "${LOG_DIR}/tun-udp.log"
            success "TUN-UDP config generated (${srv_local_v4}:${PORT_TUN}/udp  subnet 10.8.0.0/24)"

            _gen_conf "$SERVER_CONF_TUN_TCP" "tun" "tcp-server" "$srv_local_v4" "$PORT_TUN" \
                "server 10.8.1.0 255.255.255.0" \
                "$CCD_DIR_TUN" "${OPENVPN_BASE}/ipp-tun-tcp.txt" \
                "${LOG_DIR}/tun-tcp-status.log" "${LOG_DIR}/tun-tcp.log"
            success "TUN-TCP config generated (${srv_local_v4}:${PORT_TUN}/tcp  subnet 10.8.1.0/24)"

            _gen_conf "$SERVER_CONF_TAP" "tap" "udp" "$srv_local_v4" "$PORT_TAP" \
                "server 10.9.0.0 255.255.255.0" \
                "$CCD_DIR_TAP" "${OPENVPN_BASE}/ipp-tap-udp.txt" \
                "${LOG_DIR}/tap-udp-status.log" "${LOG_DIR}/tap-udp.log"
            success "TAP-UDP config generated (${srv_local_v4}:${PORT_TAP}/udp  subnet 10.9.0.0/24)"

            _gen_conf "$SERVER_CONF_TAP_TCP" "tap" "tcp-server" "$srv_local_v4" "$PORT_TAP" \
                "server 10.9.1.0 255.255.255.0" \
                "$CCD_DIR_TAP" "${OPENVPN_BASE}/ipp-tap-tcp.txt" \
                "${LOG_DIR}/tap-tcp-status.log" "${LOG_DIR}/tap-tcp.log"
            success "TAP-TCP config generated (${srv_local_v4}:${PORT_TAP}/tcp  subnet 10.9.1.0/24)"
            ;;
    esac
}

# =============================================================================
# systemd 服务(4个)
# =============================================================================

generate_systemd_services() {
    # 检测 systemd 是否支持 socket activation
    local has_socket=false
    if systemctl --version 2>/dev/null | grep -q "systemd [2-9][0-9][0-9]"; then
        has_socket=true
    fi

    # 生成 .service 文件
    # $1=service文件路径  $2=描述  $3=conf文件路径  $4=是否有对应socket(true/false)
    _gen_svc() {
        local svc_file="$1" desc="$2" conf="$3" with_socket="${4:-false}"
        local socket_line=""
        [[ "$with_socket" == "true" ]] && socket_line="Sockets=$(basename "${svc_file%.service}.socket")"

        cat > "$svc_file" <<SVC
[Unit]
Description=${desc}
Documentation=https://openvpn.net/
After=network-online.target
Wants=network-online.target
ConditionFileIsExecutable=/usr/sbin/openvpn

[Service]
Type=notify
ExecStartPre=${SCRIPTS_DIR}/iptables-setup.sh
ExecStart=/usr/sbin/openvpn --config ${conf}
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
${socket_line}

[Install]
WantedBy=multi-user.target
SVC
        # 清理空行(socket_line 为空时有多余空行)
        sed -i "/^[[:space:]]*$/d" "$svc_file"
    }

    # 生成 .socket 文件(用于 socket activation,让 systemd 预先监听port)
    # $1=socket文件路径  $2=描述  $3=TCPport  $4=UDPport
    _gen_socket() {
        local sock_file="$1" desc="$2" tcp_port="$3" udp_port="$4"
        cat > "$sock_file" <<SOCK
[Unit]
Description=${desc}
Documentation=https://openvpn.net/

[Socket]
ListenStream=${tcp_port}
ListenDatagram=${udp_port}
BindIPv6Only=both

[Install]
WantedBy=sockets.target
SOCK
    }

    # 始终生成4个Services:TUN-UDP / TUN-TCP / TAP-UDP / TAP-TCP
    # 同一port不同协议,由各自进程独立监听
    _gen_svc "$SYSTEMD_TUN" \
        "OpenVPN TUN-UDP (port ${PORT_TUN}/udp)" \
        "$SERVER_CONF_TUN" "false"
    _gen_svc "$SYSTEMD_TUN_TCP" \
        "OpenVPN TUN-TCP (port ${PORT_TUN}/tcp)" \
        "$SERVER_CONF_TUN_TCP" "false"
    _gen_svc "$SYSTEMD_TAP" \
        "OpenVPN TAP-UDP (port ${PORT_TAP}/udp)" \
        "$SERVER_CONF_TAP" "false"
    _gen_svc "$SYSTEMD_TAP_TCP" \
        "OpenVPN TAP-TCP (port ${PORT_TAP}/tcp)" \
        "$SERVER_CONF_TAP_TCP" "false"

    systemctl daemon-reload
    success "systemd services created(4 processes: TUN-UDP/TUN-TCP/TAP-UDP/TAP-TCP)"
}

# =============================================================================
# 生成 CCD 文件(TUN and TAP 两个目录各写一份)
# =============================================================================

# 将限速字符串(如 10mbit)转成 shaper 需要的 bytes/sec 整数
# shaper 单位是 bytes/sec
_speed_to_bps() {
    local input="$1"
    [[ -z "$input" ]] && echo "0" && return
    if [[ "$input" =~ ^([0-9]+)gbit$ ]]; then
        echo $(( ${BASH_REMATCH[1]} * 1000000000 / 8 ))
    elif [[ "$input" =~ ^([0-9]+)mbit$ ]]; then
        echo $(( ${BASH_REMATCH[1]} * 1000000 / 8 ))
    elif [[ "$input" =~ ^([0-9]+)kbit$ ]]; then
        echo $(( ${BASH_REMATCH[1]} * 1000 / 8 ))
    else
        echo "0"
    fi
}

generate_ccd() {
    local username="$1"
    local vpn_mode="$2"

    # 读取该用户的限速配置
    local speed_dl speed_dl_bps shaper_line=""
    speed_dl=$(db_get "$username" "speed_dl")
    if [[ -n "$speed_dl" ]]; then
        speed_dl_bps=$(_speed_to_bps "$speed_dl")
        (( speed_dl_bps > 0 )) && shaper_line="shaper ${speed_dl_bps}"
    fi

    _write_ccd() {
        local ccd_dir="$1"
        {
            if [[ "$vpn_mode" == "global" ]]; then
                # global mode: use printf to write push directives correctly
                printf '%s\n' 'push "redirect-gateway def1 bypass-dhcp"'
                printf '%s\n' 'push "dhcp-option DNS 8.8.8.8"'
                printf '%s\n' 'push "dhcp-option DNS 114.114.114.114"'
            fi
            # shaper rate limit (valid CCD direct directive)
            [[ -n "$shaper_line" ]] && echo "$shaper_line"
        } > "$ccd_dir/$username"
        chmod 644 "$ccd_dir/$username"
    }

    _write_ccd "$CCD_DIR_TUN"
    _write_ccd "$CCD_DIR_TAP"
    local speed_info=""
    [[ -n "$shaper_line" ]] && speed_info=" dl=$speed_dl"
    info "CCD written: user=$username mode=$vpn_mode$speed_info"
}

# =============================================================================
# 生成用户专属4份 .ovpn(存放在 clients/<Username>/ 目录下)
# 内嵌:CA证书 + 用户证书 + 用户私钥 + TLS Auth密钥
# 四份文件只有 dev and proto 不同,其余内容完全相同
# =============================================================================

generate_client_ovpn() {
    local username="$1"
    local server_ip="$2"

    local user_dir="$CLIENT_DIR/$username"
    mkdir -p "$user_dir"
    chmod 750 "$user_dir"

    # 验证用户证书存在
    local crt_file="$PKI_DIR/issued/${username}.crt"
    local key_file="$PKI_DIR/private/${username}.key"
    [[ -f "$crt_file" ]] || { error "User cert not found: $crt_file"; return 1; }
    [[ -f "$key_file" ]] || { error "User key not found: $key_file"; return 1; }

    # 读取证书内容(4份共用)
    local ca_content cert_content key_content ta_content
    ca_content=$(cat "$OPENVPN_BASE/ca.crt")
    cert_content=$(openssl x509 -in "$crt_file" 2>/dev/null)
    key_content=$(cat "$key_file")
    ta_content=$(cat "$OPENVPN_BASE/ta.key")

    # 路由(客户端侧写基础内网路由,服务端 CCD 按用户推送完整规则)
    local vpn_mode
    vpn_mode=$(db_get "$username" "mode")
    # Routes pushed dynamically by client-connect
    local route_lines=""

    # 生成单份 .ovpn
    # $1=dev  $2=proto  $3=port  $4=输出路径
    _write_ovpn() {
        local dev="$1" proto="$2" port="$3" out="$4"
        # 客户端 proto 写法:TCP 服务端用 tcp-server,客户端要写 tcp-client
        local client_proto
        [[ "$proto" == "tcp" ]] && client_proto="tcp-client" || client_proto="udp"

        cat > "$out" <<OVPN
client
dev ${dev}
proto ${client_proto}
remote ${server_ip} ${port}
remote-cert-tls server
resolv-retry infinite
nobind
persist-key
persist-tun
tls-version-min 1.0
cipher AES-256-CBC
auth SHA256
topology subnet
data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC
data-ciphers-fallback AES-256-CBC
auth-user-pass
${route_lines}
verb 3
mute 10
key-direction 1
<ca>
${ca_content}
</ca>
<cert>
${cert_content}
</cert>
<key>
${key_content}
</key>
<tls-auth>
${ta_content}
</tls-auth>
OVPN
        chmod 600 "$out"
    }

    # tun-udp and tun-tcp 都连 PORT_TUN;tap-udp and tap-tcp 都连 PORT_TAP
    _write_ovpn "tun" "udp" "$PORT_TUN" "$user_dir/${username}-tun-udp.ovpn"
    _write_ovpn "tun" "tcp" "$PORT_TUN" "$user_dir/${username}-tun-tcp.ovpn"
    _write_ovpn "tap" "udp" "$PORT_TAP" "$user_dir/${username}-tap-udp.ovpn"
    _write_ovpn "tap" "tcp" "$PORT_TAP" "$user_dir/${username}-tap-tcp.ovpn"

    success "4x .ovpn generated: $user_dir/"
}

# =============================================================================
# 添加用户
# =============================================================================

# 解析限速字符串(如 "10mbit")转为 tc 可用格式,返回空表示unlimited
# 支持:10m / 10mbit / 10M / 1024k / 1024kbit / 0(unlimited)
_parse_speed() {
    local input="${1:-0}"
    [[ "$input" == "0" || -z "$input" ]] && echo "" && return
    # 统一转成 tc 格式(kbit/mbit/gbit)
    if [[ "$input" =~ ^([0-9]+)[gG][bB]?(it)?$ ]]; then
        echo "${BASH_REMATCH[1]}gbit"
    elif [[ "$input" =~ ^([0-9]+)[mM][bB]?(it)?$ ]]; then
        echo "${BASH_REMATCH[1]}mbit"
    elif [[ "$input" =~ ^([0-9]+)[kK][bB]?(it)?$ ]]; then
        echo "${BASH_REMATCH[1]}kbit"
    elif [[ "$input" =~ ^[0-9]+$ && "$input" -gt 0 ]]; then
        echo "${input}kbit"  # plain number defaults to kbit
    else
        echo ""
    fi
}

add_user() {
    clear
    echo -e "${BLUE}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║              Create VPN User                         ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # ── Username ────────────────────────────────────────────────────────────────
    title "Step 1/6: Username"
    local username="${1:-}"
    while true; do
        if [[ -z "$username" ]]; then
            echo -n "  Username (a-z/0-9/_/-, 2-32 chars): "
            read -r username
        fi
        if ! [[ "$username" =~ ^[a-zA-Z0-9_-]{2,32}$ ]]; then
            error "Invalid username format,Please try again"
            username=""
            continue
        fi
        if db_user_exists "$username"; then
            error "User $username already exists, try another"
            username=""
            continue
        fi
        break
    done
    success "Username: $username"

    # ── 密码 ──────────────────────────────────────────────────────────────────
    title "Step 2/6: Password"
    local password password2
    while true; do
        echo -n "  Password (min 6 chars, any characters): "
        IFS= read -rs password; echo
        if [[ ${#password} -lt 6 ]]; then
            error "Password must be at least 6 chars"
            continue
        fi
        echo -n "  Confirm password: "
        IFS= read -rs password2; echo
        if [[ "$password" != "$password2" ]]; then
            error "Passwords do not match, try again"
            continue
        fi
        break
    done
    success "Password set"

    # ── 路由Mode ──────────────────────────────────────────────────────────────
    title "Step 3/6: Routing mode"
    echo "  1) global - all traffic via VPN (including internet)"
    echo "  2) split  - LAN only ( ${LAN_SUBNET}/24 and ${MODEM_SUBNET}/24  via VPN)"
    echo ""
    echo -n "  Select [1/2, default 2]: "
    read -r _c
    local vpn_mode
    case "${_c:-2}" in
        1) vpn_mode="global"; success "Mode: global" ;;
        *) vpn_mode="split";  success "Mode: split" ;;
    esac

    # ── MaxConn设备数 ────────────────────────────────────────────────────────────
    title "Step 4/6: Max concurrent devices"
    echo "  Limit simultaneous logins per account"
    echo "  1 = single device (new login kicks old)"
    echo "  N = up to N devices (excess get kicked)"
    echo ""
    echo -n "  Max concurrent devices [default 1]: "
    read -r max_conn
    max_conn="${max_conn:-1}"
    if ! [[ "$max_conn" =~ ^[0-9]+$ ]] || (( max_conn < 1 || max_conn > 99 )); then
        warn "Invalid input, using default 1"
        max_conn=1
    fi
    success "Max devices: ${max_conn}  devices"

    # ── 限速设置 ──────────────────────────────────────────────────────────────
    title "Step 5/6: Speed limit (optional)"
    echo "  Per-user speed limit, others unaffected"
    echo "  Units: kbit/mbit/gbit per second"
    echo "  e.g. 10mbit=10Mbps, 512kbit=512Kbps, 0=unlimited"
    echo ""
    echo -n "  DL limit (server->client) [Enter=unlimited]: "
    read -r _dl_raw
    local speed_dl
    speed_dl=$(_parse_speed "$_dl_raw")
    if [[ -n "$speed_dl" ]]; then
        success "DL limit: $speed_dl"
    else
        info "Download: unlimited"
    fi

    echo -n "  UL limit (client->server) [Enter=unlimited]: "
    read -r _ul_raw
    local speed_ul
    speed_ul=$(_parse_speed "$_ul_raw")
    if [[ -n "$speed_ul" ]]; then
        success "UL limit: $speed_ul"
    else
        info "Upload: unlimited"
    fi

    # ── 确认 ──────────────────────────────────────────────────────────────────
    title "Step 6/6: Confirm"
    echo -e "  ${CYAN}Creating user with these settings:${NC}"
    echo ""
    echo -e "  ┌────────────────────────────────────────────────────┐"
    echo -e "  │  Username:   $username"
    echo -e "  │  Mode: $vpn_mode"
    echo -e "  │  MaxConn: ${max_conn}  devices"
    echo -e "  │  DL limit: ${speed_dl:-unlimited}"
    echo -e "  │  UL limit: ${speed_ul:-unlimited}"
    echo -e "  └────────────────────────────────────────────────────┘"
    echo ""
    echo -n "  Confirm? [y/N]: "
    read -r _confirm
    [[ "$_confirm" =~ ^[Yy]$ ]] || { info "Cancelled"; return; }

    # ── 执行创建 ──────────────────────────────────────────────────────────────
    echo ""
    info "Creating user..."

    local server_ip
    server_ip=$(db_get "_server_" "public_ip")
    [[ -z "$server_ip" ]] && { echo -n "Server public IP or domain: "; read -r server_ip; }

    # 写入数据库
    local salt hash
    salt=$(openssl rand -hex 16)
    hash=$(printf "%s" "${salt}${password}" | sha256sum | cut -d" " -f1)
    db_set "$username" "status"        "active"
    db_set "$username" "mode"          "$vpn_mode"
    db_set "$username" "max_conn"      "$max_conn"
    db_set "$username" "speed_dl"      "${speed_dl}"
    db_set "$username" "speed_ul"      "${speed_ul}"
    db_set "$username" "salt"          "$salt"
    db_set "$username" "password_hash" "$hash"
    db_set "$username" "created_at"    "$(date "+%Y-%m-%d %H:%M:%S")"

    # 签发用户独立证书
    local cert_years
    cert_years=$(db_get "_server_" "cert_years")
    cert_years="${cert_years:-99}"
    create_user_cert "$username" "$cert_years"
    db_set "$username" "cert_years" "$cert_years"

    # 生成 CCD and4份 .ovpn
    generate_ccd "$username" "$vpn_mode"
    generate_client_ovpn "$username" "$server_ip"

    # 初始化会话文件
    touch "$SESSION_DIR/${username}.sessions"
    chmod 600 "$SESSION_DIR/${username}.sessions"

    # ── Done输出 ──────────────────────────────────────────────────────────────
    local user_dir="$CLIENT_DIR/$username"
    clear
    echo -e "${GREEN}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║            User created!                            ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  ${CYAN}Config dir: ${user_dir}/${NC}"
    echo -e "  ┌────────────────────────────────────────────────────────────┐"
    for f in "$user_dir"/*.ovpn; do
        [[ -f "$f" ]] || continue
        local fname size
        fname=$(basename "$f")
        size=$(wc -c < "$f" 2>/dev/null || echo "?")
        echo -e "  │  ${fname}  (${size} bytes)"
    done
    echo -e "  └────────────────────────────────────────────────────────────┘"
    echo ""
    echo -e "  ${CYAN}User config:${NC}"
    echo -e "  Mode: ${vpn_mode}  |  MaxConn: ${max_conn} devices  |  Download: ${speed_dl:-unlimited}  |  Upload: ${speed_ul:-unlimited}"
    echo ""
    echo -e "  ${YELLOW}Connect info:${NC}"
    echo -e "  tun-udp / tun-tcp → port ${PORT_TUN}"
    echo -e "  tap-udp / tap-tcp → port ${PORT_TAP}"
    echo -e "  Connect with username ${CYAN}${username}${NC} and password (cert + password auth)"
    echo ""
}

# =============================================================================
# 用户管理
# =============================================================================

manage_user() {
    local action="${1:-list}"
    local username="${2:-}"

    if [[ "$action" != "list" ]]; then
        [[ -z "$username" ]] && { echo -n "Username: "; read -r username; }
        db_user_exists "$username" || { error "User not found: $username"; return 1; }
    fi

    case "$action" in
        disable)
            db_set "$username" "status" "disabled"
            success "User disabled: $username"
            ;;
        enable)
            db_set "$username" "status" "active"
            success "User enabled: $username"
            ;;
        delete)
            echo -n "Confirm delete $username?[y/N]: "; read -r confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || { info "Cancelled"; return; }
            local easyrsa="$EASYRSA_DIR/easyrsa"
            if [[ -f "$PKI_DIR/issued/${username}.crt" ]]; then
                cd "$EASYRSA_DIR"
                EASYRSA_VARS_FILE="$EASYRSA_DIR/vars" "$easyrsa" --batch revoke "$username" 2>/dev/null || true
                EASYRSA_VARS_FILE="$EASYRSA_DIR/vars" "$easyrsa" gen-crl
                cp "$PKI_DIR/crl.pem" "$OPENVPN_BASE/"
                chmod 644 "$OPENVPN_BASE/crl.pem"
                info "Certificate revoked, CRL updated"
            fi
            sed -i "/^${username}|/d" "$CONFIG_DB"
            rm -f "$CCD_DIR_TUN/$username" "$CCD_DIR_TAP/$username"
            rm -f "$SESSION_DIR/${username}.sessions"
            rm -rf "$CLIENT_DIR/$username"
            success "User $username removed"
            ;;
        passwd)
            local pw pw2
            echo -n "New password: "; IFS= read -rs pw; echo
            echo -n "Confirm: ";   IFS= read -rs pw2; echo
            [[ "$pw" == "$pw2" ]] || { error "Passwords do not match"; return 1; }
            [[ ${#pw} -ge 6 ]] || { error "Min 6 chars"; return 1; }
            local s h
            s=$(openssl rand -hex 16)
            h=$(printf "%s" "${s}${pw}" | sha256sum | cut -d" " -f1)
            db_set "$username" "salt" "$s"
            db_set "$username" "password_hash" "$h"
            success "Password updated: $username"
            ;;
        set-mode)
            local new_mode="${3:-}"
            [[ -z "$new_mode" ]] && { echo -n "Mode [global/split]: "; read -r new_mode; }
            [[ "$new_mode" =~ ^(global|split)$ ]] || { error "Must be global or split"; return 1; }
            db_set "$username" "mode" "$new_mode"
            generate_ccd "$username" "$new_mode"
            # 重新生成4份 .ovpn(路由行变了)
            local sip; sip=$(db_get "_server_" "public_ip")
            generate_client_ovpn "$username" "$sip"
            success "Mode changed to $new_mode,.ovpn regenerated"
            ;;
        set-maxconn)
            local new_max="${3:-}"
            [[ -z "$new_max" ]] && { echo -n "Max connections [1-99]: "; read -r new_max; }
            [[ "$new_max" =~ ^[0-9]+$ ]] && (( new_max >= 1 && new_max <= 99 )) || \
                { error "Enter 1-99"; return 1; }
            db_set "$username" "max_conn" "$new_max"
            success "[CN]MaxConn[CN]: $new_max"
            ;;
        set-speed)
            # 用法: user set-speed <Username> [dl=<速度>] [ul=<速度>]
            # 不传参数则进入交互Mode
            # 速度格式: 10mbit / 512kbit / 1gbit / 0(unlimited)
            local new_dl="${3:-__ask__}" new_ul="${4:-__ask__}"

            echo ""
            echo -e "${CYAN}[CN]: ${username}${NC}"
            local cur_dl cur_ul
            cur_dl=$(db_get "$username" "speed_dl")
            cur_ul=$(db_get "$username" "speed_ul")
            echo "  Download: ${cur_dl:-unlimited}  |  Upload: ${cur_ul:-unlimited}"
            echo ""
            echo "  [CN]:10mbit / 512kbit / 1gbit / 0(unlimited)"
            echo "  [CN] = [CN]"
            echo ""

            if [[ "$new_dl" == "__ask__" ]]; then
                echo -n "  [CN]DL limit [[CN] ${cur_dl:-unlimited}]: "
                read -r new_dl
            fi
            if [[ "$new_ul" == "__ask__" ]]; then
                echo -n "  [CN]UL limit [[CN] ${cur_ul:-unlimited}]: "
                read -r new_ul
            fi

            # 处理下载速度
            if [[ -n "$new_dl" ]]; then
                local parsed_dl
                parsed_dl=$(_parse_speed "$new_dl")
                db_set "$username" "speed_dl" "$parsed_dl"
                [[ -n "$parsed_dl" ]]                     && success "DL limit[CN]: $parsed_dl"                     || success "DL limitCancelled(unlimited)"
            fi

            # 处理上传速度
            if [[ -n "$new_ul" ]]; then
                local parsed_ul
                parsed_ul=$(_parse_speed "$new_ul")
                db_set "$username" "speed_ul" "$parsed_ul"
                [[ -n "$parsed_ul" ]]                     && success "UL limit[CN]: $parsed_ul"                     || success "UL limitCancelled(unlimited)"
            fi

            info "[CN]"
            ;;
        kick)
            local sf="$SESSION_DIR/${username}.sessions"
            if [[ -s "$sf" ]]; then
                local kicked=0
                while IFS= read -r line; do
                    [[ -z "$line" ]] && continue
                    local pid ip
                    pid=$(echo "$line" | cut -d"|" -f1)
                    ip=$(echo "$line"  | cut -d"|" -f2)
                    kill -HUP "$pid" 2>/dev/null && { info "Kicked: PID=${pid} IP=${ip}"; (( kicked++ )) || true; }
                done < "$sf"
                > "$sf"
                success "Kicked $kicked  session(s)"
            else
                info "User $username [CN]online[CN]"
            fi
            ;;
        info)
            local user_dir="$CLIENT_DIR/$username"
            local ovpn_count
            ovpn_count=$(ls "$user_dir"/*.ovpn 2>/dev/null | wc -l)
            local cur_dl cur_ul
            cur_dl=$(db_get "$username" "speed_dl")
            cur_ul=$(db_get "$username" "speed_ul")
            echo ""
            echo -e "${CYAN}─── User info: $username ───${NC}"
            printf "  %-14s %s\n" "Status:"     "$(db_get "$username" "status")"
            printf "  %-14s %s\n" "Mode:" "$(db_get "$username" "mode")"
            printf "  %-14s %s\n" "MaxConn:" "$(db_get "$username" "max_conn")  devices"
            printf "  %-14s %s\n" "DL limit:" "${cur_dl:-unlimited}"
            printf "  %-14s %s\n" "UL limit:" "${cur_ul:-unlimited}"
            printf "  %-14s %s\n" "Created:" "$(db_get "$username" "created_at")"
            printf "  %-14s %s [CN] .ovpn (%s/)\n" "Config files:" "$ovpn_count" "$user_dir"
            local sf="$SESSION_DIR/${username}.sessions"
            if [[ -s "$sf" ]]; then
                local cnt; cnt=$(grep -c . "$sf" 2>/dev/null || echo 0)
                printf "  %-14s %s\n" "onlineStatus:" "${cnt}  session(s)"
                while IFS= read -r line; do
                    [[ -z "$line" ]] && continue
                    local ip ts vpnip login_time
                    ip=$(echo "$line"    | cut -d"|" -f2)
                    ts=$(echo "$line"    | cut -d"|" -f3)
                    vpnip=$(echo "$line" | cut -d"|" -f4)
                    login_time=$(date -d "@$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$ts")
                    echo "    → Client: $ip  VPN: $vpnip  Login: $login_time"
                done < "$sf"
            else
                printf "  %-14s %s\n" "onlineStatus:" "[CN]"
            fi
            echo ""
            ;;
        list)
            echo ""
            echo -e "${CYAN}─── User list ───${NC}"
            printf "%-16s %-8s %-7s %-4s %-10s %-10s  %s\n" \
                "Username" "Status" "Mode" "MaxConn" "DL limit" "UL limit" "Created"
            echo "──────────────────────────────────────────────────────────────────────────"
            grep "|status=" "$CONFIG_DB" 2>/dev/null | grep -v "^_server_" | \
            cut -d"|" -f1 | sort -u | while read -r u; do
                local online="" dl ul
                [[ -s "$SESSION_DIR/${u}.sessions" ]] && online="[online]"
                dl=$(db_get "$u" "speed_dl"); dl="${dl:--}"
                ul=$(db_get "$u" "speed_ul"); ul="${ul:--}"
                printf "%-16s %-8s %-7s %-4s %-10s %-10s  %s %s\n" \
                    "$u" \
                    "$(db_get "$u" "status")" \
                    "$(db_get "$u" "mode")" \
                    "$(db_get "$u" "max_conn")" \
                    "$dl" "$ul" \
                    "$(db_get "$u" "created_at")" \
                    "$online"
            done
            echo ""
            ;;
        *)
            error "[CN]: $action"
            echo "[CN]: info, list, disable, enable, delete, passwd, kick, set-mode, set-maxconn"
            ;;
    esac
}

# =============================================================================
# 日志查询
# =============================================================================

show_logs() {
    local log_type="${1:-all}"
    local filter="${2:-}"
    local lines="${3:-50}"
    title "[CN]"

    _log() {
        local file="$1" label="$2"
        info "$label ([CN] $lines [CN]):"
        if [[ -f "$file" ]]; then
            [[ -n "$filter" ]] \
                && grep "user=${filter}" "$file" 2>/dev/null | tail -n "$lines" \
                || tail -n "$lines" "$file" 2>/dev/null
        else
            warn "Log file not found: $file"
        fi
        echo ""
    }

    case "$log_type" in
        conn)   _log "$LOG_DIR/connections.log" "Connect/disconnect log" ;;
        auth)   _log "$LOG_DIR/auth.log"        "Auth log" ;;
        detail) _log "$LOG_DIR/detail.log"      "Detail log" ;;
        addr)   _log "$LOG_DIR/address.log"     "IP[CN]" ;;
        all)
            _log "$LOG_DIR/auth.log"        "Auth log"
            _log "$LOG_DIR/connections.log" "[CN]"
            _log "$LOG_DIR/detail.log"      "Detail log"
            ;;
        online)
            info "[CN]online[CN]:"
            echo ""
            local found=0
            for sf in "$SESSION_DIR"/*.sessions; do
                [[ -f "$sf" && -s "$sf" ]] || continue
                local u; u=$(basename "$sf" .sessions)
                local cnt; cnt=$(grep -c . "$sf" 2>/dev/null || echo 0)
                echo -e "  ${GREEN}● $u${NC}  ($cnt  session(s))"
                while IFS= read -r line; do
                    [[ -z "$line" ]] && continue
                    local pid ip ts vpnip login_time
                    pid=$(echo "$line"   | cut -d"|" -f1)
                    ip=$(echo "$line"    | cut -d"|" -f2)
                    ts=$(echo "$line"    | cut -d"|" -f3)
                    vpnip=$(echo "$line" | cut -d"|" -f4)
                    login_time=$(date -d "@$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null \
                              || date -r "$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null \
                              || echo "$ts")
                    echo "    Client: $ip  VPN IP: $vpnip  Login: $login_time  PID: $pid"
                done < "$sf"
                echo ""
                (( found++ )) || true
            done
            (( found == 0 )) && echo "  [CN]online"
            ;;
        *)
            error "[CN]: $log_type"
            echo "[CN]: conn, auth, detail, addr, all, online"
            ;;
    esac
}

# =============================================================================
# 服务管理
# =============================================================================

show_status() {
    title "OpenVPN [CN]Status"
    local items=(
        "openvpn-tun-udp.service:TUN-UDP (port ${PORT_TUN}/UDP)"
        "openvpn-tun-tcp.service:TUN-TCP (port ${PORT_TUN}/TCP)"
        "openvpn-tap-udp.service:TAP-UDP (port ${PORT_TAP}/UDP)"
        "openvpn-tap-tcp.service:TAP-TCP (port ${PORT_TAP}/TCP)"
    )
    for item in "${items[@]}"; do
        local svc label
        svc=$(echo "$item"   | cut -d: -f1)
        label=$(echo "$item" | cut -d: -f2)
        echo -e "${CYAN}${label}:${NC}"
        systemctl status "$svc" --no-pager -l 2>/dev/null | head -5 || true
        echo ""
    done
}

restart_services() {
    info "Restarting OpenVPN services (4)..."
    for svc in openvpn-tun-udp openvpn-tun-tcp openvpn-tap-udp openvpn-tap-tcp; do
        systemctl restart "${svc}.service"             && success "${svc} restarted"             || warn "${svc} restart failed"
    done
}

# =============================================================================
# 首次安装
# =============================================================================

do_install() {
    # 检查是否已安装
    if [[ -f "$INSTALL_DIR/etc/openvpn/users.db" ]]; then
        warn "[CN]: $INSTALL_DIR"
        echo -n "[CN]?[CN] [y/N]: "
        read -r _ri
        [[ "$_ri" =~ ^[Yy]$ ]] || { info "Cancelled"; return; }
    fi

    clear
    echo -e "${BLUE}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║           OpenVPN Install wizard                           ║"
    echo "  ║   [CN]Architecture:2[CN](TUN/TAP),IPv4/IPv6/dual-stack support  ║"
    echo "  ╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # ── 步骤1:Install dir ───────────────────────────────────────────────────────
    title "Step 1/7: Install directory"
    echo -e "  Default install dir: ${CYAN}/www/OpenVPN${NC}"
    echo -n "  Install directory [Enter for default]: "
    read -r _input_dir
    if [[ -n "$_input_dir" ]]; then
        INSTALL_DIR="$_input_dir"
    fi
    # 去掉末尾斜线
    INSTALL_DIR="${INSTALL_DIR%/}"
    init_paths  # ...
    success "Install dir: $INSTALL_DIR"

    # ── 步骤2:port设置 ───────────────────────────────────────────────────────
    title "Step 2/7: Port configuration"
    echo "  TUN [CN]([CN])and TAP [CN]([CN])[CN]port"
    echo "  [CN]port[CN] TCP and UDP [CN]"
    echo ""

    echo -n "  TUN port [[CN] 1194]: "
    read -r _p
    if [[ -n "$_p" ]]; then
        if [[ "$_p" =~ ^[0-9]+$ ]] && (( _p >= 1 && _p <= 65535 )); then
            PORT_TUN="$_p"
        else
            warn "port[CN],[CN] 1194"
            PORT_TUN=1194
        fi
    fi

    echo -n "  TAP port [[CN] 1195]: "
    read -r _p
    if [[ -n "$_p" ]]; then
        if [[ "$_p" =~ ^[0-9]+$ ]] && (( _p >= 1 && _p <= 65535 )); then
            if [[ "$_p" == "$PORT_TUN" ]]; then
                warn "TAP port[CN] TUN port[CN],[CN] 1195"
                PORT_TAP=1195
            else
                PORT_TAP="$_p"
            fi
        else
            warn "port[CN],[CN] 1195"
            PORT_TAP=1195
        fi
    fi
    success "TUN port: $PORT_TUN  |  TAP port: $PORT_TAP"

    # ── 步骤3:Protocoland地址 ─────────────────────────────────────────────────
    title "Step 3/7: Listen protocol and address"
    echo "  Select listen protocol:"
    echo "  1) IPv4 IPv4 only (default, best compatibility)"
    echo "  2) IPv6 IPv6 only"
    echo "  3) Dual-stack IPv4+IPv6 (via :: binding)"
    echo ""
    echo -n "  Select [1/2/3, default 1]: "
    read -r _proto_choice
    case "${_proto_choice:-1}" in
        2)
            LISTEN_PROTO="ipv6"
            local default_addr="::"
            local proto_label="IPv6"
            ;;
        3)
            LISTEN_PROTO="dual"
            local default_addr="::"
            local proto_label="dual-stack IPv4+IPv6"
            ;;
        *)
            LISTEN_PROTO="ipv4"
            local default_addr="0.0.0.0"
            local proto_label="IPv4"
            ;;
    esac

    echo ""
    if [[ "$LISTEN_PROTO" == "ipv4" ]]; then
        echo "  IPv4 listen address:"
        echo "  0.0.0.0    = All IPv4 interfaces (recommended)"
        echo "  Specific IP, e.g. 192.168.0.49"
        echo -n "  IPv4 address [default 0.0.0.0]: "
        read -r _v4_input
        LISTEN_ADDR_V4="${_v4_input:-0.0.0.0}"
        LISTEN_ADDR_V6="::"
        success "Protocol: IPv4 | addr: ${LISTEN_ADDR_V4}"

    elif [[ "$LISTEN_PROTO" == "ipv6" ]]; then
        echo "  IPv6 listen address:"
        echo "  ::         = All IPv6 interfaces (recommended)"
        echo "  Specific IP, e.g. 2001:db8::1"
        echo -n "  IPv6 address [default ::]: "
        read -r _v6_input
        LISTEN_ADDR_V4="0.0.0.0"
        LISTEN_ADDR_V6="${_v6_input:-::}"
        success "Protocol: IPv6 | addr: ${LISTEN_ADDR_V6}"

    else
        # dual-stackMode:分别询问 IPv4 and IPv6 地址
        echo "  Dual-stack: set IPv4 and IPv6 addresses separately"
        echo ""
        echo "  IPv4 address:"
        echo "  0.0.0.0  = All IPv4 interfaces (recommended)"
        echo "  Specific, e.g. 192.168.0.49"
        echo -n "  IPv4 address [default 0.0.0.0]: "
        read -r _v4_input
        LISTEN_ADDR_V4="${_v4_input:-0.0.0.0}"

        echo ""
        echo "  IPv6 address:"
        echo "  ::       = All IPv6 interfaces (recommended)"
        echo "  Specific, e.g. 2001:db8::1"
        echo -n "  IPv6 address [default ::]: "
        read -r _v6_input
        LISTEN_ADDR_V6="${_v6_input:-::}"

        # 判断是否dual-process required
        if [[ "$LISTEN_ADDR_V4" != "0.0.0.0" && "$LISTEN_ADDR_V6" != "::" ]]; then
            warn "Both specific IPs: dual-process mode (4 processes)"
            echo "  IPv4: ${LISTEN_ADDR_V4}:${PORT_TUN}/${PORT_TAP}"
            echo "  IPv6: [${LISTEN_ADDR_V6}]:${PORT_TUN}/${PORT_TAP}"
        else
            info "Single-process dual-stack (:: accepts IPv4 mapped)"
        fi
        success "Protocol: dual-stack | IPv4: ${LISTEN_ADDR_V4}  | IPv6: ${LISTEN_ADDR_V6}"
    fi

    # ── 步骤4:服务器地址 ─────────────────────────────────────────────────────
    title "Step 4/7: Public IP/hostname"
    echo -n "  Detecting public IP... "
    local server_ip
    # 用 $() 子shell调用,即使内部Failed也不会触发外层 set -e
    server_ip=$(get_public_ip) || server_ip=""
    if [[ -n "$server_ip" ]]; then
        echo -e "${GREEN}${server_ip}${NC}"
        echo -n "  Or enter domain/IP [Enter to use detected]: "
        read -r _in
        [[ -n "$_in" ]] && server_ip="$_in"
    else
        echo -e "${YELLOW}Detection failed${NC}"
        echo ""
        echo "  [CN]reason:"
        echo "  • Server cannot reach internet"
        echo "  • Firewall blocking outbound HTTP/HTTPS"
        echo "  • Behind NAT (normal, enter public IP manually)"
        echo ""
        echo -n "  Enter server public IP or domain: "
        read -r server_ip
        while [[ -z "$server_ip" ]]; do
            echo -n "  Cannot be empty, try again: "
            read -r server_ip
        done
    fi
    success "Server address: $server_ip"

    # ── 步骤5:Cert validity ─────────────────────────────────────────────────────
    title "Step 5/7: Certificate validity"
    echo "  CA and[CN]Cert validity([CN])"
    echo -n "  [CN] years[CN] [[CN] 99  years]: "
    read -r cert_years
    cert_years="${cert_years:-99}"
    if ! [[ "$cert_years" =~ ^[0-9]+$ ]] || (( cert_years < 1 )); then
        warn "[CN],[CN] 99  years"
        cert_years=99
    fi
    success "Cert validity: ${cert_years}  years"

    # ── 步骤6:确认 ──────────────────────────────────────────────────────────
    title "Step 6/7: Confirm installation"
    echo -e "  ${CYAN}[CN]:${NC}"
    echo ""
    echo -e "  ┌────────────────────────────────────────────────────┐"
    echo -e "  │  Install dir:  ${INSTALL_DIR}"
    echo -e "  │  [CN]:    ${server_ip}"
    echo -e "  │  TUN port:  ${PORT_TUN}/TCP and ${PORT_TUN}/UDP"
    echo -e "  │  TAP port:  ${PORT_TAP}/TCP and ${PORT_TAP}/UDP"
    echo -e "  │  Protocol:  ${LISTEN_PROTO}  ($(
        case "$LISTEN_PROTO" in
            ipv6) echo "[CN] IPv6" ;;
            dual) echo "IPv4 + IPv6 dual-stack" ;;
            *)    echo "[CN] IPv4" ;;
        esac
    ))"
    if [[ "$LISTEN_PROTO" == "dual" ]]; then
        echo -e "  │  IPv4 address: ${LISTEN_ADDR_V4}"
        echo -e "  │  IPv6 address: ${LISTEN_ADDR_V6}"
        _dual_needs_two_procs &&             echo -e "  │  Processes:  4 (dual-process dual-stack)" ||             echo -e "  │  Processes:  2 (single-process dual-stack)"
    elif [[ "$LISTEN_PROTO" == "ipv6" ]]; then
        echo -e "  │  Address:  ${LISTEN_ADDR_V6}"
    else
        echo -e "  │  Address:  ${LISTEN_ADDR_V4}"
    fi
    echo -e "  │  [CN] years[CN]:  ${cert_years}  years"
    echo -e "  │  systemd:   openvpn-tun.service + openvpn-tap.service"
    echo -e "  │  autostart:  [CN](systemctl enable)"
    echo -e "  └────────────────────────────────────────────────────┘"
    echo ""
    echo -n "  Confirm install?[y/N]: "
    read -r confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "Cancelled"; exit 0; }

    # ── 开始安装 ─────────────────────────────────────────────────────────────
    echo ""

    # ── 清理旧版本残留的 systemd 文件(防止新旧冲突导致port被占用)────────────
    info "Cleaning up old systemd files..."
    for svc in \
        openvpn-tun openvpn-tap \
        openvpn-tun-udp openvpn-tun-tcp \
        openvpn-tap-udp openvpn-tap-tcp \
        openvpn-tun-v4 openvpn-tun-v6 \
        openvpn-tap-v4 openvpn-tap-v6
    do
        systemctl stop    "${svc}.service" 2>/dev/null || true
        systemctl disable "${svc}.service" 2>/dev/null || true
        systemctl stop    "${svc}.socket"  2>/dev/null || true
        systemctl disable "${svc}.socket"  2>/dev/null || true
        rm -f "/etc/systemd/system/${svc}.service"
        rm -f "/etc/systemd/system/${svc}.socket"
    done
    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true
    info "Old files cleaned"

    detect_os
    install_dependencies
    init_directories
    init_pki "$cert_years"
    generate_hook_scripts
    generate_iptables_scripts
    generate_server_confs
    generate_systemd_services

    # 检查 tc 可用性(限速功能依赖)
    if ! command -v tc &>/dev/null; then
        warn "tc [CN],[CN]"
        warn "[CN]: apt-get install iproute2 (Debian) [CN] yum install iproute (RHEL)"
    else
        success "tc [CN],[CN]"
    fi

    # IP 转发
    echo 1 > /proc/sys/net/ipv4/ip_forward
    grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null ||         echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p -q 2>/dev/null || true

    # 保存安装配置
    db_set "_server_" "public_ip"    "$server_ip"
    db_set "_server_" "install_time" "$(date "+%Y-%m-%d %H:%M:%S")"
    db_set "_server_" "cert_years"   "$cert_years"
    db_set "_server_" "port_tun"     "$PORT_TUN"
    db_set "_server_" "port_tap"     "$PORT_TAP"
    db_set "_server_" "listen_proto"    "$LISTEN_PROTO"
    db_set "_server_" "listen_addr_v4"  "$LISTEN_ADDR_V4"
    db_set "_server_" "listen_addr_v6"  "$LISTEN_ADDR_V6"
    db_set "_server_" "install_dir"  "$INSTALL_DIR"

    # iptables
    "$SCRIPTS_DIR/iptables-setup.sh"

    # Ensuring directory permissions
    chmod 755 "$LOG_DIR" "$SESSION_DIR"

    # 启动并设置autostart
    info "Enabling autostart and starting services..."

    # 始终启动4个进程(TUN-UDP/TUN-TCP/TAP-UDP/TAP-TCP)
    systemctl enable openvpn-tun-udp.service openvpn-tun-tcp.service \
                     openvpn-tap-udp.service openvpn-tap-tcp.service
    systemctl start  openvpn-tun-udp.service openvpn-tun-tcp.service \
                     openvpn-tap-udp.service openvpn-tap-tcp.service
    sleep 2

    # ── 安装Done总结 ─────────────────────────────────────────────────────────
    clear
    echo -e "${GREEN}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║              OpenVPN [CN]OK!                       ║"
    echo "  ╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "  ${CYAN}Service status:${NC}"
    for svc in openvpn-tun-udp openvpn-tun-tcp openvpn-tap-udp openvpn-tap-tcp; do
        systemctl is-active "${svc}.service" &>/dev/null \
            && echo -e "  ● ${svc}.service  ${GREEN}running${NC}" \
            || echo -e "  ● ${svc}.service  ${RED}not running${NC}"
    done
    echo ""
    echo -e "  ${CYAN}Connection info:${NC}"
    echo -e "  TUN-UDP: ${server_ip}:${PORT_TUN}/UDP"
    echo -e "  TUN-TCP: ${server_ip}:${PORT_TUN}/TCP"
    echo -e "  TAP-UDP: ${server_ip}:${PORT_TAP}/UDP"
    echo -e "  TAP-TCP: ${server_ip}:${PORT_TAP}/TCP"
    echo ""
    echo -e "  ${CYAN}autostart:${NC} [CN] systemctl enable [CN]"
    echo ""
    echo -e "  ${CYAN}[CN]port[CN]([CN],[CN]4[CN]):${NC}"
    echo -e "  ┌────────────────────────────────────────────────────┐"
    echo -e "  │  UDP ${PORT_TUN}  →  192.168.1.2  →  DMZ  →  192.168.0.49"
    echo -e "  │  TCP ${PORT_TUN}  →  192.168.1.2  →  DMZ  →  192.168.0.49"
    echo -e "  │  UDP ${PORT_TAP}  →  192.168.1.2  →  DMZ  →  192.168.0.49"
    echo -e "  │  TCP ${PORT_TAP}  →  192.168.1.2  →  DMZ  →  192.168.0.49"
    echo -e "  └────────────────────────────────────────────────────┘"
    echo ""
    echo -e "  ${CYAN}Install dir:${NC} $INSTALL_DIR"
    echo -e "  ${CYAN}[CN]:${NC} $0 help"
    echo ""
    echo ""
    echo -e "  ${YELLOW}──────────────────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW}Next: Create VPN user${NC}"
    echo -e "  At least one user required to use VPN"
    echo ""
    echo -n "  [CN] VPN [CN]?[Y/n]: "
    read -r _yn
    # 默认 Y,只有明确输入 n 才跳过
    if [[ ! "${_yn,,}" =~ ^n ]]; then
        add_user
    else
        echo ""
        info "Skipped. Run this command later to add users:"
        echo -e "  ${CYAN}sudo $0 adduser${NC}"
        echo ""
    fi
}

# =============================================================================
# 帮助
# =============================================================================

show_help() {
    local script="$0"
    local pt="${PORT_TUN:-1194}"
    local ptap="${PORT_TAP:-1195}"
    local cdir="${CLIENT_DIR:-/www/OpenVPN/clients}"
    local db="${CONFIG_DB:-/www/OpenVPN/etc/openvpn/users.db}"
    local logd="${LOG_DIR:-/www/OpenVPN/logs}"
    local stun="${SERVER_CONF_TUN:-/www/OpenVPN/etc/openvpn/server-tun-udp.conf}"
    local stap="${SERVER_CONF_TAP:-/www/OpenVPN/etc/openvpn/server-tap-udp.conf}"

    echo -e "${CYAN}OpenVPN [CN]${NC}  |  [CN]: ${INSTALL_DIR:-/www/OpenVPN}"
    echo ""
    echo -e "${YELLOW}Install/Uninstall:${NC}"
    echo "  $script install                          Install OpenVPN([CN])"
    echo "  $script uninstall                        Full uninstall (files, services, packages)"
    echo ""
    echo -e "${YELLOW}User management:${NC}"
    echo "  $script adduser                          Create new user([CN]4[CN] .ovpn)"
    echo "  $script user list                        List all users"
    echo "  $script user info      <Username>          Show user details and config paths"
    echo "  $script user disable   <Username>          Disable account"
    echo "  $script user enable    <Username>          Enable account"
    echo "  $script user delete    <Username>          Delete account and revoke certificate"
    echo "  $script user passwd    <Username>          Change password"
    echo "  $script user kick      <Username>          [CN]online[CN]"
    echo "  $script user set-mode     <Username> <global|split>  [CN]Mode"
    echo "  $script user set-maxconn  <Username> <N>             [CN]MaxConn[CN]"
    echo "  $script user set-speed    <Username>                 Change speed limit (interactive)"
    echo ""
    echo -e "${YELLOW}Logs:${NC}"
    echo "  $script log online                       [CN]online[CN]"
    echo "  $script log conn   [Username] [[CN]]       Connect/disconnect log"
    echo "  $script log auth   [Username] [[CN]]       Auth log"
    echo "  $script log detail [Username] [[CN]]       Detail log"
    echo "  $script log all    [[CN]]                All logs"
    echo ""
    echo -e "${YELLOW}Services:${NC}"
    echo "  $script status"
    echo "  $script restart"
    echo ""
    echo -e "${YELLOW}Architecture:${NC}"
    echo "  Server: 4 processes (2 ports, UDP+TCP each):"
    echo "    TUN-UDP port ${pt}/UDP   TUN-TCP port ${pt}/TCP"
    echo "    TAP-UDP port ${ptap}/UDP   TAP-TCP port ${ptap}/TCP"
    echo ""
    echo "  Per-user config dir:${cdir}/<Username>/"
    echo "    <Username>-tun-udp.ovpn   dev tun + proto udp       → [CN] ${pt}/UDP"
    echo "    <Username>-tun-tcp.ovpn   dev tun + proto tcp-client → [CN] ${pt}/TCP"
    echo "    <Username>-tap-udp.ovpn   dev tap + proto udp        → [CN] ${ptap}/UDP"
    echo "    <Username>-tap-tcp.ovpn   dev tap + proto tcp-client → [CN] ${ptap}/TCP"
    echo ""
    echo "  [CN]:[CN]([CN])+ Username[CN]([CN]),[CN]"
    echo "  NAT mapping: port ${pt} and ${ptap} each open TCP+UDP, 4 rules total"
    echo ""
    echo -e "${YELLOW}Key paths:${NC}"
    echo "  Client configs: ${cdir}/<Username>/"
    echo "  User DB: ${db}"
    echo "  Server configs: ${stun%udp.conf}*.conf"
    echo "  Log dir:   ${logd}/"
    echo ""
}

# =============================================================================
# 卸载 OpenVPN(彻底清除所有安装内容)
# =============================================================================

do_uninstall() {
    # 先尝试加载已有配置,找到Install dirandport
    load_config

    clear
    echo -e "${RED}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║              OpenVPN Uninstall                        ║"
    echo "  ║   [CN],[CN]and[CN]           ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # ── 确认 ──────────────────────────────────────────────────────────────────
    echo -e "  ${RED}WARNING: The following will be permanently deleted!${NC}"
    echo ""
    echo "  • OpenVPN services (openvpn-tun / openvpn-tap)"
    echo "  • systemd service and socket files"
    echo "  • Install dir with all certs, keys, configs, logs"
    echo "  • iptables rules"
    echo "  • tc/ifb rate limit rules"
    echo "  • Installed packages (openvpn, easy-rsa, etc.)"
    echo ""
    echo -e "  ${YELLOW}Install dir: ${INSTALL_DIR}${NC}"
    echo ""
    echo -n "  Type YES to confirm uninstall (case sensitive): "
    read -r _confirm
    if [[ "$_confirm" != "YES" ]]; then
        info "Cancelled[CN]"
        return
    fi

    echo ""
    title "Starting uninstall"

    # ── 步骤1:停止并禁用所有服务 ────────────────────────────────────────────
    info "Step 1/8: Stopping OpenVPN services..."
    for svc in \
        openvpn-tun-udp.service \
        openvpn-tun-tcp.service \
        openvpn-tap-udp.service \
        openvpn-tap-tcp.service \
        openvpn-tun-udp.socket \
        openvpn-tap-udp.socket
    do
        if systemctl is-active "$svc" &>/dev/null; then
            systemctl stop "$svc" 2>/dev/null && info "  Stopped: $svc" || true
        fi
        if systemctl is-enabled "$svc" &>/dev/null; then
            systemctl disable "$svc" 2>/dev/null && info "  disabledautostart: $svc" || true
        fi
    done
    # 同时尝试停止系统默认路径的 openvpn 服务
    systemctl stop  openvpn.service     2>/dev/null || true
    systemctl disable openvpn.service   2>/dev/null || true
    systemctl stop  openvpn@tun.service 2>/dev/null || true
    systemctl stop  openvpn@tap.service 2>/dev/null || true
    success "All services stopped"

    # ── 步骤2:删除 systemd 服务文件 ─────────────────────────────────────────
    info "Step 2/8: Removing systemd files..."
    local systemd_files=(
        "/etc/systemd/system/openvpn-tun-udp.service"
        "/etc/systemd/system/openvpn-tun-tcp.service"
        "/etc/systemd/system/openvpn-tap-udp.service"
        "/etc/systemd/system/openvpn-tap-tcp.service"
        "/etc/systemd/system/openvpn-tun-udp.socket"
        "/etc/systemd/system/openvpn-tap-udp.socket"
    )
    for f in "${systemd_files[@]}"; do
        if [[ -f "$f" ]]; then
            rm -f "$f"
            info "  Removed: $f"
        fi
    done
    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true
    success "systemd files cleaned"

    # ── 步骤3:清理 iptables 规则 ─────────────────────────────────────────────
    info "Step 3/8: Cleaning iptables rules..."
    local iface
    iface=$(ip route show default 2>/dev/null | grep -m1 "^default" | cut -d" " -f5)
    iface="${iface:-eth0}"

    # 删除 NAT 规则
    for subnet in "${VPN_SUBNET_TUN}/24" "${VPN_SUBNET_TAP}/24"; do
        iptables  -t nat -D POSTROUTING -s "$subnet" -o "$iface" -j MASQUERADE 2>/dev/null || true
    done
    # 删除 FORWARD 规则
    for subnet in "${VPN_SUBNET_TUN}/24" "${VPN_SUBNET_TAP}/24"; do
        iptables  -D FORWARD -s "$subnet" -j ACCEPT 2>/dev/null || true
    done
    iptables  -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    # 删除 INPUT 规则(port放行)
    for port in "$PORT_TUN" "$PORT_TAP"; do
        iptables  -D INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null || true
        iptables  -D INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || true
        # 同时清理 ip6tables
        if command -v ip6tables &>/dev/null; then
            ip6tables -D INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null || true
            ip6tables -D INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || true
        fi
    done
    if command -v ip6tables &>/dev/null; then
        ip6tables -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    fi
    success "iptables rules cleaned"

    # ── 步骤4:清理 tc/ifb rate limit rules ──────────────────────────────────────────
    info "[CN] 4/8:[CN] tc/ifb rate limit rules..."
    if command -v tc &>/dev/null; then
        # 清理所有 tun/tap 接口上的 qdisc
        mapfile -t iface_list < <(ip -o link show | grep -oE "tun[0-9]+|tap[0-9]+")
        for iface_name in "${iface_list[@]:-}"; do
            [[ -z "$iface_name" ]] && continue
            tc qdisc del dev "$iface_name" root      2>/dev/null || true
            tc qdisc del dev "$iface_name" handle ffff: ingress 2>/dev/null || true
            info "  Cleaned interface: $iface_name"
        done
        # 清理 ifb 接口
        while IFS= read -r ifb_name; do
            [[ -z "$ifb_name" ]] && continue
            tc qdisc del dev "$ifb_name" root 2>/dev/null || true
            ip link set "$ifb_name" down 2>/dev/null || true
            ip link del "$ifb_name"      2>/dev/null || true
            info "  Removed ifb interface: $ifb_name"
        done < <(ip -o link show type ifb 2>/dev/null | grep -oE "ifb[0-9]+")
        # 卸载 ifb 内核模块
        rmmod ifb 2>/dev/null || true
    fi
    # 清理临时 tc Status文件
    rm -f /tmp/ovpn_tc_* 2>/dev/null || true
    success "tc/ifb rules cleaned"

    # ── 步骤5:删除Install dir ───────────────────────────────────────────────────
    info "Step 5/8: Removing install directory ${INSTALL_DIR}..."
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        success "Install dirRemoved: $INSTALL_DIR"
    else
        warn "Install dir not found, skipping: $INSTALL_DIR"
    fi

    # ── 步骤6:卸载软件包 ────────────────────────────────────────────────────
    info "Step 6/8: Removing packages..."
    detect_os 2>/dev/null || true
    echo ""
    echo -n "  [CN] easy-rsa,bridge-utils [CN]?[y/N]: "
    read -r _rm_deps

    case "${OS_FAMILY:-debian}" in
        debian)
            if [[ "$_rm_deps" =~ ^[Yy]$ ]]; then
                ${PKG_MGR:-apt-get} remove -y openvpn easy-rsa bridge-utils 2>/dev/null || true
                ${PKG_MGR:-apt-get} autoremove -y 2>/dev/null || true
            else
                ${PKG_MGR:-apt-get} remove -y openvpn 2>/dev/null || true
            fi
            ${PKG_MGR:-apt-get} purge -y openvpn 2>/dev/null || true
            ;;
        rhel)
            if [[ "$_rm_deps" =~ ^[Yy]$ ]]; then
                ${PKG_MGR:-yum} remove -y openvpn easy-rsa bridge-utils 2>/dev/null || true
            else
                ${PKG_MGR:-yum} remove -y openvpn 2>/dev/null || true
            fi
            ;;
        arch)
            if [[ "$_rm_deps" =~ ^[Yy]$ ]]; then
                pacman -Rns --noconfirm openvpn easy-rsa bridge-utils 2>/dev/null || true
            else
                pacman -Rns --noconfirm openvpn 2>/dev/null || true
            fi
            ;;
        suse)
            if [[ "$_rm_deps" =~ ^[Yy]$ ]]; then
                zypper --non-interactive remove openvpn easy-rsa bridge-utils 2>/dev/null || true
            else
                zypper --non-interactive remove openvpn 2>/dev/null || true
            fi
            ;;
        alpine)
            if [[ "$_rm_deps" =~ ^[Yy]$ ]]; then
                apk del openvpn easy-rsa bridge 2>/dev/null || true
            else
                apk del openvpn 2>/dev/null || true
            fi
            ;;
    esac
    # 清理手动安装的 easy-rsa
    rm -f /usr/local/bin/easyrsa 2>/dev/null || true
    success "Packages removed"

    # ── 步骤7:清理 sysctl IP 转发设置 ──────────────────────────────────────
    info "Step 7/8: Cleaning IP forwarding..."
    echo ""
    echo -n "  Disable IP forwarding (net.ipv4.ip_forward)?"
    echo -n "Skip if other services need forwarding [y/N]: "
    read -r _rm_ipfwd
    if [[ "$_rm_ipfwd" =~ ^[Yy]$ ]]; then
        # 从 sysctl.conf 删除
        grep -v "net.ipv4.ip_forward" /etc/sysctl.conf > /tmp/_sysctl_tmp 2>/dev/null && \
            mv /tmp/_sysctl_tmp /etc/sysctl.conf || true
        grep -v "net.ipv4.ip_forward" /etc/sysctl.conf > /tmp/_sysctl_tmp 2>/dev/null && \
            mv /tmp/_sysctl_tmp /etc/sysctl.conf || true
        # 同时清理 /etc/sysctl.d/ 下可能的配置
        while IFS= read -r f; do
            grep -v "net.ipv4.ip_forward" "$f" > /tmp/_sysctl_tmp 2>/dev/null && \
                mv /tmp/_sysctl_tmp "$f" || true
        done < <(find /etc/sysctl.d/ -name "*.conf" 2>/dev/null)
        # 立即关闭
        echo 0 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true
        sysctl -p -q 2>/dev/null || true
        success "IP forwarding disabled"
    else
        info "Skipped, IP forwarding kept enabled"
    fi

    # ── 步骤8:最终清理检查 ──────────────────────────────────────────────────
    info "Step 8/8: Final cleanup..."
    # 清理可能残留的 openvpn pid 文件
    rm -f /var/run/openvpn*.pid 2>/dev/null || true
    rm -f /run/openvpn*.pid     2>/dev/null || true
    # 清理系统 openvpn 配置目录(如有)
    if [[ -d /etc/openvpn ]]; then
        echo ""
        echo -n "  [CN] /etc/openvpn [CN],[CN]?[y/N]: "
        read -r _rm_etc
        if [[ "$_rm_etc" =~ ^[Yy]$ ]]; then
            rm -rf /etc/openvpn
            info "  Removed: /etc/openvpn"
        fi
    fi
    # 清理 /tmp 下的临时文件
    rm -f /tmp/openvpn_* /tmp/ovpn_* 2>/dev/null || true
    success "Final cleanup done"

    # ── 卸载Done ──────────────────────────────────────────────────────────────
    clear
    echo -e "${GREEN}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║              OpenVPN uninstalled!                      ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  ${CYAN}Cleaned:${NC}"
    echo "  ✓ OpenVPN services stopped and disabled"
    echo "  ✓ systemd service and socket filesremoved"
    echo "  ✓ iptables rules cleaned"
    echo "  ✓ tc/ifb rate limit rules[CN]"
    echo "  ✓ Install dir ${INSTALL_DIR} removed"
    echo "  ✓ OpenVPN packages uninstalled"
    echo "  ✓ Temp files cleaned"
    echo ""
    echo -e "  ${YELLOW}[CN]:[CN]and[CN]Install dir[CN].${NC}"
    echo -e "  ${YELLOW}To reinstall, run: $0 install${NC}"
    echo ""
}


main() {
    check_root

    local cmd="${1:-help}"; shift || true

    # 非安装/卸载命令先加载已有配置(读取Install dirandport)
    if [[ "$cmd" != "install" && "$cmd" != "uninstall" && "$cmd" != "help" && "$cmd" != "--help" && "$cmd" != "-h" ]]; then
        load_config
    fi

    case "$cmd" in
        install)        do_install ;;
        uninstall)      do_uninstall ;;
        adduser|add)    add_user "$@" ;;
        user)
            local sub="${1:-list}"; shift || true
            manage_user "$sub" "$@"
            ;;
        log|logs)
            local lt="${1:-all}"; shift || true
            show_logs "$lt" "$@"
            ;;
        status)         show_status ;;
        restart)        restart_services ;;
        help|--help|-h) show_help ;;
        *)
            error "[CN]: $cmd"
            show_help; exit 1
            ;;
    esac
}

main "$@"
