#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$root/deploy/home-server/release-transaction.sh"

temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT

mkdir -p "$temp/opshub/releases/old/deploy/home-server" \
  "$temp/opshub/releases/new/deploy/home-server" \
  "$temp/opshub/downloads/help/assets" "$temp/opshub/web" \
  "$temp/input/web" "$temp/input/help/assets" "$temp/input/android" "$temp/input/windows"
printf 'old runtime\n' > "$temp/opshub/releases/old/deploy/home-server/Caddyfile"
printf 'new runtime\n' > "$temp/opshub/releases/new/deploy/home-server/Caddyfile"
printf 'old index\n' > "$temp/opshub/web/index.html"
printf 'old help\n' > "$temp/opshub/downloads/help/assets/old.md"
printf 'old manifest\n' > "$temp/opshub/downloads/latest.json"
printf 'old page\n' > "$temp/opshub/downloads/download.html"
printf 'old icon\n' > "$temp/opshub/downloads/opshub-icon-192.png"
printf 'old env\n' > "$temp/opshub.env"
ln -s "$temp/opshub/releases/old" "$temp/opshub/current"

printf 'new index\n' > "$temp/input/web/index.html"
printf 'new help\n' > "$temp/input/help/assets/new.md"
printf 'new manifest\n' > "$temp/input/latest.json"
printf 'new page\n' > "$temp/input/download.html"
printf 'new icon\n' > "$temp/input/opshub-icon-192.png"
printf 'apk\n' > "$temp/input/android/app.apk"
printf 'zip\n' > "$temp/input/windows/app.zip"
printf 'installer\n' > "$temp/input/windows/app.exe"
printf 'checksum\n' > "$temp/input/windows/app.sha256"
tar -C "$temp/input/web" -czf "$temp/input/web.tar.gz" .
tar -C "$temp/input/help" -czf "$temp/input/help-assets.tar.gz" .

export OPSHUB_SUDO=''
export OPSHUB_ENV_FILE="$temp/opshub.env"
export OPSHUB_SSD_ROOT="$temp/opshub"
export OPSHUB_REMOTE_APP_DIR="$temp/opshub"
export CURRENT_DIR="$temp/opshub/current"
export REMOTE_RELEASE_DIR="$temp/opshub/releases/new"
export DEPLOY_RUN_ID=101
export DEPLOY_RUN_ATTEMPT=1
export DOWNLOADS_DIR="$temp/opshub/downloads"
export WEB_DIR="$temp/opshub/web"
export TXN_INPUT_DIR="$temp/input"
export TXN_CLIENT_DIR="$temp/input"
export APK_NAME=app.apk WINDOWS_ZIP_NAME=app.zip WINDOWS_INSTALLER_NAME=app.exe WINDOWS_CHECKSUM_NAME=app.sha256

opshub_txn_begin
test "$(opshub_txn_previous_release)" = "$temp/opshub/releases/old"
test "$(opshub_txn_candidate_release)" = "$temp/opshub/releases/new"
test "$OPSHUB_TXN_ID" = '101-1'
opshub_txn_stage_shared
opshub_txn_require_promoted
grep -Fxq 'new manifest' "$DOWNLOADS_DIR/latest.json"
grep -Fxq 'new index' "$WEB_DIR/index.html"
test -e "$OPSHUB_TXN_SHARED_SNAPSHOT/SNAPSHOT_READY"
printf 'new env\n' > "$OPSHUB_ENV_FILE"
opshub_txn_restore_env
opshub_txn_restore_shared
grep -Fxq 'old env' "$OPSHUB_ENV_FILE"
grep -Fxq 'old manifest' "$DOWNLOADS_DIR/latest.json"
grep -Fxq 'old index' "$WEB_DIR/index.html"
opshub_txn_cleanup
test ! -e "$OPSHUB_TXN_STATE"

# A failed restore retains the checkpoint instead of cleaning evidence.
export DEPLOY_RUN_ID=102
export DEPLOY_RUN_ATTEMPT=2
opshub_txn_begin
rm -f "$OPSHUB_TXN_ENV_SNAPSHOT"
if opshub_txn_restore_env; then
  echo 'restore unexpectedly succeeded without env snapshot' >&2
  exit 1
fi
test -e "$OPSHUB_TXN_STATE"
opshub_txn_cleanup

# A partial shared restore reports failure, preserves evidence, and can resume.
export DEPLOY_RUN_ID=104
export DEPLOY_RUN_ATTEMPT=1
opshub_txn_begin
opshub_txn_stage_shared
opshub_test_sudo() {
  if [[ "$1" = cp && " $* " = *" $OPSHUB_TXN_SHARED_SNAPSHOT/web "* ]]; then
    return 23
  fi
  command "$@"
}
export OPSHUB_SUDO=opshub_test_sudo
if opshub_txn_restore_shared; then
  echo 'shared restore unexpectedly succeeded after injected copy failure' >&2
  exit 1
fi
test -e "$OPSHUB_TXN_STATE"
export OPSHUB_SUDO=''
opshub_txn_restore_shared
grep -Fxq 'old index' "$WEB_DIR/index.html"
opshub_txn_cleanup

# Static-only transaction snapshots current Caddy/Help and shared download files.
export DEPLOY_RUN_ID=103
export DEPLOY_RUN_ATTEMPT=3
export REMOTE_RELEASE_DIR="$CURRENT_DIR"
export OPSHUB_TXN_STATIC_ONLY=true
mkdir -p "$temp/input-static/help/assets"
printf 'static manifest\n' > "$temp/input-static/latest.json"
printf 'static page\n' > "$temp/input-static/download.html"
printf 'static icon\n' > "$temp/input-static/opshub-icon-192.png"
printf 'static caddy\n' > "$temp/input-static/Caddyfile"
printf 'static help\n' > "$temp/input-static/help/assets/static.md"
tar -C "$temp/input-static/help" -czf "$temp/input-static/docs-help.tar.gz" .
export TXN_INPUT_DIR="$temp/input-static"
opshub_txn_begin
opshub_txn_promote_static
opshub_txn_require_promoted
grep -Fxq 'static manifest' "$DOWNLOADS_DIR/latest.json"
grep -Fxq 'static caddy' "$CURRENT_DIR/deploy/home-server/Caddyfile"
grep -Fxq 'static help' "$CURRENT_DIR/docs/help/assets/static.md"
grep -Fxq 'static help' "$DOWNLOADS_DIR/help/assets/static.md"
opshub_txn_restore_shared
opshub_txn_restore_static_current
grep -Fxq 'old manifest' "$DOWNLOADS_DIR/latest.json"
grep -Fxq 'old runtime' "$CURRENT_DIR/deploy/home-server/Caddyfile"
grep -Fxq 'old help' "$DOWNLOADS_DIR/help/assets/old.md"
test ! -e "$CURRENT_DIR/docs/help/assets/static.md"
opshub_txn_cleanup

workflow="$root/.github/workflows/deploy-opshub.yml"
grep -Fq 'action-staging/${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}' "$workflow"
! grep -Fq 'action-staging/${GITHUB_RUN_ID}/' "$workflow"
grep -Fq "DEPLOY_RUN_ATTEMPT='\$GITHUB_RUN_ATTEMPT'" "$workflow"
grep -Fq 'source "$TMP_DIR/release-transaction.sh"' "$workflow"

verify_full_line=$(grep -n 'name: Verify public health and version metadata' "$workflow" | cut -d: -f1)
rollback_full_line=$(grep -n 'name: Roll back production after failed release verification' "$workflow" | cut -d: -f1)
finalize_full_line=$(grep -n 'name: Finalize successful production release checkpoint' "$workflow" | cut -d: -f1)
verify_static_line=$(grep -n 'name: Verify static download deploy' "$workflow" | cut -d: -f1)
rollback_static_line=$(grep -n 'name: Roll back static-only publication after failed verification' "$workflow" | cut -d: -f1)
finalize_static_line=$(grep -n 'name: Finalize successful static-only publication checkpoint' "$workflow" | cut -d: -f1)
full_trap_line=$(grep -n "trap 'rollback_on_error" "$workflow" | cut -d: -f1)
full_promote_line=$(grep -n 'opshub_txn_stage_shared' "$workflow" | cut -d: -f1)
static_trap_line=$(grep -n "trap 'rollback_static" "$workflow" | cut -d: -f1)
static_promote_line=$(grep -n 'opshub_txn_promote_static' "$workflow" | cut -d: -f1)
mapfile -t cleanup_lines < <(grep -n 'opshub_txn_cleanup' "$workflow" | cut -d: -f1)
test "$verify_full_line" -lt "$rollback_full_line"
test "$rollback_full_line" -lt "$finalize_full_line"
test "$verify_static_line" -lt "$rollback_static_line"
test "$rollback_static_line" -lt "$finalize_static_line"
test "$full_trap_line" -lt "$full_promote_line"
test "$static_trap_line" -lt "$static_promote_line"
test "${#cleanup_lines[@]}" -eq 2
test "$finalize_full_line" -lt "${cleanup_lines[0]}"
test "$finalize_static_line" -lt "${cleanup_lines[1]}"

echo 'release transaction snapshot, fail-closed retention, and static rollback contract passed'
