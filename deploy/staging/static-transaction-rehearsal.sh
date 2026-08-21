#!/usr/bin/env bash
set -Eeuo pipefail

: "${CURRENT_DIR:?CURRENT_DIR is required}"

helper="$CURRENT_DIR/deploy/home-server/release-transaction.sh"
test -f "$helper"
source "$helper"

root="$(mktemp -d /tmp/opshub-static-transaction.XXXXXX)"
trap 'rm -rf -- "$root"' EXIT

mkdir -p \
  "$root/opshub/releases/old/deploy/home-server" \
  "$root/opshub/releases/old/docs/help/content" \
  "$root/opshub/downloads/help/assets" \
  "$root/opshub/downloads/help/content" \
  "$root/opshub/web" \
  "$root/input/help/assets" \
  "$root/input/help/content"
ln -s "$root/opshub/releases/old" "$root/opshub/current"
printf 'old caddy\n' > "$root/opshub/releases/old/deploy/home-server/Caddyfile"
printf '[{"key":"release-old","title":"Release old","file":"release-old.md"}]\n' > "$root/opshub/releases/old/docs/help/navigation.json"
printf 'old immutable runtime help\n' > "$root/opshub/releases/old/docs/help/content/release-old.md"
printf 'old help\n' > "$root/opshub/downloads/help/assets/old.md"
printf '[{"key":"old","title":"Old","file":"old.md"}]\n' > "$root/opshub/downloads/help/navigation.json"
printf 'old shared Help sentinel\n' > "$root/opshub/downloads/help/content/old.md"
printf 'old index\n' > "$root/opshub/web/index.html"
printf 'old manifest\n' > "$root/opshub/downloads/latest.json"
printf 'old page\n' > "$root/opshub/downloads/download.html"
printf 'old icon\n' > "$root/opshub/downloads/opshub-icon-192.png"
printf 'old env\n' > "$root/opshub.env"
printf 'new manifest\n' > "$root/input/latest.json"
printf 'new page\n' > "$root/input/download.html"
printf 'new icon\n' > "$root/input/opshub-icon-192.png"
printf 'new help\n' > "$root/input/help/assets/new.md"
printf '[{"key":"new","title":"New","file":"new.md"}]\n' > "$root/input/help/navigation.json"
printf 'new shared Help sentinel\n' > "$root/input/help/content/new.md"
tar -C "$root/input/help" -czf "$root/input/docs-help.tar.gz" .

export OPSHUB_SUDO=''
export OPSHUB_ENV_FILE="$root/opshub.env"
export OPSHUB_SSD_ROOT="$root/opshub"
export OPSHUB_REMOTE_APP_DIR="$root/opshub"
export CURRENT_DIR="$root/opshub/current"
export REMOTE_RELEASE_DIR="$root/opshub/current"
export DEPLOY_RUN_ID=900001
export DEPLOY_RUN_ATTEMPT=1
export DOWNLOADS_DIR="$root/opshub/downloads"
export WEB_DIR="$root/opshub/web"
export TXN_INPUT_DIR="$root/input"
export OPSHUB_TXN_STATIC_ONLY=true
release_hash_before="$(find "$CURRENT_DIR" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}')"

opshub_txn_begin
opshub_txn_promote_static
opshub_txn_require_promoted
grep -Fxq 'new help' "$DOWNLOADS_DIR/help/assets/new.md"
grep -Fxq 'new shared Help sentinel' "$DOWNLOADS_DIR/help/content/new.md"
grep -Fq '"key":"new"' "$DOWNLOADS_DIR/help/navigation.json"
grep -Fxq 'new manifest' "$DOWNLOADS_DIR/latest.json"
test "$(find "$CURRENT_DIR" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}')" = "$release_hash_before"
grep -Fxq 'old immutable runtime help' "$CURRENT_DIR/docs/help/content/release-old.md"

opshub_txn_restore_shared
grep -Fxq 'old caddy' "$CURRENT_DIR/deploy/home-server/Caddyfile"
grep -Fxq 'old immutable runtime help' "$CURRENT_DIR/docs/help/content/release-old.md"
grep -Fxq 'old help' "$DOWNLOADS_DIR/help/assets/old.md"
grep -Fxq 'old shared Help sentinel' "$DOWNLOADS_DIR/help/content/old.md"
grep -Fq '"key":"old"' "$DOWNLOADS_DIR/help/navigation.json"
grep -Fxq 'old manifest' "$DOWNLOADS_DIR/latest.json"
test ! -e "$DOWNLOADS_DIR/help/content/new.md"
test "$(find "$CURRENT_DIR" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}')" = "$release_hash_before"
opshub_txn_cleanup
test ! -e "$OPSHUB_TXN_STATE"

echo 'STATIC TRANSACTION REHEARSAL PASS'
