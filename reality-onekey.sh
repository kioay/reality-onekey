#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

XRAY_INSTALL_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG="/usr/local/etc/xray/config.json"
CLIENT_OUT="/root/reality-client.txt"

PORT="443"
SERVER_NAME="www.cloudflare.com"
DEST=""
HOST=""
REMARK="reality"
UUID=""
SHORT_ID=""
SKIP_INSTALL="0"
NO_FIREWALL="0"
FORCE="0"

usage() {
  cat <<'USAGE'
Usage:
  sudo bash reality-onekey.sh [options]

Options:
  --host <ip-or-domain>       Server address used in the client link.
  --port <port>               Listen TCP port. Default: 443.
  --sni <domain>              REALITY serverName/SNI. Default: www.cloudflare.com.
  --dest <host:port>          REALITY target. Default: <sni>:443.
  --remark <name>             Client link name. Default: reality.
  --uuid <uuid>               Use an existing UUID instead of generating one.
  --short-id <hex>            Use an existing REALITY shortId instead of generating one.
  --skip-install              Do not run the official Xray installer.
  --no-firewall               Do not touch ufw/firewalld.
  --force                     Continue even if the listen port appears occupied.
  -h, --help                  Show help.

Examples:
  sudo bash reality-onekey.sh
  sudo bash reality-onekey.sh --host 203.0.113.10 --port 443 --sni www.microsoft.com
  sudo bash reality-onekey.sh --host vpn.example.com --port 8443 --dest www.cloudflare.com:443
USAGE
}

log() {
  printf '[reality] %s\n' "$*"
}

die() {
  printf '[reality] error: %s\n' "$*" >&2
  exit 1
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "run this script as root, for example: sudo bash $0"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --host)
        HOST="${2:-}"; shift 2 ;;
      --port)
        PORT="${2:-}"; shift 2 ;;
      --sni)
        SERVER_NAME="${2:-}"; shift 2 ;;
      --dest)
        DEST="${2:-}"; shift 2 ;;
      --remark)
        REMARK="${2:-}"; shift 2 ;;
      --uuid)
        UUID="${2:-}"; shift 2 ;;
      --short-id)
        SHORT_ID="${2:-}"; shift 2 ;;
      --skip-install)
        SKIP_INSTALL="1"; shift ;;
      --no-firewall)
        NO_FIREWALL="1"; shift ;;
      --force)
        FORCE="1"; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        die "unknown option: $1" ;;
    esac
  done
}

validate_args() {
  [[ "${PORT}" =~ ^[0-9]+$ ]] || die "--port must be a number"
  (( PORT >= 1 && PORT <= 65535 )) || die "--port must be between 1 and 65535"
  [[ -n "${SERVER_NAME}" ]] || die "--sni cannot be empty"
  if [[ -n "${SHORT_ID}" && ! "${SHORT_ID}" =~ ^[0-9a-fA-F]{2,16}$ ]]; then
    die "--short-id must be 2-16 hex characters"
  fi
  DEST="${DEST:-${SERVER_NAME}:443}"
}

install_deps() {
  log "Installing basic dependencies..."
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y curl ca-certificates openssl iproute2
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl ca-certificates openssl iproute
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl ca-certificates openssl iproute
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install curl ca-certificates openssl iproute2
  else
    die "unsupported package manager; install curl, ca-certificates, openssl, and iproute2 manually"
  fi
}

install_xray() {
  if [[ "${SKIP_INSTALL}" == "1" ]]; then
    log "Skipping Xray installation."
    command -v xray >/dev/null 2>&1 || [[ -x "${XRAY_BIN}" ]] || die "xray not found"
    return
  fi

  log "Installing/updating Xray with the official installer..."
  bash -c "$(curl -fsSL "${XRAY_INSTALL_URL}")" @ install
  [[ -x "${XRAY_BIN}" ]] || XRAY_BIN="$(command -v xray || true)"
  [[ -n "${XRAY_BIN}" && -x "${XRAY_BIN}" ]] || die "xray installation finished but xray binary was not found"
}

check_systemd() {
  command -v systemctl >/dev/null 2>&1 || die "systemd is required"
}

check_port() {
  if ! command -v ss >/dev/null 2>&1; then
    return
  fi

  local listeners
  listeners="$(ss -H -ltnp "sport = :${PORT}" 2>/dev/null || true)"
  if [[ -n "${listeners}" && "${FORCE}" != "1" ]]; then
    if ! grep -qi 'xray' <<<"${listeners}"; then
      printf '%s\n' "${listeners}" >&2
      die "tcp port ${PORT} is already in use; stop that service, choose --port, or pass --force"
    fi
  fi
}

detect_public_host() {
  local ip url
  for url in \
    "https://api64.ipify.org" \
    "https://ifconfig.me/ip" \
    "https://icanhazip.com"; do
    ip="$(curl -fsSL --max-time 6 "${url}" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ -n "${ip}" ]]; then
      printf '%s\n' "${ip}"
      return 0
    fi
  done
  return 1
}

ensure_host_for_link() {
  if [[ -z "${HOST}" ]]; then
    HOST="$(detect_public_host || true)"
  fi

  if [[ -z "${HOST}" && -t 0 ]]; then
    read -r -p "Server IP/domain for client link: " HOST
  fi

  if [[ -z "${HOST}" ]]; then
    HOST="YOUR_SERVER_IP_OR_DOMAIN"
  fi
}

generate_values() {
  [[ -x "${XRAY_BIN}" ]] || XRAY_BIN="$(command -v xray || true)"
  [[ -n "${XRAY_BIN}" && -x "${XRAY_BIN}" ]] || die "xray binary was not found"

  if [[ -z "${UUID}" ]]; then
    UUID="$("${XRAY_BIN}" uuid)"
  fi

  if [[ -z "${SHORT_ID}" ]]; then
    SHORT_ID="$(openssl rand -hex 8)"
  fi

  local keys
  keys="$("${XRAY_BIN}" x25519)"
  PRIVATE_KEY="$(awk -F': ' '/Private key|PrivateKey/ {print $2; exit}' <<<"${keys}")"
  PUBLIC_KEY="$(awk -F': ' '/Public key|PublicKey|Password \(PublicKey\)/ {print $2; exit}' <<<"${keys}")"
  [[ -n "${PRIVATE_KEY}" && -n "${PUBLIC_KEY}" ]] || die "failed to generate REALITY x25519 keys"
}

write_config() {
  log "Writing Xray config: ${XRAY_CONFIG}"
  install -d -m 0755 "$(dirname "${XRAY_CONFIG}")"

  if [[ -f "${XRAY_CONFIG}" ]]; then
    cp -a "${XRAY_CONFIG}" "${XRAY_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
  fi

  cat > "${XRAY_CONFIG}" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "block"
      }
    ]
  },
  "inbounds": [
    {
      "tag": "vless-reality-in",
      "listen": "0.0.0.0",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${DEST}",
          "xver": 0,
          "serverNames": [
            "${SERVER_NAME}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

  "${XRAY_BIN}" run -test -config "${XRAY_CONFIG}" >/dev/null
}

open_firewall() {
  if [[ "${NO_FIREWALL}" == "1" ]]; then
    log "Skipping host firewall changes."
    return
  fi

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi active; then
    log "Opening ${PORT}/tcp in ufw..."
    ufw allow "${PORT}/tcp"
  elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    log "Opening ${PORT}/tcp in firewalld..."
    firewall-cmd --permanent --add-port="${PORT}/tcp"
    firewall-cmd --reload
  else
    log "No active ufw/firewalld detected. Open ${PORT}/tcp in your cloud security group if needed."
  fi
}

restart_xray() {
  log "Enabling and restarting xray.service..."
  systemctl enable xray >/dev/null
  systemctl restart xray
  if ! systemctl is-active --quiet xray; then
    journalctl -u xray -n 80 --no-pager >&2 || true
    die "xray.service failed to start"
  fi
}

safe_remark() {
  printf '%s' "${REMARK}" | tr ' /?#&%' '______'
}

uri_host() {
  if [[ "${HOST}" == *:* && "${HOST}" != \[*\] ]]; then
    printf '[%s]' "${HOST}"
  else
    printf '%s' "${HOST}"
  fi
}

write_client_output() {
  local link h r
  h="$(uri_host)"
  r="$(safe_remark)"
  link="vless://${UUID}@${h}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SERVER_NAME}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none&spx=%2F#${r}"

  cat > "${CLIENT_OUT}" <<EOF
VLESS REALITY client link:
${link}

Server:
  address: ${HOST}
  port: ${PORT}
  protocol: vless
  uuid: ${UUID}
  flow: xtls-rprx-vision
  transport: tcp
  security: reality
  sni/serverName: ${SERVER_NAME}
  destination: ${DEST}
  fingerprint: chrome
  publicKey: ${PUBLIC_KEY}
  shortId: ${SHORT_ID}
  spiderX: /

Config:
  ${XRAY_CONFIG}

Service:
  systemctl status xray --no-pager
  journalctl -u xray -f
EOF

  chmod 0600 "${CLIENT_OUT}"

  printf '\n'
  log "Done. Client details were saved to ${CLIENT_OUT}"
  log "The generated VLESS link contains access credentials. Do not publish it."
  printf '\n%s\n\n' "${link}"
  log "Remember to open tcp/${PORT} in the VPS provider security group."
}

main() {
  parse_args "$@"
  validate_args
  need_root
  check_systemd
  install_deps
  install_xray
  check_port
  ensure_host_for_link
  generate_values
  write_config
  open_firewall
  restart_xray
  write_client_output
}

main "$@"
