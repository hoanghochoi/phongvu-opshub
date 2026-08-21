#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${1:-$SCRIPT_DIR/env}"
COMPOSE_FILE="${2:-$SCRIPT_DIR/docker-compose.home.yml}"

[[ -f "$ENV_FILE" ]] || { echo "Missing runtime env file." >&2; exit 1; }

env_value() {
  local key="$1"
  local line
  line="$(grep -m1 "^${key}=" "$ENV_FILE" || true)"
  printf '%s' "${line#*=}" | tr -d '\r'
}

SSD_ROOT="$(env_value OPSHUB_SSD_ROOT)"
SSD_ROOT="${SSD_ROOT:-/srv/opshub}"
RUNTIME_GID="$(env_value OPSHUB_RUNTIME_GID)"
RUNTIME_GID="${RUNTIME_GID:-1000}"
SECRET_DIR="$SSD_ROOT/secrets"
SECRET_FILE="$SECRET_DIR/bidv-h2h-kek"
TMP_FILE="$(mktemp)"
CANDIDATE_FILE="$SECRET_DIR/.bidv-h2h-kek.candidate.$$"
trap 'rm -f -- "$TMP_FILE"; sudo rm -f -- "$CANDIDATE_FILE"' EXIT

validate_key_file() {
  local file="$1"
  local normalized decoded canonical
  normalized="$(tr -d '\r\n' < "$file")"
  [[ "$normalized" =~ ^[A-Za-z0-9+/]{43}=$ ]] || return 1
  decoded="$(printf '%s' "$normalized" | openssl base64 -d -A | wc -c | tr -d ' ')"
  [[ "$decoded" == "32" ]] || return 1
  canonical="$(printf '%s' "$normalized" | openssl base64 -d -A | openssl base64 -A)"
  [[ "$canonical" == "$normalized" ]]
}

sudo install -d -m 0750 -o root -g "$RUNTIME_GID" "$SECRET_DIR"
export OPSHUB_ENV_FILE="$ENV_FILE"
POSTGRES_USER="$(env_value POSTGRES_USER)"
POSTGRES_USER="${POSTGRES_USER:-opshub}"
POSTGRES_DB="$(env_value POSTGRES_DB)"
POSTGRES_DB="${POSTGRES_DB:-opshub}"
table_exists="$({
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T postgres \
    psql -Atq -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    -c "SELECT CASE WHEN to_regclass('\"BankPgpKey\"') IS NULL THEN 0 ELSE 1 END;"
} 2>/dev/null || true)"
[[ "$table_exists" =~ ^[01]$ ]] || { echo "Cannot verify protected BIDV data; deployment stopped." >&2; exit 1; }

verify_candidate_against_database() {
  local candidate="$1"
  [[ "$table_exists" == "1" ]] || return 0
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" \
    --profile maintenance run --rm -T --build \
    -v "$candidate:/run/secrets/bidv-h2h-kek:ro" \
    maintenance node scripts/verify-bidv-kek.mjs
}

if sudo test -f "$SECRET_FILE"; then
  sudo cp -- "$SECRET_FILE" "$TMP_FILE"
  validate_key_file "$TMP_FILE" || { echo "BIDV KEK file is invalid; deployment stopped." >&2; exit 1; }
  verify_candidate_against_database "$SECRET_FILE"
  sudo chown root:"$RUNTIME_GID" "$SECRET_FILE"
  sudo chmod 0440 "$SECRET_FILE"
  echo "BIDV KEK preflight: existing secret retained."
  exit 0
fi

LEGACY_KEK="$(env_value BIDV_H2H_KEK_BASE64)"
if [[ -n "$LEGACY_KEK" ]]; then
  printf '%s\n' "$LEGACY_KEK" > "$TMP_FILE"
  validate_key_file "$TMP_FILE" || { echo "Legacy BIDV KEK is invalid; deployment stopped." >&2; exit 1; }
  sudo install -m 0440 -o root -g "$RUNTIME_GID" "$TMP_FILE" "$CANDIDATE_FILE"
  verify_candidate_against_database "$CANDIDATE_FILE"
  sudo mv -f -- "$CANDIDATE_FILE" "$SECRET_FILE"
  echo "BIDV KEK preflight: validated legacy local secret migrated."
  exit 0
fi

evidence_count=0
if [[ "$table_exists" == "1" ]]; then
  evidence_count="$({
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T postgres \
      psql -Atq -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
      -c 'SELECT (SELECT count(*) FROM "BankPgpKey") + (SELECT count(*) FROM "BankTransaction");'
  } 2>/dev/null || true)"
fi
if [[ ! "$evidence_count" =~ ^[0-9]+$ || "$evidence_count" != "0" ]]; then
  echo "Protected BIDV data may already exist but the KEK is missing; deployment stopped." >&2
  exit 1
fi

openssl rand -base64 32 > "$TMP_FILE"
validate_key_file "$TMP_FILE" || { echo "Generated BIDV KEK failed validation." >&2; exit 1; }
sudo install -m 0440 -o root -g "$RUNTIME_GID" "$TMP_FILE" "$SECRET_FILE"
echo "BIDV KEK preflight: new environment secret created locally."
