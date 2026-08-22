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
identity_candidate=''
finished=false

privileged() { if [ -n "$OPSHUB_SUDO" ]; then "$OPSHUB_SUDO" "$@"; else "$@"; fi; }

verify_behavior() {
  OPSHUB_SUDO="$OPSHUB_SUDO" bash "$script_dir/verify-production-baseline.sh" \
    "$previous" "$rollback_env" "$live_env" "$current" "$downloads" "$web"
}
identity_action() {
  local record="${2:-$identity}"
  privileged env OPSHUB_SUDO='' bash "$script_dir/production-runtime-identity.sh" "$1" \
    "$record" "$previous" "$rollback_env" "$downloads" "$web" "$current"
}
cleanup_identity_candidate() {
  if [ -n "$identity_candidate" ]; then
    privileged rm -f -- "$identity_candidate" "${identity_candidate}.next"
  fi
}
validate_safe_identity_refresh() {
  local retained="$1" candidate="$2"
  python3 - "$retained" "$candidate" <<'PY'
import json, pathlib, sys

retained_path, candidate_path = map(pathlib.Path, sys.argv[1:])
try:
    retained = json.loads(retained_path.read_text(encoding='utf-8'))
    candidate = json.loads(candidate_path.read_text(encoding='utf-8'))
except Exception as error:
    raise SystemExit(f'Retained identity refresh requires two valid records: {error}')

preserved = {
    'sourceCommit',
    'caddySha256',
    'webSha256',
    'manifestSha256',
    'helpSha256',
}
refreshable = {'envSha256', 'apiImageId', 'realtimeImageId'}
expected = preserved | refreshable
if set(retained) != expected or set(candidate) != expected:
    raise SystemExit('Retained identity refresh rejected an unexpected identity schema')
for key in sorted(preserved):
    if retained[key] != candidate[key]:
        raise SystemExit(f'Retained identity refresh rejected protected drift: {key}')
changed = sorted(key for key in refreshable if retained[key] != candidate[key])
if not changed:
    raise SystemExit('Retained identity refresh found no authorized stale field')
print(','.join(changed))
PY
}
require_preflight_only_identity_refresh() {
  local previous_real releases_dir state_previous state_candidate
  previous_real="$(readlink -f "$previous")"
  releases_dir="$(readlink -f "$(dirname "$previous_real")")"
  state_previous="$(readlink -f "$(opshub_txn_previous_release)" || true)"
  state_candidate="$(readlink -f "$(opshub_txn_candidate_release)" || true)"
  [ "$state_previous" = "$previous_real" ] || {
    echo 'Retained identity refresh is not authorized by a preflight-only transaction.' >&2
    return 1
  }
  case "$state_candidate" in
    "$releases_dir"/*) ;;
    *)
      echo 'Retained identity refresh candidate is outside the protected releases directory.' >&2
      return 1
      ;;
  esac
  privileged cmp -s "$OPSHUB_TXN_ENV_SNAPSHOT" "$rollback_env" || {
    echo 'Retained identity refresh env snapshot differs from the exact baseline.' >&2
    return 1
  }
  if privileged test -e "$OPSHUB_TXN_SHARED_SNAPSHOT" ||
     privileged test -e "$OPSHUB_TXN_SHARED_STAGE"; then
    echo 'Retained identity refresh rejected transaction-owned shared state.' >&2
    return 1
  fi
}
commit_identity_candidate() {
  privileged install -d -m 0700 "$(dirname "$identity")"
  privileged install -m 0600 "$identity_candidate" "${identity}.next"
  privileged mv -Tf "${identity}.next" "$identity"
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
  cleanup_identity_candidate
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
  identity_candidate="${identity}.candidate.${OPSHUB_TXN_ID}"
  cleanup_identity_candidate
  echo 'Production behavior is coherent but retained runtime identity is stale; validating bounded refresh.' >&2
  identity_action write "$identity_candidate" >/dev/null
  stale_fields="$(validate_safe_identity_refresh "$identity" "$identity_candidate")"
  retained_identity_sha="$(privileged sha256sum "$identity" | awk '{print $1}')"
  require_preflight_only_identity_refresh
  phase='identity-refresh-exact-recreate'
  OPSHUB_SUDO="$OPSHUB_SUDO" bash "$script_dir/rollback-runtime.sh" \
    "$previous" "$rollback_env" "$live_env" "$current"
  phase='identity-refresh-verify'
  verify_behavior
  if identity_action verify; then
    cleanup_identity_candidate
    identity_candidate=''
    phase='complete'
    finished=true
    trap - EXIT INT TERM HUP
    echo 'Exact previous-release recreate restored the retained runtime identity.'
    exit 0
  fi
  cleanup_identity_candidate
  identity_action write "$identity_candidate" >/dev/null
  stale_fields="$(validate_safe_identity_refresh "$identity" "$identity_candidate")"
  identity_action verify "$identity_candidate" >/dev/null
  require_preflight_only_identity_refresh
  [ "$(privileged sha256sum "$identity" | awk '{print $1}')" = "$retained_identity_sha" ] || {
    echo 'Retained runtime identity changed during bounded refresh.' >&2
    exit 1
  }
  commit_identity_candidate
  identity_action verify
  cleanup_identity_candidate
  identity_candidate=''
  phase='complete'
  finished=true
  trap - EXIT INT TERM HUP
  echo "Existing production baseline is coherent and retained runtime identity was refreshed: ${stale_fields}."
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
