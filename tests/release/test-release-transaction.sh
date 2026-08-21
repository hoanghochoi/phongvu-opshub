#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$root/deploy/home-server/release-transaction.sh"

temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT

# Git Bash on Windows exposes POSIX commands over NTFS but does not reliably
# preserve Unix mode/ownership bits. Keep the fixture semantic-only there;
# Linux CI still exercises the real permission-preserving commands.
if [[ "$(uname -s)" == MINGW* ]]; then
  opshub_test_sudo() {
    local command_name="$1"
    shift
    case "$command_name" in
      install)
        local -a args=()
        local skip_next=false arg
        for arg in "$@"; do
          if [[ "$skip_next" == true ]]; then
            skip_next=false
            continue
          fi
          if [[ "$arg" == -m ]]; then
            skip_next=true
            continue
          fi
          args+=("$arg")
        done
        command install "${args[@]}"
        ;;
      chmod)
        return 0
        ;;
      cp)
        local -a args=()
        for arg in "$@"; do
          [[ "$arg" == --preserve=* ]] || args+=("$arg")
        done
        command cp "${args[@]}"
        ;;
      *)
        command "$command_name" "$@"
        ;;
    esac
  }
  export OPSHUB_SUDO=opshub_test_sudo
else
  export OPSHUB_SUDO=''
fi

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

export OPSHUB_ENV_FILE="$temp/opshub.env"
export OPSHUB_SSD_ROOT="$temp/opshub"
export OPSHUB_REMOTE_APP_DIR="$temp/opshub"
export CURRENT_DIR="$temp/opshub/releases/old"
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
export INJECT_SHARED_RESTORE_FAILURE=true
opshub_txn_begin
opshub_txn_stage_shared
opshub_test_sudo() {
  if [[ "${INJECT_SHARED_RESTORE_FAILURE:-false}" = true && "$1" = cp && " $* " = *" $OPSHUB_TXN_SHARED_SNAPSHOT/web "* ]]; then
    return 23
  fi
  if [[ "$(uname -s)" == MINGW* && "$1" = cp ]]; then
    local -a args=()
    local arg
    for arg in "${@:2}"; do
      [[ "$arg" == --preserve=* ]] || args+=("$arg")
    done
    command cp "${args[@]}"
    return
  fi
  if [[ "$(uname -s)" == MINGW* && "$1" = install ]]; then
    local -a args=()
    local skip_next=false arg
    for arg in "${@:2}"; do
      if [[ "$skip_next" == true ]]; then
        skip_next=false
        continue
      fi
      if [[ "$arg" == -m ]]; then
        skip_next=true
        continue
      fi
      args+=("$arg")
    done
    command install "${args[@]}"
    return
  fi
  if [[ "$(uname -s)" == MINGW* && "$1" = chmod ]]; then
    return 0
  fi
  command "$@"
}
export OPSHUB_SUDO=opshub_test_sudo
if opshub_txn_restore_shared; then
  echo 'shared restore unexpectedly succeeded after injected copy failure' >&2
  exit 1
fi
test -e "$OPSHUB_TXN_STATE"
export INJECT_SHARED_RESTORE_FAILURE=false
if [[ "$(uname -s)" == MINGW* ]]; then
  export OPSHUB_SUDO=opshub_test_sudo
else
  export OPSHUB_SUDO=''
fi
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
grep -Fq 'action-staging/${GITHUB_RUN_ID}/' "$workflow"
! grep -Fq 'action-staging/${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}' "$workflow"
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

# The KEK bootstrap is called from an SSH `bash -s` heredoc by both deploy
# workflows. A nested Compose process that inherits stdin can drain every
# deployment command after the bootstrap while still exiting zero.
bootstrap_fixture="$temp/bootstrap-stdin"
bootstrap_mock_bin="$bootstrap_fixture/bin"
bootstrap_ssd_root="$bootstrap_fixture/ssd"
bootstrap_marker="$bootstrap_fixture/after-bootstrap"
mkdir -p "$bootstrap_mock_bin" "$bootstrap_ssd_root/secrets"
printf '%s\n' \
  "OPSHUB_SSD_ROOT=$bootstrap_ssd_root" \
  'OPSHUB_RUNTIME_GID=1000' \
  'POSTGRES_USER=opshub' \
  'POSTGRES_DB=opshub' > "$bootstrap_fixture/env"
: > "$bootstrap_fixture/compose.yml"
printf '%s\n' 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' \
  > "$bootstrap_ssd_root/secrets/bidv-h2h-kek"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'while IFS= read -r _; do :; done' \
  'case " $* " in' \
  '  *" exec -T postgres "*) printf "1\\n" ;;' \
  '  *" --profile maintenance run "*) printf "BIDV KEK preflight passed protectedKeyCount=1\\n" ;;' \
  '  *) echo "Unexpected mocked docker invocation: $*" >&2; exit 64 ;;' \
  'esac' > "$bootstrap_mock_bin/docker"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'command_name="$1"' \
  'shift' \
  'case "$command_name" in' \
  '  install)' \
  '    args=()' \
  '    while (($#)); do' \
  '      case "$1" in' \
  '        -m|-o|-g) shift 2 ;;' \
  '        *) args+=("$1"); shift ;;' \
  '      esac' \
  '    done' \
  '    command install "${args[@]}"' \
  '    ;;' \
  '  chown|chmod) exit 0 ;;' \
  '  *) command "$command_name" "$@" ;;' \
  'esac' > "$bootstrap_mock_bin/sudo"
chmod +x "$bootstrap_mock_bin/docker" "$bootstrap_mock_bin/sudo"

unsafe_bootstrap="$bootstrap_fixture/bootstrap-with-inherited-stdin.sh"
sed 's/"\$@" < \/dev\/null/"\$@"/' \
  "$root/deploy/home-server/bootstrap-bidv-kek.sh" > "$unsafe_bootstrap"
chmod +x "$unsafe_bootstrap"
PATH="$bootstrap_mock_bin:$PATH" bash -s -- \
  "$unsafe_bootstrap" \
  "$bootstrap_fixture/env" \
  "$bootstrap_fixture/compose.yml" \
  "$bootstrap_marker" <<'REMOTE'
bash "$1" "$2" "$3"
printf 'unsafe-remote-transaction-continued\n' > "$4"
REMOTE
test ! -e "$bootstrap_marker"

PATH="$bootstrap_mock_bin:$PATH" bash -s -- \
  "$root/deploy/home-server/bootstrap-bidv-kek.sh" \
  "$bootstrap_fixture/env" \
  "$bootstrap_fixture/compose.yml" \
  "$bootstrap_marker" <<'REMOTE'
bash "$1" "$2" "$3"
printf 'remote-transaction-continued\n' > "$4"
REMOTE
grep -Fxq 'remote-transaction-continued' "$bootstrap_marker"

echo 'release transaction snapshot, stdin boundary, fail-closed retention, and static rollback contract passed'
