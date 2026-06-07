#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="cloudflared-opshub-staging"
ENV_DIR="/etc/$SERVICE_NAME"
ENV_FILE="$ENV_DIR/env"
TOKEN_FILE="$ENV_DIR/token"
CLOUDFLARED_BIN="$(command -v cloudflared || true)"
TUNNEL_NAME="${CLOUDFLARED_TUNNEL_NAME:-opshub-staging}"
TUNNEL_HOSTNAME="${CLOUDFLARED_TUNNEL_HOSTNAME:-opshub-staging.hoanghochoi.com}"
TUNNEL_SERVICE="${CLOUDFLARED_TUNNEL_SERVICE:-http://127.0.0.1:8090}"
ORIGIN_CERT="${CLOUDFLARED_ORIGIN_CERT:-$HOME/.cloudflared/cert.pem}"
ROUTE_DNS="${CLOUDFLARED_ROUTE_DNS:-false}"

if [[ -z "$CLOUDFLARED_BIN" ]]; then
  echo "cloudflared is not installed on this host." >&2
  exit 1
fi

if [[ -z "${CLOUDFLARED_TUNNEL_TOKEN:-}" ]]; then
  if [[ ! -r "$ORIGIN_CERT" ]]; then
    cat >&2 <<EOF
CLOUDFLARED_TUNNEL_TOKEN is not set and origin cert is not readable: $ORIGIN_CERT
Set CLOUDFLARED_TUNNEL_TOKEN or run this on a host with cloudflared cert.pem.
EOF
    exit 1
  fi

  TUNNEL_ID="$($CLOUDFLARED_BIN --origincert "$ORIGIN_CERT" tunnel list 2>/dev/null |
    awk -v name="$TUNNEL_NAME" '$2 == name { print $1; exit }')"
  if [[ -z "$TUNNEL_ID" ]]; then
    "$CLOUDFLARED_BIN" --origincert "$ORIGIN_CERT" tunnel create "$TUNNEL_NAME" >/dev/null
    TUNNEL_ID="$($CLOUDFLARED_BIN --origincert "$ORIGIN_CERT" tunnel list 2>/dev/null |
      awk -v name="$TUNNEL_NAME" '$2 == name { print $1; exit }')"
  fi
  if [[ -z "$TUNNEL_ID" ]]; then
    echo "Could not find or create Cloudflare tunnel: $TUNNEL_NAME" >&2
    exit 1
  fi

  if [[ "$ROUTE_DNS" == "true" || "$ROUTE_DNS" == "1" ]]; then
    "$CLOUDFLARED_BIN" --origincert "$ORIGIN_CERT" tunnel route dns \
      --overwrite-dns "$TUNNEL_ID" "$TUNNEL_HOSTNAME"
  else
    echo "Skipping DNS route. Set CLOUDFLARED_ROUTE_DNS=true only when this cert can manage $TUNNEL_HOSTNAME."
  fi
  CLOUDFLARED_TUNNEL_TOKEN="$($CLOUDFLARED_BIN --origincert "$ORIGIN_CERT" tunnel token "$TUNNEL_ID")"
  if [[ -z "$CLOUDFLARED_TUNNEL_TOKEN" ]]; then
    echo "Could not create token for Cloudflare tunnel: $TUNNEL_NAME" >&2
    exit 1
  fi
fi

sudo install -d -m 0700 -o root -g root "$ENV_DIR"
printf '%s\n' "$CLOUDFLARED_TUNNEL_TOKEN" | sudo tee "$TOKEN_FILE" >/dev/null
sudo chmod 0600 "$TOKEN_FILE"
sudo rm -f "$ENV_FILE"

sudo tee "/etc/systemd/system/$SERVICE_NAME.service" >/dev/null <<EOF
[Unit]
Description=Cloudflare Tunnel for OpsHub staging
After=network-online.target
Wants=network-online.target

[Service]
TimeoutStartSec=15
Type=notify
ExecStart=$CLOUDFLARED_BIN tunnel --no-autoupdate run --token-file $TOKEN_FILE --url $TUNNEL_SERVICE
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME" >/dev/null
sudo systemctl restart "$SERVICE_NAME"
sudo systemctl status "$SERVICE_NAME" --no-pager
