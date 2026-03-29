#!/usr/bin/env bash
# ============================================================
#  EasyTier Web Dashboard deploy script
#  For: Ubuntu / Debian
#  Usage: sudo bash deploy-easytier-web.sh
#  Idempotent: safe to re-run, will update service config
#
#  After deployment:
#    Node:    easytier-core -w wss://CONFIG_DOMAIN/<username>
#    Browser: https://WEB_DOMAIN
# ============================================================

# curl -fsSL https://deploy-easytier-web.sshawn9.com | sudo bash

set -euo pipefail

# ======================== Configuration ========================

# Cloudflare domains (required, DNS records with proxy enabled)
WEB_DOMAIN="easytier.sshawn9.com"
CONFIG_DOMAIN="et-config.sshawn9.com"

# Ports (official defaults)
API_PORT=11211
CONFIG_PORT=22020

# Config server protocol (ws for CF proxy, clients connect via wss://)
CONFIG_PROTOCOL=ws

# Data paths
DB_PATH="/var/lib/easytier/et.db"
GEOIP_PATH="/var/lib/easytier/GeoLite2-City.mmdb"
INSTALL_DIR="/usr/bin"

# Logging
LOG_DIR="/var/log/easytier"
LOG_LEVEL="warn"

# ======================== Internal ========================

readonly RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' NC='\033[0m'
readonly SERVICE_NAME="easytier-web"
readonly SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
readonly BIN_PATH="${INSTALL_DIR}/easytier-web-embed"

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ======================== Preflight ========================

check_root() {
    [[ $EUID -ne 0 ]] && error "Root required: sudo bash $0"
}

check_config() {
    [[ "$WEB_DOMAIN" == *"example.com"* ]] && error "Set WEB_DOMAIN before running"
    [[ "$CONFIG_DOMAIN" == *"example.com"* ]] && error "Set CONFIG_DOMAIN before running"
}

install_dependencies() {
    info "Installing dependencies..."
    apt-get update -qq
    apt-get install -y -qq curl unzip > /dev/null 2>&1
}

# ======================== Install ========================

install_easytier() {
    if [[ -f "$BIN_PATH" ]] && "$BIN_PATH" --version &>/dev/null; then
        info "Already installed ($("$BIN_PATH" --version 2>/dev/null)), skipping"
        return 0
    fi

    # Remove broken binary if exists but not executable
    [[ -f "$BIN_PATH" ]] && rm -f "$BIN_PATH"

    local arch version url tmp_zip tmp_dir bin_dir
    case "$(uname -m)" in
        x86_64)  arch="x86_64-unknown-linux-musl" ;;
        aarch64) arch="aarch64-unknown-linux-musl" ;;
        *)       error "Unsupported arch: $(uname -m)" ;;
    esac

    version=$(curl -fsSI "https://github.com/EasyTier/EasyTier/releases/latest" \
        | grep -i '^location:' | grep -oP '/tag/\K[^\s\r]+')
    [[ -z "$version" ]] && error "Failed to fetch latest version"

    url="https://github.com/EasyTier/EasyTier/releases/download/${version}/easytier-linux-${arch}-${version}.zip"
    info "Downloading EasyTier ${version}..."

    tmp_zip=$(mktemp /tmp/easytier_XXXXXX.zip)
    tmp_dir=$(mktemp -d /tmp/easytier_XXXXXX)
    trap 'rm -rf "$tmp_zip" "$tmp_dir"' EXIT

    curl -fSL -o "$tmp_zip" "$url"
    unzip -qo "$tmp_zip" -d "$tmp_dir"

    bin_dir=$(find "$tmp_dir" -name "easytier-web-embed" -printf '%h\n' -quit)
    [[ -z "$bin_dir" ]] && error "easytier-web-embed not found in archive"
    install -m 755 "${bin_dir}/easytier-web-embed" "$BIN_PATH"

    rm -rf "$tmp_zip" "$tmp_dir"
    trap - EXIT
    info "Installed to ${BIN_PATH}"
}

install_geoip() {
    if [[ -f "$GEOIP_PATH" ]]; then
        info "GeoIP database exists, skipping"
        return 0
    fi

    info "Downloading GeoLite2-City.mmdb..."
    curl -fSL -o "$GEOIP_PATH" \
        "https://raw.githubusercontent.com/P3TERX/GeoLite.mmdb/download/GeoLite2-City.mmdb"
    info "GeoIP database installed"
}

show_version() {
    info "Version: $("$BIN_PATH" --version 2>/dev/null || echo 'N/A')"
}

# ======================== Data ========================

prepare_dirs() {
    mkdir -p "$(dirname "$DB_PATH")"
    mkdir -p "$LOG_DIR"
}

# ======================== Systemd ========================

stop_existing_service() {
    if systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null; then
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        systemctl disable --quiet "$SERVICE_NAME" 2>/dev/null || true
        info "Stopped existing ${SERVICE_NAME}"
    fi
}

create_service() {
    info "Creating systemd service..."

    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=EasyTier Web Dashboard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BIN_PATH} \\
  --api-server-port ${API_PORT} \\
  --api-host https://${WEB_DOMAIN} \\
  --config-server-port ${CONFIG_PORT} \\
  --config-server-protocol ${CONFIG_PROTOCOL} \\
  --db ${DB_PATH} \\
  --file-log-level ${LOG_LEVEL} \\
  --file-log-dir ${LOG_DIR} \\
  --geoip-db ${GEOIP_PATH}
WorkingDirectory=$(dirname "$DB_PATH")
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
}

start_service() {
    systemctl daemon-reload
    systemctl enable --quiet "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"

    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        info "${SERVICE_NAME} started"
    else
        error "${SERVICE_NAME} failed to start, check: journalctl -u ${SERVICE_NAME} -n 30"
    fi
}

# ======================== Firewall ========================

configure_firewall() {
    if ! command -v ufw &>/dev/null; then
        warn "ufw not found, manually allow ports: ${API_PORT}/tcp, ${CONFIG_PORT}/tcp"
        return 0
    fi

    if ! ufw status | grep -q "Status: active"; then
        info "ufw inactive, skipping firewall config"
        return 0
    fi

    info "Adding ufw rules..."
    ufw allow 22/tcp comment "SSH" > /dev/null 2>&1 || true
    ufw allow "${API_PORT}/tcp" comment "EasyTier Web" > /dev/null 2>&1 || true
    ufw allow "${CONFIG_PORT}/tcp" comment "EasyTier Config WS" > /dev/null 2>&1 || true
    info "Firewall rules added"
}

# ======================== Summary ========================

print_result() {
    cat << EOF

============================================================
$(echo -e "${GREEN} EasyTier Web Dashboard deployed${NC}")
============================================================

  Web panel:       https://${WEB_DOMAIN}
  Config server:   wss://${CONFIG_DOMAIN} (origin ws://0.0.0.0:${CONFIG_PORT})
  Database:        ${DB_PATH}
  Logs:            ${LOG_DIR}

  Default accounts (CHANGE PASSWORDS IMMEDIATELY):
    admin / admin  (superuser)
    user  / user   (regular)

  Node connect:
    easytier-core -w wss://${CONFIG_DOMAIN}/<username>

  Service management:
    systemctl status ${SERVICE_NAME}
    systemctl restart ${SERVICE_NAME}
    journalctl -u ${SERVICE_NAME} -f

============================================================
  Cloudflare setup
============================================================

  1. Add two A records (proxy enabled / orange cloud):
     ${WEB_DOMAIN}    -> server IP
     ${CONFIG_DOMAIN} -> server IP

  2. Add two Origin Rules (CF dashboard -> Rules -> Origin Rules):

     Rule 1 - Web panel:
       Match: Hostname = ${WEB_DOMAIN}
       Action: Override destination port -> ${API_PORT}

     Rule 2 - Config server:
       Match: Hostname = ${CONFIG_DOMAIN}
       Action: Override destination port -> ${CONFIG_PORT}

  3. SSL/TLS:
     Set encryption mode to "Flexible"
     (CF terminates TLS, connects to origin via HTTP/WS)

  4. Network:
     Ensure WebSockets is enabled (on by default)

============================================================
EOF
}

# ======================== Main ========================

main() {
    check_root
    check_config
    install_dependencies
    install_easytier
    show_version
    prepare_dirs
    install_geoip
    stop_existing_service
    create_service
    start_service
    configure_firewall
    print_result
}

main "$@"
