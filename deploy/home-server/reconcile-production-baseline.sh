#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -ne 7 ]; then
  echo 'Usage: reconcile-production-baseline.sh <previous-release> <rollback-env> <live-env> <current-link> <downloads> <web> <identity>' >&2
  exit 64
fi
previous="$1" rollback_env="$2" live_env="$3" current="$4" downloads="$5" web="$6" identity="$7"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/release-transaction.sh"
export OPSHUB_SUDO="${OPSHUB_SUDO-sudo}"
opshub_txn_load
phase='preflight'
historical_snapshot=''
finished=false

privileged() { if [ -n "$OPSHUB_SUDO" ]; then "$OPSHUB_SUDO" "$@"; else "$@"; fi; }

verify_behavior() {
  OPSHUB_SUDO="$OPSHUB_SUDO" bash "$script_dir/verify-production-baseline.sh" \
    "$previous" "$rollback_env" "$live_env" "$current" "$downloads" "$web"
}
identity_action() {
  privileged env OPSHUB_SUDO='' bash "$script_dir/production-runtime-identity.sh" "$1" \
    "$identity" "$previous" "$rollback_env" "$downloads" "$web" "$current"
}
restore_exact_historical_shared() {
  local active_snapshot="$OPSHUB_TXN_SHARED_SNAPSHOT" status=0
  OPSHUB_TXN_SHARED_SNAPSHOT="$historical_snapshot"
  opshub_txn_restore_shared || status=$?
  if [ "$status" -eq 0 ]; then
    opshub_txn_verify_shared_snapshot || status=$?
  fi
  OPSHUB_TXN_SHARED_SNAPSHOT="$active_snapshot"
  return "$status"
}
recover_historical_shared() {
  local attempt
  trap - ERR EXIT
  trap '' INT TERM HUP
  echo 'Historical shared restore was interrupted; converging to the exact checkpoint before exit.' >&2
  for attempt in 1 2 3; do
    if restore_exact_historical_shared; then
      echo 'Historical shared checkpoint recovery converged.' >&2
      return 0
    fi
    echo "Historical shared checkpoint recovery attempt $attempt failed." >&2
  done
  echo 'Historical shared checkpoint recovery could not prove a complete state.' >&2
  return 1
}
on_signal() {
  local signal="$1" status="$2"
  echo "Production baseline reconciliation received $signal during phase=$phase." >&2
  exit "$status"
}
on_exit() {
  local status="$1"
  trap - EXIT
  if [ "$status" -ne 0 ] && [ "$phase" = 'historical-shared-restore' ] && [ -n "$historical_snapshot" ]; then
    recover_historical_shared || status=1
  fi
  exit "$status"
}
trap 'on_signal INT 130' INT
trap 'on_signal TERM 143' TERM
trap 'on_signal HUP 129' HUP
trap 'on_exit $?' EXIT

if verify_behavior; then
  if identity_action verify; then
    finished=true
    trap - EXIT INT TERM HUP
    echo 'Existing production baseline is identity-bound and coherent.'
    exit 0
  fi

  phase='identity-refresh'
  echo 'Production behavior is coherent but retained runtime identity is stale; refreshing identity.' >&2
  identity_action write
  verify_behavior
  identity_action verify
  phase='complete'
  finished=true
  trap - EXIT INT TERM HUP
  echo 'Existing production baseline is coherent and retained runtime identity was refreshed.'
  exit 0
fi

echo 'Production baseline is split; requiring an exact previous-release shared checkpoint.' >&2
restored=false
mapfile -t states < <(privileged find "$OPSHUB_TXN_ROLLBACK_DIR" -maxdepth 1 -type f -name 'deploy-*.state' -printf '%T@ %p\n' | sort -rn | awk '{print $2}')
for state in "${states[@]}"; do
  [ "$state" != "$OPSHUB_TXN_STATE" ] || continue
  [ "$(privileged sed -n '1p' "$state")" = "$previous" ] || continue
  historical_snapshot="${state%.state}.shared"
  if privileged test -e "$historical_snapshot/SNAPSHOT_READY" && \
     privileged test -e "$historical_snapshot/PROMOTED"; then
    phase='historical-shared-restore'
    if ! restore_exact_historical_shared; then
      continue
    fi
    restored=true
    break
  fi
done
[ "$restored" = true ] || { echo 'No exact previous-release shared checkpoint is available.' >&2; exit 1; }

phase='runtime-rollback'
OPSHUB_SUDO="$OPSHUB_SUDO" bash "$script_dir/rollback-runtime.sh" "$previous" "$rollback_env" "$live_env" "$current"
phase='final-verification'
verify_behavior
identity_action write
verify_behavior
identity_action verify
phase='complete'
finished=true
trap - EXIT INT TERM HUP
echo 'Exact previous release baseline reconciled and identity-bound.'
