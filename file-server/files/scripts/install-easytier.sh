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

# ── Constants ────────────────────────────────────────────────
readonly INSTALL_DIR="/usr/bin"
readonly SERVICE_NAME="easytier"
readonly SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
readonly WEB_ADDR="wss://et-config.sshawn9.com:0/admin"

readonly GITHUB_REPO="EasyTier/EasyTier"
readonly DL_PROXY="{{DL_PROXY}}"
readonly DL_TOKEN="{{DL_TOKEN}}"

readonly UPGRADE_LOG="/tmp/easytier-upgrade.log"

# ── Logging helpers ──────────────────────────────────────────
log()  { printf '\033[32m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[33m[WARN]\033[0m  %s\n' "$*" >&2; }
err()  { printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()  { err "$@"; exit 1; }

step() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  printf '\n\033[1;36m[Step %d/%d]\033[0m %s\n' "$CURRENT_STEP" "$TOTAL_STEPS" "$*"
}

CURRENT_STEP=0
TOTAL_STEPS=0

# ── Preflight checks ────────────────────────────────────────
check_root() {
  if [[ $EUID -ne 0 ]]; then
    die "Please run as root (sudo)."
  fi
}

check_deps() {
  local missing=()
  for cmd in curl unzip; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing required commands: ${missing[*]}"
  fi
}

detect_arch() {
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64|aarch64) ;;
    *) die "Unsupported architecture: $ARCH" ;;
  esac
  log "Architecture: $ARCH"
}

# ── Version resolution (proxy-first) ────────────────────────
resolve_latest_version() {
  local api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
  local proxy_api_url="${DL_PROXY}/${api_url#https://}?token=${DL_TOKEN}"

  local json ver
  for src in "proxy:$proxy_api_url" "direct:$api_url"; do
    local label="${src%%:*}" target="${src#*:}"
    log "Resolving latest version ($label) ..."
    if json=$(curl -fsSL --connect-timeout 10 "$target" 2>/dev/null); then
      ver=$(printf '%s' "$json" | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | head -1)
      if [[ -n "$ver" ]]; then
        LATEST_VERSION="$ver"
        log "Latest version: $LATEST_VERSION"
        return 0
      fi
    fi
    warn "Resolve version via $label failed, trying next ..."
  done
  return 1
}

check_upgrade_needed() {
  local current
  current=$("${INSTALL_DIR}/easytier-core" --version 2>/dev/null | grep -oP '[\d.]+' | head -1) || return 0

  resolve_latest_version || return 0
  local latest="${LATEST_VERSION#v}"

  if [[ "$current" == "$latest" ]]; then
    log "Current: v$current = Latest: v$latest (up to date)"
    return 1  # no upgrade needed
  else
    log "Current: v$current -> Latest: v$latest (upgrade needed)"
    return 0
  fi
}

# ── Download (proxy-first, each tried twice) ─────────────────
download_binary() {
  local output="$1"

  # LATEST_VERSION is already set by check_upgrade_needed / resolve_latest_version
  if [[ -z "${LATEST_VERSION:-}" ]]; then
    resolve_latest_version || die "Failed to detect latest version"
  fi

  local url="https://github.com/${GITHUB_REPO}/releases/download/${LATEST_VERSION}/easytier-linux-${ARCH}-${LATEST_VERSION}.zip"
  local proxy_url="${DL_PROXY}/${url#https://}?token=${DL_TOKEN}"

  local src attempt
  for src in "proxy:$proxy_url" "direct:$url"; do
    local label="${src%%:*}" target="${src#*:}"
    for attempt in 1 2; do
      log "Downloading ($label, attempt $attempt/2) ..."
      if curl -fsSL --connect-timeout 10 "$target" -o "$output"; then
        log "Download complete"
        return 0
      fi
      warn "$label attempt $attempt failed"
    done
  done

  die "All download attempts failed"
}

# ── Service management ───────────────────────────────────────
write_service_file() {
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

  log "Service file written: $SERVICE_FILE"
}

start_service() {
  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
  log "Service $SERVICE_NAME enabled and started"
  if [[ -n "$MACHINE_ID" ]]; then
    log "Machine ID: $MACHINE_ID"
  fi
}

# ── Detached upgrade ─────────────────────────────────────────
# Runs stop -> replace binaries -> start in a background process detached
# from the terminal, so that even if the connection (e.g. via EasyTier)
# drops on stop, the script still finishes.
do_upgrade_detached() {
  local tmp_dir="$1"

  {
    log "=== Detached upgrade started at $(date) ==="

    log "Stopping $SERVICE_NAME service ..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    log "Service stopped"

    log "Installing binaries to $INSTALL_DIR ..."
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
      log "  Installed: $bin"
    done
    rm -rf "$tmp_dir"

    log "Writing service configuration ..."
    write_service_file

    log "Starting service ..."
    start_service

    log "=== Upgrade complete at $(date) ==="
  } >> "$UPGRADE_LOG" 2>&1
}

# ── Main ─────────────────────────────────────────────────────
main() {
  check_root

  MACHINE_ID="${1:-}"
  ARCH=""
  LATEST_VERSION=""

  printf '\n\033[1m  EasyTier Node Installer\033[0m\n'
  if [[ -n "$MACHINE_ID" ]]; then
    printf '  Machine ID: %s\n' "$MACHINE_ID"
  fi
  printf '\n'

  # Decide total steps based on whether an upgrade is needed
  log "Checking prerequisites ..."
  check_deps
  detect_arch

  log "Checking installed version ..."
  if ! check_upgrade_needed; then
    TOTAL_STEPS=2

    step "Update service configuration"
    write_service_file

    step "Restart service"
    start_service

    printf '\n\033[1;32m  Already up to date. Service restarted.\033[0m\n\n'
    return
  fi

  TOTAL_STEPS=4

  step "Download latest release"
  local tmp_dir
  tmp_dir=$(mktemp -d)
  download_binary "$tmp_dir/easytier.zip"

  step "Extract archive"
  unzip -q "$tmp_dir/easytier.zip" -d "$tmp_dir"
  local count
  count=$(find "$tmp_dir" \( -name "easytier-core" -o -name "easytier-cli" \) -type f | wc -l)
  log "Extracted $count binaries"
  if [[ "$count" -lt 2 ]]; then
    rm -rf "$tmp_dir"
    die "Expected 2 binaries (easytier-core, easytier-cli), found $count"
  fi

  step "Stop service & install binaries (detached)"
  log "The upgrade will continue in a detached background process."
  log "This prevents connection loss from interrupting the upgrade."
  log "Progress log: $UPGRADE_LOG"
  : > "$UPGRADE_LOG"

  export INSTALL_DIR SERVICE_NAME SERVICE_FILE WEB_ADDR MACHINE_ID UPGRADE_LOG
  export -f log warn err die write_service_file start_service do_upgrade_detached resolve_latest_version

  nohup setsid bash -c 'do_upgrade_detached "$@"' _ "$tmp_dir" </dev/null >/dev/null 2>&1 &

  step "Done"
  log "Upgrade launched in background (PID: $!)"
  log "Check progress: cat $UPGRADE_LOG"
  log "After reconnecting: systemctl status easytier"

  printf '\n\033[1;32m  Upgrade in progress. Service will restart automatically.\033[0m\n\n'
}

main "$@"
