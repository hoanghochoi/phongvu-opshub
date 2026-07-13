#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ "${1:-}" != "--confirm-staging-refresh" ]]; then
  echo "Refusing to refresh DB without --confirm-staging-refresh." >&2
  exit 1
fi

PROD_SSH_HOST="${PROD_SSH_HOST:-hoang-n8n}"
STAGING_SSH_HOST="${STAGING_SSH_HOST:-mementoamoris}"
PROD_CURRENT_DIR="${PROD_CURRENT_DIR:-/home/ubuntu/phongvu-opshub/current}"
PROD_ENV_FILE="${PROD_ENV_FILE:-/srv/opshub/env}"
PROD_SSD_ROOT="${PROD_SSD_ROOT:-/srv/opshub}"
PROD_COMPOSE_PROJECT_NAME="${PROD_COMPOSE_PROJECT_NAME:-}"
STAGING_CURRENT_DIR="${STAGING_CURRENT_DIR:-/home/hhh/phongvu-opshub-staging/current}"
STAGING_ENV_FILE="${STAGING_ENV_FILE:-/srv/opshub-staging/env}"
STAGING_SSD_ROOT="${STAGING_SSD_ROOT:-/srv/opshub-staging}"
STAGING_BACKUP_ROOT="${STAGING_BACKUP_ROOT:-$STAGING_SSD_ROOT/backups}"
STAGING_COMPOSE_PROJECT_NAME="${STAGING_COMPOSE_PROJECT_NAME:-opshub_staging}"

sq() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\''/g")"
}

echo "Preparing staging database on $STAGING_SSH_HOST..."
ssh "$STAGING_SSH_HOST" \
  "STAGING_CURRENT_DIR=$(sq "$STAGING_CURRENT_DIR") STAGING_ENV_FILE=$(sq "$STAGING_ENV_FILE") STAGING_SSD_ROOT=$(sq "$STAGING_SSD_ROOT") STAGING_BACKUP_ROOT=$(sq "$STAGING_BACKUP_ROOT") STAGING_COMPOSE_PROJECT_NAME=$(sq "$STAGING_COMPOSE_PROJECT_NAME") bash -s" <<'REMOTE'
set -euo pipefail
umask 077
cd "$STAGING_CURRENT_DIR"
export OPSHUB_ENV_FILE="$STAGING_ENV_FILE"
export OPSHUB_SSD_ROOT="$STAGING_SSD_ROOT"
export COMPOSE_PROJECT_NAME="$STAGING_COMPOSE_PROJECT_NAME"
compose=(docker compose --env-file "$STAGING_ENV_FILE" -f deploy/home-server/docker-compose.home.yml)
compose_cmd() {
  "${compose[@]}" "$@" < /dev/null
}
compose_cmd up -d --wait postgres redis
compose_cmd stop api realtime caddy || true
install -d -m 0700 "$STAGING_BACKUP_ROOT"
backup_file="$STAGING_BACKUP_ROOT/pre-refresh-$(date -u +%Y%m%d-%H%M%S).sql.gz"
compose_cmd exec -T postgres sh -lc 'pg_dump --no-owner --no-privileges -U "$POSTGRES_USER" "$POSTGRES_DB"' | gzip > "$backup_file"
chmod 0600 "$backup_file"
echo "Staging database backup created: $backup_file"
compose_cmd exec -T postgres sh -lc '
  set -e
  dropdb --force -U "$POSTGRES_USER" --maintenance-db=postgres --if-exists "$POSTGRES_DB"
  createdb -U "$POSTGRES_USER" --owner "$POSTGRES_USER" "$POSTGRES_DB"
'
REMOTE

prod_project_export=""
if [[ -n "$PROD_COMPOSE_PROJECT_NAME" ]]; then
  prod_project_export="export COMPOSE_PROJECT_NAME=$(sq "$PROD_COMPOSE_PROJECT_NAME");"
fi
prod_dump_cmd="set -euo pipefail; cd $(sq "$PROD_CURRENT_DIR"); export OPSHUB_ENV_FILE=$(sq "$PROD_ENV_FILE"); export OPSHUB_SSD_ROOT=$(sq "$PROD_SSD_ROOT"); $prod_project_export docker compose --env-file $(sq "$PROD_ENV_FILE") -f deploy/home-server/docker-compose.home.yml exec -T postgres sh -lc 'pg_dump --clean --if-exists --no-owner --no-privileges -U \"\$POSTGRES_USER\" \"\$POSTGRES_DB\"' < /dev/null"
staging_import_cmd="set -euo pipefail; cd $(sq "$STAGING_CURRENT_DIR"); export OPSHUB_ENV_FILE=$(sq "$STAGING_ENV_FILE"); export OPSHUB_SSD_ROOT=$(sq "$STAGING_SSD_ROOT"); export COMPOSE_PROJECT_NAME=$(sq "$STAGING_COMPOSE_PROJECT_NAME"); docker compose --env-file $(sq "$STAGING_ENV_FILE") -f deploy/home-server/docker-compose.home.yml exec -T postgres sh -lc 'psql -v ON_ERROR_STOP=1 -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\"'"

echo "Streaming production dump from $PROD_SSH_HOST into staging. Raw dump is not written to disk locally."
ssh "$PROD_SSH_HOST" "$prod_dump_cmd" | ssh "$STAGING_SSH_HOST" "$staging_import_cmd"

echo "Running staging migrations and sanitizer..."
ssh "$STAGING_SSH_HOST" \
  "STAGING_CURRENT_DIR=$(sq "$STAGING_CURRENT_DIR") STAGING_ENV_FILE=$(sq "$STAGING_ENV_FILE") STAGING_SSD_ROOT=$(sq "$STAGING_SSD_ROOT") STAGING_COMPOSE_PROJECT_NAME=$(sq "$STAGING_COMPOSE_PROJECT_NAME") bash -s" <<'REMOTE'
set -euo pipefail
umask 077
cd "$STAGING_CURRENT_DIR"
export OPSHUB_ENV_FILE="$STAGING_ENV_FILE"
export OPSHUB_SSD_ROOT="$STAGING_SSD_ROOT"
export COMPOSE_PROJECT_NAME="$STAGING_COMPOSE_PROJECT_NAME"
compose=(docker compose --env-file "$STAGING_ENV_FILE" -f deploy/home-server/docker-compose.home.yml)
compose_cmd() {
  "${compose[@]}" "$@" < /dev/null
}
compose_cmd --profile migrate run --rm -T --build migrate
compose_cmd --profile maintenance run --rm -T --build \
  -e OPSHUB_STAGING=true \
  -e OPSHUB_STAGING_SANITIZE_CONFIRM=opshub-staging \
  maintenance npm run sanitize:staging
compose_cmd up -d --build --force-recreate api realtime caddy
compose_cmd ps
REMOTE

echo "Staging DB refresh and sanitization complete. Run deploy/staging/smoke-test-checklist-db-refresh-2026-06-08.md."
