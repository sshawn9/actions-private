#!/usr/bin/env bash
set -euo pipefail

readonly INSTALL_DIR="/usr/bin"
readonly SERVICE_NAME="easytier"
readonly SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
readonly WEB_ADDR="wss://et-config.sshawn9.com/admin"  # TODO: fill in web management address

readonly GITHUB_REPO="EasyTier/EasyTier"
readonly DL_PROXY="{{DL_PROXY}}"
readonly DL_TOKEN="{{DL_TOKEN}}"

log()  { printf '[INFO]  %s\n' "$*"; }
err()  { printf '[ERROR] %s\n' "$*" >&2; }
die()  { err "$@"; exit 1; }

check_root() {
  if [[ $EUID -ne 0 ]]; then
    die "Please run as root (sudo)."
  fi
}

parse_args() {
  if [[ -z "${1:-}" ]]; then
    die "Usage: ${0##*/} <machine_id>"
  fi
  readonly MACHINE_ID="$1"
}

# Resolve latest version, download with proxy-first + direct fallback (each tried twice)
download_easytier() {
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64|aarch64) ;;
    *) die "Unsupported architecture: $arch" ;;
  esac

  local latest_url
  latest_url=$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${GITHUB_REPO}/releases/latest")
  local version="${latest_url##*/}"
  if [[ -z "$version" ]]; then
    die "Failed to detect latest version"
  fi
  log "Architecture: $arch, Version: $version"

  local url="https://github.com/${GITHUB_REPO}/releases/download/${version}/easytier-linux-${arch}-${version}.zip"
  local proxy_url="${DL_PROXY}/${url#https://}?token=${DL_TOKEN}"
  local output="$1"

  local src attempt
  for src in "proxy:$proxy_url" "direct:$url"; do
    local label="${src%%:*}" target="${src#*:}"
    for attempt in 1 2; do
      log "Downloading ($label, attempt $attempt) ..."
      if curl -fsSL --connect-timeout 10 "$target" -o "$output"; then
        return 0
      fi
      err "$label attempt $attempt failed"
    done
  done

  die "All download attempts failed"
}

stop_existing() {
  if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    log "Stopping existing $SERVICE_NAME service ..."
    systemctl stop "$SERVICE_NAME"
  fi
}

install_binary() {
  local tmp_dir
  tmp_dir=$(mktemp -d)
  trap 'rm -rf "$tmp_dir"' EXIT

  download_easytier "$tmp_dir/easytier.zip"
  unzip -q "$tmp_dir/easytier.zip" -d "$tmp_dir"

  local bin
  for bin in easytier-core easytier-cli; do
    local found
    found=$(find "$tmp_dir" -name "$bin" -type f | head -1)
    if [[ -z "$found" ]]; then
      die "$bin not found in archive"
    fi
    install -m 755 "$found" "$INSTALL_DIR/$bin"
  done

  log "Installed to $INSTALL_DIR"
}

setup_service() {
  if [[ -z "$WEB_ADDR" ]]; then
    die "WEB_ADDR not configured"
  fi

  cat > "$SERVICE_FILE" <<-EOF
	[Unit]
	Description=A full meshed p2p VPN, connecting all your devices in one network with one command.
	After=network.target syslog.target
	StartLimitIntervalSec=0

	[Service]
	Type=simple
	WorkingDirectory=/tmp
	ExecStart=${INSTALL_DIR}/easytier-core \\
	    --hostname ${MACHINE_ID} \\
	    --machine-id ${MACHINE_ID} \\
	    -w ${WEB_ADDR}
	Restart=always
	RestartSec=1
	LimitNOFILE=infinity

	[Install]
	WantedBy=multi-user.target
	EOF

  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
  log "Service started (machine_id=${MACHINE_ID})"
}

main() {
  check_root
  parse_args "$@"
  stop_existing
  install_binary
  setup_service
}

main "$@"
