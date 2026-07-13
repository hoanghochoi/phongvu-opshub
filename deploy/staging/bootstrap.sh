#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-/srv/opshub-staging/env}"
SSD_ROOT="${OPSHUB_SSD_ROOT:-/srv/opshub-staging}"
REMOTE_APP_DIR="${OPSHUB_REMOTE_APP_DIR:-/home/hhh/phongvu-opshub-staging}"
GROUP_NAME="$(id -gn)"
RUNTIME_UID="${OPSHUB_RUNTIME_UID:-1000}"
RUNTIME_GID="${OPSHUB_RUNTIME_GID:-1000}"

if [[ "$(hostname)" != "mementoamoris" ]]; then
  echo "Warning: expected to run on mementoamoris, got $(hostname)." >&2
fi

sudo mkdir -p \
  "$SSD_ROOT/postgres" \
  "$SSD_ROOT/redis" \
  "$SSD_ROOT/uploads" \
  "$SSD_ROOT/private-media" \
  "$SSD_ROOT/downloads" \
  "$SSD_ROOT/import" \
  "$SSD_ROOT/payment-audio" \
  "$SSD_ROOT/backups" \
  "$SSD_ROOT/caddy/data" \
  "$SSD_ROOT/caddy/config" \
  "$REMOTE_APP_DIR/releases" \
  "$REMOTE_APP_DIR/action-staging"

sudo chown -R "$(id -un):$GROUP_NAME" "$REMOTE_APP_DIR"
sudo chown -R "root:$GROUP_NAME" "$SSD_ROOT"
sudo chmod 775 "$SSD_ROOT" "$SSD_ROOT/downloads" "$SSD_ROOT/import" "$SSD_ROOT/backups"
sudo chown -R "$RUNTIME_UID:$RUNTIME_GID" \
  "$SSD_ROOT/uploads" \
  "$SSD_ROOT/private-media" \
  "$SSD_ROOT/payment-audio"
sudo chmod 755 "$SSD_ROOT/uploads"
sudo chmod 700 "$SSD_ROOT/private-media" "$SSD_ROOT/payment-audio"

if [[ ! -e "$ENV_FILE" ]]; then
  sudo install -m 0640 -o root -g "$GROUP_NAME" deploy/staging/env.example "$ENV_FILE"
  echo "Created staging env template: $ENV_FILE"
  echo "Replace placeholders before running the staging workflow."
elif [[ ! -s "$ENV_FILE" ]]; then
  sudo install -m 0640 -o root -g "$GROUP_NAME" deploy/staging/env.example "$ENV_FILE"
  echo "Replaced empty staging env with template: $ENV_FILE"
else
  echo "Staging env already exists; leaving it unchanged: $ENV_FILE"
fi

echo "Current UFW status:"
sudo ufw status verbose

if sudo ufw status | grep -Eq '^22/tcp[[:space:]]+ALLOW[[:space:]]+Anywhere'; then
  echo "Warning: public SSH is still open. Keep only '22/tcp on tailscale0' before staging deploy." >&2
fi

if sudo ufw status | grep -Eq '^(80|443)/tcp[[:space:]]+ALLOW'; then
  echo "Warning: public 80/443 is open. Staging is intended to use Cloudflare Tunnel to 127.0.0.1:8090." >&2
fi

echo "Bootstrap complete."
