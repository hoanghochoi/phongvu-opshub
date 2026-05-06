#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${1:-$SCRIPT_DIR/env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

COMPOSE_FILE="$SCRIPT_DIR/docker-compose.home.yml"
SSD_ROOT="${OPSHUB_SSD_ROOT:-/srv/opshub}"
BACKUP_ROOT="${OPSHUB_BACKUP_ROOT:-/mnt/truenas/opshub-backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$BACKUP_ROOT/$STAMP"

mkdir -p "$DEST"

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T postgres \
  pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" | gzip > "$DEST/postgres.sql.gz"

if [[ -d "$SSD_ROOT/uploads" ]]; then
  tar -C "$SSD_ROOT" -czf "$DEST/uploads.tar.gz" uploads
fi

cat > "$DEST/manifest.txt" <<EOF
created_at=$STAMP
postgres_dump=postgres.sql.gz
uploads_archive=uploads.tar.gz
source_ssd_root=$SSD_ROOT
EOF

if [[ "${BACKUP_PRUNE:-false}" == "true" ]]; then
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
    -mtime "+${BACKUP_RETENTION_DAYS:-30}" -print -exec rm -rf {} +
fi

echo "Backup created: $DEST"
