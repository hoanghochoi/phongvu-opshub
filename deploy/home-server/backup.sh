#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${1:-$SCRIPT_DIR/env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 1
fi

read_env_value() {
  local key="$1"
  local default_value="${2:-}"
  local line value first last
  if [[ ! "$key" =~ ^[A-Z0-9_]+$ ]]; then
    echo "Invalid env key requested." >&2
    return 2
  fi
  line=$(grep -m1 "^${key}=" "$ENV_FILE" || true)
  if [[ -z "$line" ]]; then
    printf '%s' "$default_value"
    return
  fi
  value=${line#*=}
  value=${value%$'\r'}
  first=${value:0:1}
  last=${value: -1}
  if [[ "$first" == "'" || "$first" == '"' ]]; then
    if [[ ${#value} -lt 2 || "$last" != "$first" ]]; then
      echo "Invalid quoted dotenv value for $key." >&2
      return 2
    fi
    value=${value:1:${#value}-2}
  fi
  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    echo "Invalid multiline dotenv value for $key." >&2
    return 2
  fi
  printf '%s' "$value"
}

COMPOSE_FILE="$SCRIPT_DIR/docker-compose.home.yml"
export OPSHUB_ENV_FILE="$ENV_FILE"
SSD_ROOT="$(read_env_value OPSHUB_SSD_ROOT /srv/opshub)"
BACKUP_ROOT="$(read_env_value OPSHUB_BACKUP_ROOT /mnt/truenas/opshub-backups)"
BACKUP_AGE_RECIPIENT="$(read_env_value BACKUP_AGE_RECIPIENT)"
BACKUP_ALLOW_UNENCRYPTED="$(read_env_value BACKUP_ALLOW_UNENCRYPTED false)"
POSTGRES_USER="$(read_env_value POSTGRES_USER opshub)"
POSTGRES_DB="$(read_env_value POSTGRES_DB opshub)"
BACKUP_PRUNE="$(read_env_value BACKUP_PRUNE false)"
BACKUP_RETENTION_DAYS="$(read_env_value BACKUP_RETENTION_DAYS 30)"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$BACKUP_ROOT/$STAMP"
PARTIAL_DEST="$BACKUP_ROOT/.${STAMP}.partial"
BIDV_KEK_FILE="$SSD_ROOT/secrets/bidv-h2h-kek"

case "$BACKUP_ROOT" in
  ""|"/")
    echo "Refusing unsafe backup root: ${BACKUP_ROOT:-<empty>}" >&2
    exit 1
    ;;
esac

validate_bidv_kek_file() {
  local file="$1"
  local normalized decoded canonical
  normalized="$(tr -d '\r\n' < "$file")"
  [[ "$normalized" =~ ^[A-Za-z0-9+/]{43}=$ ]] || return 1
  decoded="$(printf '%s' "$normalized" | openssl base64 -d -A | wc -c | tr -d ' ')"
  [[ "$decoded" == "32" ]] || return 1
  canonical="$(printf '%s' "$normalized" | openssl base64 -d -A | openssl base64 -A)"
  [[ "$canonical" == "$normalized" ]]
}

export OPSHUB_ENV_FILE="$ENV_FILE"
bidv_tables_exist="$(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T postgres \
  psql -Atq -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -c "SELECT CASE WHEN to_regclass('\"BankPgpKey\"') IS NULL THEN 0 ELSE 1 END;" \
  2>/dev/null || true)"
[[ "$bidv_tables_exist" =~ ^[01]$ ]] || { echo "Cannot verify BIDV protected data; backup stopped." >&2; exit 1; }
bidv_protected_count=0
if [[ "$bidv_tables_exist" == "1" ]]; then
  bidv_protected_count="$(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T postgres \
    psql -Atq -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    -c 'SELECT (SELECT count(*) FROM "BankPgpKey") + (SELECT count(*) FROM "BankTransaction");' \
    2>/dev/null || true)"
fi
[[ "$bidv_protected_count" =~ ^[0-9]+$ ]] || { echo "Cannot count BIDV protected data; backup stopped." >&2; exit 1; }

if [[ -f "$BIDV_KEK_FILE" ]]; then
  validate_bidv_kek_file "$BIDV_KEK_FILE" || { echo "BIDV KEK is unreadable or invalid; backup stopped." >&2; exit 1; }
  [[ -n "$BACKUP_AGE_RECIPIENT" ]] || { echo "BIDV database and KEK require an age-encrypted backup." >&2; exit 1; }
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" \
    --profile maintenance run --rm -T maintenance node scripts/verify-bidv-kek.mjs
elif [[ "$bidv_protected_count" != "0" ]]; then
  echo "BIDV protected data exists but its KEK is missing; backup stopped." >&2
  exit 1
fi

if [[ -n "$BACKUP_AGE_RECIPIENT" ]]; then
  if ! command -v age >/dev/null 2>&1; then
    echo "BACKUP_AGE_RECIPIENT is set but the age command is unavailable." >&2
    exit 1
  fi
  BACKUP_SUFFIX=".age"
elif [[ "$BACKUP_ALLOW_UNENCRYPTED" == "true" ]]; then
  echo "WARNING: creating an explicitly approved unencrypted backup." >&2
  BACKUP_SUFFIX=""
else
  echo "Refusing to create an unencrypted backup." >&2
  echo "Set BACKUP_AGE_RECIPIENT, or explicitly set BACKUP_ALLOW_UNENCRYPTED=true for an approved emergency." >&2
  exit 1
fi

install -d -m 0700 "$BACKUP_ROOT"
if ! command -v flock >/dev/null 2>&1; then
  echo "The flock command is required to prevent overlapping backups." >&2
  exit 1
fi
exec 9>"$BACKUP_ROOT/.backup.lock"
chmod 0600 "$BACKUP_ROOT/.backup.lock"
if ! flock -n 9; then
  echo "Another OpsHub backup is already running." >&2
  exit 1
fi
if [[ -e "$DEST" || -e "$PARTIAL_DEST" ]]; then
  echo "Backup destination already exists for stamp: $STAMP" >&2
  exit 1
fi
install -d -m 0700 "$PARTIAL_DEST"
cleanup_partial() {
  if [[ -d "$PARTIAL_DEST" ]]; then
    rm -rf -- "$PARTIAL_DEST"
  fi
}
trap cleanup_partial EXIT

write_backup_stream() {
  local output_path="$1"
  if [[ -n "$BACKUP_AGE_RECIPIENT" ]]; then
    age --encrypt --recipient "$BACKUP_AGE_RECIPIENT" > "$output_path"
  else
    cat > "$output_path"
  fi
  chmod 0600 "$output_path"
  if [[ ! -s "$output_path" ]]; then
    echo "Backup artifact is empty: $output_path" >&2
    return 1
  fi
}

POSTGRES_ARCHIVE="postgres.sql.gz${BACKUP_SUFFIX}"
UPLOADS_ARCHIVE="none"
PRIVATE_MEDIA_ARCHIVE="none"
BIDV_KEK_ARCHIVE="none"

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T postgres \
  pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" | gzip -c | \
  write_backup_stream "$PARTIAL_DEST/$POSTGRES_ARCHIVE"

if [[ -d "$SSD_ROOT/uploads" ]]; then
  UPLOADS_ARCHIVE="uploads.tar.gz${BACKUP_SUFFIX}"
  tar -C "$SSD_ROOT" -czf - uploads | \
    write_backup_stream "$PARTIAL_DEST/$UPLOADS_ARCHIVE"
fi

if [[ -d "$SSD_ROOT/private-media" ]]; then
  PRIVATE_MEDIA_ARCHIVE="private-media.tar.gz${BACKUP_SUFFIX}"
  tar -C "$SSD_ROOT" -czf - private-media | \
    write_backup_stream "$PARTIAL_DEST/$PRIVATE_MEDIA_ARCHIVE"
fi

if [[ -f "$BIDV_KEK_FILE" ]]; then
  BIDV_KEK_ARCHIVE="bidv-h2h-kek.tar.gz${BACKUP_SUFFIX}"
  tar -C "$SSD_ROOT/secrets" -czf - bidv-h2h-kek | \
    write_backup_stream "$PARTIAL_DEST/$BIDV_KEK_ARCHIVE"
fi

cat > "$PARTIAL_DEST/manifest.txt" <<EOF
created_at=$STAMP
encryption=$([[ -n "$BACKUP_AGE_RECIPIENT" ]] && printf 'age' || printf 'none-explicitly-approved')
postgres_dump=$POSTGRES_ARCHIVE
uploads_archive=$UPLOADS_ARCHIVE
private_media_archive=$PRIVATE_MEDIA_ARCHIVE
bidv_kek_archive=$BIDV_KEK_ARCHIVE
source_ssd_root=$SSD_ROOT
EOF
chmod 0600 "$PARTIAL_DEST/manifest.txt"
printf 'opshub-backup-v1\n' > "$PARTIAL_DEST/.opshub-backup"
chmod 0600 "$PARTIAL_DEST/.opshub-backup"

(
  cd "$PARTIAL_DEST"
  checksum_files=("$POSTGRES_ARCHIVE" "manifest.txt" ".opshub-backup")
  if [[ "$UPLOADS_ARCHIVE" != "none" ]]; then
    checksum_files+=("$UPLOADS_ARCHIVE")
  fi
  if [[ "$PRIVATE_MEDIA_ARCHIVE" != "none" ]]; then
    checksum_files+=("$PRIVATE_MEDIA_ARCHIVE")
  fi
  if [[ "$BIDV_KEK_ARCHIVE" != "none" ]]; then
    checksum_files+=("$BIDV_KEK_ARCHIVE")
  fi
  sha256sum "${checksum_files[@]}" > SHA256SUMS
  chmod 0600 SHA256SUMS
)

mv -- "$PARTIAL_DEST" "$DEST"
trap - EXIT

if [[ "$BACKUP_PRUNE" == "true" ]]; then
  while IFS= read -r -d '' candidate; do
    [[ -f "$candidate/.opshub-backup" ]] || continue
    case "$(basename "$candidate")" in
      20??????-??????) ;;
      *) continue ;;
    esac
    printf 'Pruning verified OpsHub backup: %s\n' "$candidate"
    rm -rf -- "$candidate"
  done < <(
    find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
      -name '20??????-??????' -mtime "+${BACKUP_RETENTION_DAYS}" -print0
  )
fi

echo "Backup created: $DEST"
