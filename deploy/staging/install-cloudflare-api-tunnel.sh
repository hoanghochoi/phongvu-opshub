#!/usr/bin/env bash
set -euo pipefail

readonly APPROVAL_PHRASE="INSTALL_OPSHUB_STAGING_API_TUNNEL"
readonly SERVICE_NAME="cloudflared-opshub-staging-api"
readonly CURRENT_TUNNEL_NAME="opshub-staging"
readonly TUNNEL_NAME="opshub-staging-api"
readonly TUNNEL_HOSTNAME="api-opshub-staging.hoanghochoi.com"
readonly EXPECTED_DNS_ZONE="hoanghochoi.com"
readonly TUNNEL_SERVICE="http://127.0.0.1:8090"
readonly ORIGIN_HOST_HEADER="opshub-staging.hoanghochoi.com"
readonly METRICS_ADDRESS="127.0.0.1:20243"
readonly KEEPALIVE_CONNECTIONS="300"
readonly ENV_DIR="/etc/$SERVICE_NAME"
readonly CONFIG_FILE="$ENV_DIR/config.yml"
readonly CREDENTIAL_FILE="$ENV_DIR/credentials.json"
readonly UNIT_FILE="/etc/systemd/system/$SERVICE_NAME.service"

CLOUDFLARED_BIN="$(command -v cloudflared || true)"
ORIGIN_CERT="${CLOUDFLARED_ORIGIN_CERT:-$HOME/.cloudflared/cert.pem}"
ROUTE_DNS="${CLOUDFLARED_ROUTE_DNS:-false}"

fail() {
  echo "$*" >&2
  exit 1
}

if [[ "${CLOUDFLARED_API_TUNNEL_APPROVAL:-}" != "$APPROVAL_PHRASE" ]]; then
  fail "CLOUDFLARED_API_TUNNEL_APPROVAL must equal $APPROVAL_PHRASE"
fi
case "$ROUTE_DNS" in
  true | false) ;;
  *) fail "CLOUDFLARED_ROUTE_DNS must equal true or false" ;;
esac
if [[ -z "$CLOUDFLARED_BIN" ]]; then
  fail "cloudflared is not installed on this host"
fi
if [[ ! -r "$ORIGIN_CERT" ]]; then
  fail "Cloudflare origin cert is not readable: $ORIGIN_CERT"
fi

certificate_zone_name() {
  python3 - "$ORIGIN_CERT" <<'PY'
import base64
import json
import re
import sys
import urllib.request

source = open(sys.argv[1], encoding="utf-8").read()
match = re.search(
    r"BEGIN ARGO TUNNEL TOKEN-----\s*(.*?)\s*-----END ARGO TUNNEL TOKEN",
    source,
    re.S,
)
if not match:
    raise SystemExit("Cloudflare origin cert format is not recognized")
credential = json.loads(base64.b64decode("".join(match.group(1).split())))
zone_id = credential.get("zoneID")
api_token = credential.get("apiToken")
if not zone_id or not api_token:
    raise SystemExit("Cloudflare origin cert has no zone credential")
request = urllib.request.Request(
    f"https://api.cloudflare.com/client/v4/zones/{zone_id}",
    headers={"Authorization": f"Bearer {api_token}", "Accept": "application/json"},
)
with urllib.request.urlopen(request, timeout=15) as response:
    payload = json.load(response)
if not payload.get("success") or payload.get("result", {}).get("name") is None:
    raise SystemExit("Cloudflare origin cert zone lookup failed")
print(payload["result"]["name"])
PY
}

if [[ "$ROUTE_DNS" == "true" ]]; then
  if ! command -v python3 >/dev/null 2>&1; then
    fail "python3 is required for the DNS zone ownership preflight"
  fi
  certificate_zone="$(certificate_zone_name)"
  if [[ "$certificate_zone" != "$EXPECTED_DNS_ZONE" ]]; then
    fail "Origin cert zone is $certificate_zone, expected $EXPECTED_DNS_ZONE; refusing DNS publication"
  fi
fi

lookup_tunnel_id() {
  local name="$1"
  "$CLOUDFLARED_BIN" --origincert "$ORIGIN_CERT" tunnel list 2>/dev/null |
    awk -v tunnel_name="$name" '$2 == tunnel_name { print $1; exit }'
}

current_tunnel_id="$(lookup_tunnel_id "$CURRENT_TUNNEL_NAME")"
if [[ -z "$current_tunnel_id" ]]; then
  fail "Protected current tunnel was not found: $CURRENT_TUNNEL_NAME"
fi

tunnel_id="$(lookup_tunnel_id "$TUNNEL_NAME")"
if [[ -z "$tunnel_id" ]]; then
  "$CLOUDFLARED_BIN" --origincert "$ORIGIN_CERT" tunnel create \
    "$TUNNEL_NAME" >/dev/null
  for _ in {1..10}; do
    tunnel_id="$(lookup_tunnel_id "$TUNNEL_NAME")"
    [[ -n "$tunnel_id" ]] && break
    sleep 1
  done
fi
if [[ ! "$tunnel_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  fail "Could not resolve a valid tunnel id for $TUNNEL_NAME"
fi
if [[ "$tunnel_id" == "$current_tunnel_id" ]]; then
  fail "API-only tunnel must not reuse the protected current tunnel"
fi

source_credential="$HOME/.cloudflared/$tunnel_id.json"
if [[ ! -r "$source_credential" ]]; then
  fail "Local credential for $TUNNEL_NAME is not readable: $source_credential"
fi

config_tmp="$(mktemp)"
unit_tmp="$(mktemp)"
cleanup() {
  rm -f "$config_tmp" "$unit_tmp"
}
trap cleanup EXIT

cat >"$config_tmp" <<EOF
tunnel: "$tunnel_id"
credentials-file: "$CREDENTIAL_FILE"
ingress:
  - hostname: "$TUNNEL_HOSTNAME"
    path: "^/api/.*$"
    service: "$TUNNEL_SERVICE"
    originRequest:
      httpHostHeader: "$ORIGIN_HOST_HEADER"
      keepAliveConnections: $KEEPALIVE_CONNECTIONS
  - service: "http_status:404"
EOF

"$CLOUDFLARED_BIN" tunnel --config "$config_tmp" ingress validate

cat >"$unit_tmp" <<EOF
[Unit]
Description=Cloudflare API-only Tunnel for OpsHub staging
After=network-online.target
Wants=network-online.target

[Service]
TimeoutStartSec=30
Type=notify
ExecStart=$CLOUDFLARED_BIN tunnel --config $CONFIG_FILE --metrics $METRICS_ADDRESS --no-autoupdate run $tunnel_id
Restart=on-failure
RestartSec=5s
NoNewPrivileges=true
PrivateTmp=true
ProtectClock=true
ProtectControlGroups=true
ProtectHome=true
ProtectKernelLogs=true
ProtectKernelModules=true
ProtectKernelTunables=true
ProtectSystem=strict
RestrictRealtime=true
RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
EOF

sudo install -d -m 0700 -o root -g root "$ENV_DIR"
sudo install -m 0600 -o root -g root "$source_credential" "$CREDENTIAL_FILE"
sudo install -m 0600 -o root -g root "$config_tmp" "$CONFIG_FILE"
sudo install -m 0644 -o root -g root "$unit_tmp" "$UNIT_FILE"
sudo "$CLOUDFLARED_BIN" tunnel --config "$CONFIG_FILE" ingress validate
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME" >/dev/null
sudo systemctl restart "$SERVICE_NAME"
sudo systemctl is-active --quiet "$SERVICE_NAME"
if [[ "$ROUTE_DNS" == "true" ]]; then
  "$CLOUDFLARED_BIN" --origincert "$ORIGIN_CERT" tunnel route dns \
    --overwrite-dns "$tunnel_id" "$TUNNEL_HOSTNAME"
else
  printf 'DNS publication skipped; create proxied CNAME %s -> %s.cfargotunnel.com with the %s zone owner.\n' \
    "$TUNNEL_HOSTNAME" "$tunnel_id" "$EXPECTED_DNS_ZONE"
fi

printf 'Installed %s for %s via tunnel %s.\n' \
  "$SERVICE_NAME" "$TUNNEL_HOSTNAME" "$TUNNEL_NAME"
printf 'Metrics remain loopback-only at %s.\n' "$METRICS_ADDRESS"
