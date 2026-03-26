#!/usr/bin/env bash
set -euo pipefail

readonly INSTALL_DIR="/usr/local/bin"
readonly SERVICE_NAME="easytier"
readonly SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
readonly WEB_ADDR=""  # TODO: fill in web management address

declare -A DOWNLOAD_URLS=(
  [x86_64]=""   # TODO: fill in
  [aarch64]=""  # TODO: fill in
  [armv7l]=""   # TODO: fill in
)

log()  { printf '[INFO]  %s\n' "$*"; }
err()  { printf '[ERROR] %s\n' "$*" >&2; }
die()  { err "$@"; exit 1; }

check_root() {
  (( EUID == 0 )) || die "Please run as root (sudo)."
}

parse_args() {
  [[ -n "${1:-}" ]] || die "Usage: ${0##*/} <machine_id>"
  readonly MACHINE_ID="$1"
}

get_download_url() {
  local arch
  arch=$(uname -m)
  [[ -v DOWNLOAD_URLS[$arch] ]] || die "Unsupported architecture: $arch"
  readonly DOWNLOAD_URL="${DOWNLOAD_URLS[$arch]}"
  [[ -n "$DOWNLOAD_URL" ]] || die "Download URL not configured for $arch"
  log "Architecture: $arch"
}

install_binary() {
  local tmp_dir
  tmp_dir=$(mktemp -d)
  trap 'rm -rf "$tmp_dir"' EXIT

  log "Downloading easytier ..."
  curl -fsSL "$DOWNLOAD_URL" -o "$tmp_dir/easytier.tar.gz"
  tar -xzf "$tmp_dir/easytier.tar.gz" -C "$tmp_dir"

  local bin
  for bin in easytier-core easytier-cli; do
    install -m 755 "$tmp_dir/$bin" "$INSTALL_DIR/$bin"
  done

  log "Installed to $INSTALL_DIR"
}

setup_service() {
  [[ -n "$WEB_ADDR" ]] || die "WEB_ADDR not configured"

  cat > "$SERVICE_FILE" <<-EOF
	[Unit]
	Description=EasyTier VPN Service
	After=network.target

	[Service]
	Type=simple
	ExecStart=${INSTALL_DIR}/easytier-core \\
	    --hostname ${MACHINE_ID} \\
	    --instance-id ${MACHINE_ID} \\
	    --web-client-url ${WEB_ADDR}
	Restart=on-failure
	RestartSec=5

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
  get_download_url
  install_binary
  setup_service
}

main "$@"
