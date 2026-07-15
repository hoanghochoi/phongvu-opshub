#!/usr/bin/env bash
set -euo pipefail

EXPECTED_HOST="mementoamoris"
CONFIRMATION="PREPARE_OPSHUB_STAGING_LOAD_USERS"
ENV_FILE="${OPSHUB_ENV_FILE:-/srv/opshub-staging/env}"
COMPOSE_FILE="deploy/home-server/docker-compose.home.yml"
OUTPUT_DIR="${OPSHUB_STAGING_LOAD_OUTPUT_DIR:-/srv/opshub-staging/load-output}"

fail() {
  echo "Staging load-user wrapper stopped: $*" >&2
  exit 1
}

[[ "$(hostname)" == "$EXPECTED_HOST" ]] || fail "expected hostname $EXPECTED_HOST"
[[ -f "$ENV_FILE" ]] || fail "runtime env file is missing"
grep -qx 'OPSHUB_STAGING=true' "$ENV_FILE" || fail "OPSHUB_STAGING=true is missing"
grep -qx 'OPSHUB_STAGING_SANITIZE_CONFIRM=opshub-staging' "$ENV_FILE" || fail "staging sentinel is missing"
grep -qx 'PUBLIC_BASE_URL=https://opshub-staging.hoanghochoi.com' "$ENV_FILE" || fail "public hostname is not staging"
grep -qx 'OPSHUB_STAGING_LOAD_MAINTENANCE_ENABLED=true' "$ENV_FILE" || fail "load maintenance gate is disabled"

RUNTIME_UID="$(sed -n 's/^OPSHUB_RUNTIME_UID=//p' "$ENV_FILE" | tail -n 1)"
RUNTIME_GID="$(sed -n 's/^OPSHUB_RUNTIME_GID=//p' "$ENV_FILE" | tail -n 1)"
[[ "$RUNTIME_UID" =~ ^[0-9]+$ ]] || fail "OPSHUB_RUNTIME_UID must be numeric"
[[ "$RUNTIME_GID" =~ ^[0-9]+$ ]] || fail "OPSHUB_RUNTIME_GID must be numeric"

ACTION="${1:-}"
RUN_ID="${2:-}"
CONFIRM="${3:-}"
[[ "$ACTION" =~ ^(prepare|revoke|delete|verify-empty)$ ]] || fail "action must be prepare, revoke, delete, or verify-empty"
[[ "$RUN_ID" =~ ^[a-z0-9]([a-z0-9-]{1,30}[a-z0-9])?$ ]] || fail "invalid run id"
[[ "$CONFIRM" == "$CONFIRMATION" ]] || fail "confirmation phrase does not match"

sudo install -d -m 0700 -o "$RUNTIME_UID" -g "$RUNTIME_GID" "$OUTPUT_DIR"
export OPSHUB_ENV_FILE="$ENV_FILE"
export OPSHUB_STAGING_LOAD_OUTPUT_DIR="$OUTPUT_DIR"

docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  --profile maintenance \
  build maintenance

ARGS=(
  --action "$ACTION"
  --run-id "$RUN_ID"
  --confirm "$CONFIRMATION"
)
if [[ "$ACTION" == "prepare" ]]; then
  ARGS+=(--output "/output/$RUN_ID.tokens.json")
fi

docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  --profile maintenance \
  run --rm -T maintenance \
  npm run load-users:staging -- "${ARGS[@]}"

if [[ "$ACTION" == "prepare" ]]; then
  MODE="$(stat -c '%a' "$OUTPUT_DIR/$RUN_ID.tokens.json")"
  [[ "$MODE" == "600" ]] || fail "token file mode is $MODE instead of 600"
  echo "Token file prepared outside the repository with mode 0600."
elif [[ "$ACTION" == "delete" || "$ACTION" == "verify-empty" ]]; then
  rm -f -- "$OUTPUT_DIR/$RUN_ID.tokens.json"
  [[ ! -e "$OUTPUT_DIR/$RUN_ID.tokens.json" ]] || fail "token file cleanup failed"
  if [[ "$ACTION" == "delete" ]]; then
    echo "Exactly 60 synthetic records were deleted, zero remain, and the token file was removed."
  else
    echo "Zero synthetic records remain and the token file was removed (idempotent recovery)."
  fi
fi
