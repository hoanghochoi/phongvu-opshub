#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -ne 4 ]; then
  echo 'Usage: rollback-runtime.sh <target-release> <target-env> <live-env> <current-link>' >&2
  exit 64
fi

target_release="$(readlink -f "$1")"
target_env="$2"
live_env="$3"
current_link="$4"
compose_project='home-server'
pre_release="$(readlink -f "$current_link" || true)"
pre_env="$(mktemp)"
phase='initial'
finished=false
recovering=false

privileged() { if [ -n "${OPSHUB_SUDO-sudo}" ]; then "${OPSHUB_SUDO-sudo}" "$@"; else "$@"; fi; }
log_failure() { echo "Runtime rollback: $*" >&2; return 1; }
cleanup() { privileged rm -f -- "$pre_env"; }

[ -d "$target_release" ] || { cleanup; log_failure 'target release is unavailable'; exit 1; }
[ -d "$pre_release" ] || { cleanup; log_failure 'pre-attempt release is unavailable'; exit 1; }
privileged test -s "$target_env" || { cleanup; log_failure 'prepared target env is unavailable'; exit 1; }
privileged test -s "$live_env" || { cleanup; log_failure 'live env is unavailable'; exit 1; }
rm -f -- "$pre_env"
privileged cp --preserve=mode,ownership,timestamps -- "$live_env" "$pre_env"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$script_dir/verify-release-manifest.sh" "$target_release" >/dev/null || {
  cleanup; log_failure 'target release manifest verification failed'; exit 1;
}

compose_for() {
  local release="$1" env_file="$2"
  shift 2
  docker compose --project-name "$compose_project" --env-file "$env_file" \
    -f "$release/deploy/home-server/docker-compose.home.yml" "$@" < /dev/null
}
env_value() { privileged sed -n "s/^${2}=//p" "$1" | tail -n 1; }
verify_release_health() {
  local env_file="$1" host
  host="$(env_value "$env_file" OPSHUB_DOMAIN)"
  [ -n "$host" ] && curl -fsS -H "Host: $host" -H 'X-Forwarded-Proto: https' \
    'http://127.0.0.1:8090/health' >/dev/null
}
install_env_and_pointer() {
  local env_file="$1" release="$2"
  local env_stage="${live_env}.runtime-rollback" link_stage="${current_link}.runtime-rollback"
  privileged cp --preserve=mode,ownership,timestamps -- "$env_file" "$env_stage"
  privileged mv -Tf -- "$env_stage" "$live_env"
  ln -sfn "$release" "$link_stage"
  mv -Tf "$link_stage" "$current_link"
}
state_matches() {
  local release="$1" env_file="$2"
  [ "$(readlink -f "$current_link" || true)" = "$release" ] &&
    privileged cmp -s "$env_file" "$live_env" &&
    verify_release_health "$env_file"
}

commit_target() {
  phase='target-commit'
  install_env_and_pointer "$target_env" "$target_release" && state_matches "$target_release" "$target_env"
}

recover_coherent_state() {
  [ "$recovering" = false ] || return 1
  recovering=true
  trap - ERR INT TERM HUP EXIT
  echo "Runtime rollback interrupted or failed during phase=$phase; reconciling one complete state." >&2

  # The exact checkpoint target is primary authority. Retry it even when the
  # mutable pre-attempt env cannot parse (the live incident state may already
  # be split between an old pointer and a new env).
  if compose_for "$target_release" "$target_env" config >/dev/null &&
     compose_for "$target_release" "$target_env" up -d --build --force-recreate --wait --wait-timeout 240 redis api realtime caddy &&
     verify_release_health "$target_env" && commit_target; then
    echo 'Failure recovery converged on the exact target release.' >&2
    return 0
  fi

  # The pre-attempt state is only a fallback when its mutable env is parseable.
  if compose_for "$pre_release" "$pre_env" config >/dev/null 2>&1 &&
     compose_for "$pre_release" "$pre_env" up -d --build --force-recreate --wait --wait-timeout 240 redis api realtime caddy &&
     verify_release_health "$pre_env" &&
     install_env_and_pointer "$pre_env" "$pre_release" &&
     state_matches "$pre_release" "$pre_env"; then
    echo 'Failure recovery converged on the complete pre-attempt release.' >&2
    return 0
  fi
  echo 'Unable to prove either a complete target or pre-attempt runtime; protected evidence retained.' >&2
  return 1
}

on_signal() {
  local signal="$1" status="$2"
  echo "Runtime rollback received $signal during phase=$phase." >&2
  exit "$status"
}
on_exit() {
  local status="$1"
  trap - EXIT
  if [ "$status" -ne 0 ] && [ "$finished" = false ]; then
    recover_coherent_state || status=1
  fi
  cleanup
  exit "$status"
}
trap 'on_signal INT 130' INT
trap 'on_signal TERM 143' TERM
trap 'on_signal HUP 129' HUP
trap 'on_exit $?' EXIT

phase='target-preflight'
compose_for "$target_release" "$target_env" config >/dev/null || exit 1
phase='target-recreate'
compose_for "$target_release" "$target_env" up -d --build --force-recreate --wait --wait-timeout 240 redis api realtime caddy || exit 1
phase='target-health'
verify_release_health "$target_env" || exit 1
phase='target-commit'
commit_target || exit 1
phase='complete'
finished=true
echo 'Target release, env and home-server containers are coherent.'
