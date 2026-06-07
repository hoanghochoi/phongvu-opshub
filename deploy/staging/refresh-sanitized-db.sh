#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--confirm-staging-refresh" ]]; then
  echo "Refusing to refresh DB without --confirm-staging-refresh." >&2
  exit 1
fi

: "${STAGING_TEST_PASSWORD:?Set STAGING_TEST_PASSWORD for known staging users.}"

PROD_SSH_HOST="${PROD_SSH_HOST:-hoang-n8n}"
STAGING_SSH_HOST="${STAGING_SSH_HOST:-mementoamoris}"
PROD_CURRENT_DIR="${PROD_CURRENT_DIR:-/home/ubuntu/phongvu-opshub/current}"
PROD_ENV_FILE="${PROD_ENV_FILE:-/srv/opshub/env}"
STAGING_CURRENT_DIR="${STAGING_CURRENT_DIR:-/home/hhh/phongvu-opshub-staging/current}"
STAGING_ENV_FILE="${STAGING_ENV_FILE:-/srv/opshub-staging/env}"

sq() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\''/g")"
}

echo "Preparing staging database on $STAGING_SSH_HOST..."
ssh "$STAGING_SSH_HOST" \
  "STAGING_CURRENT_DIR=$(sq "$STAGING_CURRENT_DIR") STAGING_ENV_FILE=$(sq "$STAGING_ENV_FILE") bash -s" <<'REMOTE'
set -euo pipefail
cd "$STAGING_CURRENT_DIR"
set -a
. "$STAGING_ENV_FILE"
set +a
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-opshub_staging}"
compose=(docker compose --env-file "$STAGING_ENV_FILE" -f deploy/home-server/docker-compose.home.yml)
"${compose[@]}" up -d --wait postgres redis
"${compose[@]}" stop api realtime caddy || true
"${compose[@]}" exec -T postgres sh -lc '
  psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=1 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '\''$POSTGRES_DB'\'' AND pid <> pg_backend_pid();"
  dropdb -U "$POSTGRES_USER" --if-exists "$POSTGRES_DB"
  createdb -U "$POSTGRES_USER" "$POSTGRES_DB"
'
REMOTE

prod_dump_cmd="set -euo pipefail; cd $(sq "$PROD_CURRENT_DIR"); set -a; . $(sq "$PROD_ENV_FILE"); set +a; docker compose --env-file $(sq "$PROD_ENV_FILE") -f deploy/home-server/docker-compose.home.yml exec -T postgres pg_dump --no-owner --no-privileges -U \"\$POSTGRES_USER\" \"\$POSTGRES_DB\""
staging_import_cmd="set -euo pipefail; cd $(sq "$STAGING_CURRENT_DIR"); set -a; . $(sq "$STAGING_ENV_FILE"); set +a; export COMPOSE_PROJECT_NAME=\"\${COMPOSE_PROJECT_NAME:-opshub_staging}\"; docker compose --env-file $(sq "$STAGING_ENV_FILE") -f deploy/home-server/docker-compose.home.yml exec -T postgres psql -v ON_ERROR_STOP=1 -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\""

echo "Streaming production dump from $PROD_SSH_HOST into staging. Raw dump is not written to disk locally."
ssh "$PROD_SSH_HOST" "$prod_dump_cmd" | ssh "$STAGING_SSH_HOST" "$staging_import_cmd"

echo "Running staging migrations and sanitizer..."
ssh "$STAGING_SSH_HOST" \
  "STAGING_CURRENT_DIR=$(sq "$STAGING_CURRENT_DIR") STAGING_ENV_FILE=$(sq "$STAGING_ENV_FILE") STAGING_TEST_PASSWORD=$(sq "$STAGING_TEST_PASSWORD") bash -s" <<'REMOTE'
set -euo pipefail
cd "$STAGING_CURRENT_DIR"
set -a
. "$STAGING_ENV_FILE"
set +a
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-opshub_staging}"
compose=(docker compose --env-file "$STAGING_ENV_FILE" -f deploy/home-server/docker-compose.home.yml)
"${compose[@]}" --profile migrate run --rm -T --build migrate < /dev/null
"${compose[@]}" run --rm -T \
  -e OPSHUB_STAGING=true \
  -e OPSHUB_STAGING_SANITIZE_CONFIRM=opshub-staging \
  -e STAGING_TEST_PASSWORD="$STAGING_TEST_PASSWORD" \
  api npm run sanitize:staging
"${compose[@]}" up -d --build --force-recreate api realtime caddy
"${compose[@]}" ps
REMOTE

echo "Staging DB refresh and sanitization complete. Run deploy/staging/smoke-checklist.md."
