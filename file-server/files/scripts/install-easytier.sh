#!/usr/bin/env bash
# ============================================================
#  EasyTier Node Install Script
#  Installs the latest EasyTier binaries (easytier-core, easytier-cli)
#  and configures a systemd service that connects to the config server.
#
#  Supported: Ubuntu / Debian, x86_64 / aarch64
#  Requires:  root (sudo), curl, unzip
#
#  Download & run:
#    curl -fsSL https://file.sshawn9.com/iet | sudo bash
#
#  With a machine ID (sets both --hostname and --machine-id):
#    curl -fsSL https://file.sshawn9.com/iet | sudo bash -s -- <machine-id>
#
#  Examples:
#    # Install with default settings (no machine ID)
#    curl -fsSL https://file.sshawn9.com/iet | sudo bash
#
#    # Install and register as "robot-01"
#    curl -fsSL https://file.sshawn9.com/iet | sudo bash -s -- robot-01
#
#    # Save the script first, then run with arguments
#    curl -fsSL -OJ https://file.sshawn9.com/iet
#    sudo bash install-easytier.sh robot-01
#
#  Arguments:
#    $1  machine-id  (optional) Unique identifier for this node.
#                    Used as both --hostname and --machine-id in the
#                    easytier-core command. If omitted, EasyTier assigns
#                    a random ID automatically.
#
#  Note on "bash -s -- <arg>" vs "bash -s <arg>":
#    "bash -s" reads the script from stdin; subsequent arguments become
#    the script's positional parameters ($1, $2, ...).
#    The "--" signals the end of bash's own options, so everything after
#    it is treated as a script argument, never as a bash flag.
#
#    Without "--", an argument starting with "-" would be interpreted as
#    a bash option, causing errors or unexpected behavior:
#      curl ... | sudo bash -s   -node5    # bash parses -n,-o,-d,-e,-5 as flags → breaks
#      curl ... | sudo bash -s -- -node5   # $1 = "-node5" as intended ✓
#
#    For normal names (e.g. "robot-01") both forms work identically.
#    Using "--" is a defensive best practice — always safe regardless
#    of what the argument looks like.
#
#  What this script does:
#    1. Detects architecture (x86_64 / aarch64)
#    2. Resolves the latest EasyTier release from GitHub
#    3. Downloads via dl-proxy (fallback: direct from GitHub)
#    4. Installs easytier-core and easytier-cli to /usr/bin
#    5. Creates and starts a systemd service "easytier"
#
#  After installation:
#    systemctl status easytier      # Check service status
#    systemctl restart easytier     # Restart the service
#    journalctl -u easytier -f      # Follow logs
#    easytier-cli peer              # List connected peers
#    easytier-cli route             # Show routing table
# ============================================================
set -euo pipefail

readonly INSTALL_DIR="/usr/bin"
readonly SERVICE_NAME="easytier"
readonly SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
readonly WEB_ADDR="wss://et-config.sshawn9.com:0/admin"

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
  MACHINE_ID="${1:-}"
}

# Resolve latest version tag from GitHub API, proxy-first + direct fallback
resolve_latest_version() {
  local api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
  local proxy_api_url="${DL_PROXY}/${api_url#https://}?token=${DL_TOKEN}"

  local json version
  for src in "proxy:$proxy_api_url" "direct:$api_url"; do
    local label="${src%%:*}" target="${src#*:}"
    if json=$(curl -fsSL --connect-timeout 10 "$target" 2>/dev/null); then
      version=$(printf '%s' "$json" | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | head -1)
      if [[ -n "$version" ]]; then
        printf '%s' "$version"
        return 0
      fi
    fi
    err "resolve version ($label) failed"
  done
  return 1
}

# Download EasyTier binary, proxy-first + direct fallback (each tried twice)
download_easytier() {
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64|aarch64) ;;
    *) die "Unsupported architecture: $arch" ;;
  esac

  local version
  version=$(resolve_latest_version) || die "Failed to detect latest version"
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

  download_easytier "$tmp_dir/easytier.zip"
  unzip -q "$tmp_dir/easytier.zip" -d "$tmp_dir"

  local bin
  for bin in easytier-core easytier-cli; do
    local found
    found=$(find "$tmp_dir" -name "$bin" -type f | head -1)
    if [[ -z "$found" ]]; then
      rm -rf "$tmp_dir"
      die "$bin not found in archive"
    fi
    install -m 755 "$found" "$INSTALL_DIR/$bin"
  done

  rm -rf "$tmp_dir"
  log "Installed to $INSTALL_DIR"
}

setup_service() {
  if [[ -z "$WEB_ADDR" ]]; then
    die "WEB_ADDR not configured"
  fi

  local exec_start="${INSTALL_DIR}/easytier-core"
  if [[ -n "$MACHINE_ID" ]]; then
    exec_start+=" --hostname ${MACHINE_ID} --machine-id ${MACHINE_ID}"
  fi
  exec_start+=" -w ${WEB_ADDR}"

  cat > "$SERVICE_FILE" <<-EOF
	[Unit]
	Description=A full meshed p2p VPN, connecting all your devices in one network with one command.
	After=network.target syslog.target
	StartLimitIntervalSec=0

	[Service]
	Type=simple
	WorkingDirectory=/tmp
	ExecStart=${exec_start}
	Restart=always
	RestartSec=1
	LimitNOFILE=infinity

	[Install]
	WantedBy=multi-user.target
	EOF

  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
  if [[ -n "$MACHINE_ID" ]]; then
    log "Service started (machine_id=${MACHINE_ID})"
  else
    log "Service started"
  fi
}

is_latest() {
  local current
  current=$("${INSTALL_DIR}/easytier-core" --version 2>/dev/null | grep -oP '[\d.]+' | head -1) || return 1
  local version
  version=$(resolve_latest_version) || return 1
  local latest="${version#v}"
  [[ "$current" == "$latest" ]]
}

## Detached upgrade: stop → replace binaries → start in a background process
## so that even if the current connection (e.g. via EasyTier) drops, the
## script still finishes.
do_upgrade_detached() {
  local tmp_dir="$1"
  local log_file="/tmp/easytier-upgrade.log"

  # This function runs detached from the terminal via setsid/nohup.
  {
    log "Stopping existing $SERVICE_NAME service ..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true

    local bin
    for bin in easytier-core easytier-cli; do
      local found
      found=$(find "$tmp_dir" -name "$bin" -type f | head -1)
      if [[ -z "$found" ]]; then
        err "$bin not found in archive"
        rm -rf "$tmp_dir"
        exit 1
      fi
      install -m 755 "$found" "$INSTALL_DIR/$bin"
    done
    rm -rf "$tmp_dir"
    log "Installed to $INSTALL_DIR"

    setup_service
    log "Upgrade complete!"
  } >> "$log_file" 2>&1
}

main() {
  check_root
  parse_args "$@"

  if is_latest; then
    log "Already up to date ($(${INSTALL_DIR}/easytier-core --version 2>/dev/null)), skipping download"
    setup_service
    return
  fi

  # Download first (while the connection is still alive)
  local tmp_dir
  tmp_dir=$(mktemp -d)
  download_easytier "$tmp_dir/easytier.zip"
  unzip -q "$tmp_dir/easytier.zip" -d "$tmp_dir"

  # Run stop → install → start detached from the terminal, so if the
  # EasyTier connection drops on stop, the script still finishes.
  log "Starting detached upgrade (log: /tmp/easytier-upgrade.log) ..."

  # Export functions and variables needed by the detached subprocess
  export INSTALL_DIR SERVICE_NAME SERVICE_FILE WEB_ADDR MACHINE_ID
  export -f log err die stop_existing setup_service do_upgrade_detached resolve_latest_version

  nohup setsid bash -c 'do_upgrade_detached "$@"' _ "$tmp_dir" </dev/null >/dev/null 2>&1 &
  log "Upgrade launched in background. Check /tmp/easytier-upgrade.log for results."
}

main "$@"
