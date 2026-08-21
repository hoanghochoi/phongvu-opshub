#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${1:-$SCRIPT_DIR/env}"
ACTION="${2:-prepare}"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.home.yml"
KEYS=(
  BIDV_H2H_KEK_BASE64
  BIDV_H2H_INGEST_ENABLED
  BIDV_H2H_PROJECTION_ENABLED
  BIDV_H2H_PUBLIC_BASE_URL
  BIDV_H2H_ENVIRONMENT
)

[[ -f "$ENV_FILE" ]] || { echo "Missing runtime env file." >&2; exit 1; }

if [[ "$ACTION" == "clear" ]]; then
  for key in "${KEYS[@]}"; do
    sudo sed -i "/^${key}=/d" "$ENV_FILE"
  done
  echo "Legacy BIDV rollback bridge cleared."
  exit 0
fi
[[ "$ACTION" == "prepare" ]] || { echo "Action must be prepare or clear." >&2; exit 1; }

read_env() {
  local key="$1"
  sudo sed -n "s/^${key}=//p" "$ENV_FILE" | tail -n 1 | tr -d '\r'
}
upsert_env() {
  local key="$1" value="$2" escaped
  escaped="$(printf '%s' "$value" | sed 's/[\/&]/\\&/g')"
  if sudo grep -q "^${key}=" "$ENV_FILE"; then
    sudo sed -i "s/^${key}=.*/${key}=${escaped}/" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" | sudo tee -a "$ENV_FILE" >/dev/null
  fi
}

ssd_root="$(read_env OPSHUB_SSD_ROOT)"
ssd_root="${ssd_root:-/srv/opshub}"
secret_file="$ssd_root/secrets/bidv-h2h-kek"
sudo test -r "$secret_file" || { echo "BIDV KEK is unavailable; rollback bridge stopped." >&2; exit 1; }
kek="$(sudo cat "$secret_file" | tr -d '\r\n')"
[[ "$kek" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { echo "BIDV KEK is invalid; rollback bridge stopped." >&2; exit 1; }

export OPSHUB_ENV_FILE="$ENV_FILE"
postgres_user="$(read_env POSTGRES_USER)"
postgres_user="${postgres_user:-opshub}"
postgres_db="$(read_env POSTGRES_DB)"
postgres_db="${postgres_db:-opshub}"
legacy_pair="$(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T postgres \
  psql -Atq -F '|' -U "$postgres_user" -d "$postgres_db" \
  -c 'SELECT "ingressEnabled", "projectionEnabled" FROM "BankConnectionControl" WHERE "bankCode" = '\''BIDV'\'';')"
legacy_pair="${legacy_pair:-f|f}"
case "$legacy_pair" in
  'f|f') ingress=false; projection=false ;;
  't|f') ingress=true; projection=false ;;
  't|t') ingress=true; projection=true ;;
  *) echo "Unsafe BIDV legacy control pair; rollback bridge stopped." >&2; exit 1 ;;
esac

api_base="$(read_env PRIVATE_MEDIA_PUBLIC_BASE_URL)"
[[ "$api_base" =~ ^https://api(-staging)?\.phongvu\.work/v1/?$ ]] || {
  echo "Cannot derive BIDV legacy public endpoint." >&2
  exit 1
}
environment=production
[[ "$api_base" == *api-staging.phongvu.work* ]] && environment=staging

upsert_env BIDV_H2H_KEK_BASE64 "$kek"
upsert_env BIDV_H2H_INGEST_ENABLED "$ingress"
upsert_env BIDV_H2H_PROJECTION_ENABLED "$projection"
upsert_env BIDV_H2H_PUBLIC_BASE_URL "${api_base%/}/bidv"
upsert_env BIDV_H2H_ENVIRONMENT "$environment"
sudo chmod 0640 "$ENV_FILE"
unset kek
echo "Legacy BIDV rollback bridge prepared from local secret and synchronized controls."
