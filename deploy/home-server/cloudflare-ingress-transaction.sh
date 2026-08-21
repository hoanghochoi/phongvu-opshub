#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -ne 3 ]; then
  echo 'Usage: cloudflare-ingress-transaction.sh <activate|restore|finalize> <config> <snapshot>' >&2
  exit 64
fi

action="$1" config="$2" snapshot="$3"
sidecar="${snapshot}.hashes"
lock_file="${config}.opshub.lock"
cloudflared_bin="${CLOUDFLARED_BIN:-cloudflared}"
systemctl_bin="${SYSTEMCTL_BIN:-systemctl}"
web_host='phongvu.work' api_host='api.phongvu.work' origin_service='http://localhost:8090'
candidate='' installed=false finished=false

privileged() { if [ -n "${OPSHUB_SUDO-sudo}" ]; then "${OPSHUB_SUDO-sudo}" "$@"; else "$@"; fi; }
die() { echo "Cloudflare ingress transaction: $*" >&2; exit 1; }
hash_file() { sha256sum "$1" | awk '{print $1}'; }
read_sidecar() {
  baseline_hash="$(privileged sed -n '1p' "$sidecar")"
  rendered_hash="$(privileged sed -n '2p' "$sidecar")"
  pair_ownership="$(privileged sed -n '3p' "$sidecar")"
  case "$pair_ownership" in inserted|preexisting) ;; *) return 1 ;; esac
}

exec 9>"$lock_file"
flock -n 9 || die 'another Cloudflare ingress transaction holds the exclusive lock'

validate_structure() {
  local file="$1"
  awk -v web="$web_host" -v api="$api_host" -v service="$origin_service" '
    function fail(message) { failed=1; print message > "/dev/stderr"; exit 1 }
    /^[^[:space:]#][^:]*:[[:space:]]*$/ && $0 == "ingress:" { ingress_count++; in_ingress=1; next }
    in_ingress && catchall_count > 0 && /^  - / { fail("ingress route appears after final catch-all") }
    in_ingress && (index($0, web) > 0 || index($0, api) > 0) && \
      $0 != "  - hostname: " web && $0 != "  - hostname: " api { fail("production hostname uses unsupported syntax") }
    in_ingress && /^  - hostname: / {
      hostname=substr($0, length("  - hostname: ") + 1)
      if (hostname == "" || seen[hostname]++) fail("duplicate or empty hostname")
      pending=hostname
      if (hostname == "staging.phongvu.work" || hostname == "api-staging.phongvu.work") fail("cross-environment hostname")
      next
    }
    in_ingress && pending != "" && /^    service: / {
      route_service=substr($0, length("    service: ") + 1)
      if ((pending == web || pending == api) && route_service != service) fail("production hostname has wrong service")
      if (pending == web) web_count++; if (pending == api) api_count++; pending=""; next
    }
    in_ingress && /^  - service: http_status:404[[:space:]]*$/ {
      if (pending != "") fail("hostname is missing service")
      catchall_count++; next
    }
    in_ingress && /^[^[:space:]#]/ { in_ingress=0 }
    END {
      if (failed) exit 1
      if (pending != "") fail("hostname is missing service")
      if (ingress_count != 1 || catchall_count != 1) fail("expected one ingress and one final 404 catch-all")
      if ((web_count == 0) != (api_count == 0)) fail("production host pair is incomplete")
      if (web_count > 1 || api_count > 1) fail("production host pair is duplicated")
      if (web_count == 1 && api_count == 1) exit 0
      exit 2
    }
  ' "$file"
}
validate_cloudflared() { "$cloudflared_bin" --config "$1" tunnel ingress validate >/dev/null; }
restart_active() { privileged "$systemctl_bin" restart cloudflared.service && privileged "$systemctl_bin" is-active --quiet cloudflared.service; }
atomic_install() {
  local source="$1" stage="${config}.opshub-cutover"
  privileged install -m 0600 "$source" "$stage"
  privileged mv -Tf -- "$stage" "$config"
}
remove_owned_rules() {
  local source="$1" target="$2"
  python3 - "$source" "$target" "$web_host" "$api_host" "$origin_service" <<'PY'
import pathlib, sys

source, target = map(pathlib.Path, sys.argv[1:3])
web, api, service = sys.argv[3:]
data = source.read_bytes()
for host in (web, api):
    block = f'  - hostname: {host}\n    service: {service}\n'.encode('utf-8')
    if data.count(block) != 1:
        raise SystemExit(f'owned Tunnel rule changed or is not an exact two-line rule: {host}')
    data = data.replace(block, b'', 1)
target.write_bytes(data)
PY
}

restore_cas() {
  privileged test -s "$snapshot" && privileged test -s "$sidecar" || return 1
  local live_hash restore_candidate structure_status surgical_candidate installed_hash
  read_sidecar || return 1
  restore_candidate="$(mktemp)"
  privileged cat "$snapshot" > "$restore_candidate"
  [ "$(hash_file "$restore_candidate")" = "$baseline_hash" ] || { rm -f "$restore_candidate"; return 1; }
  validate_cloudflared "$restore_candidate" || { rm -f "$restore_candidate"; return 1; }
  live_hash="$(privileged sha256sum "$config" | awk '{print $1}')"
  if [ "$live_hash" = "$baseline_hash" ]; then
    rm -f "$restore_candidate"
    [ "$(privileged sha256sum "$config" | awk '{print $1}')" = "$live_hash" ] || return 1
    restart_active
    return
  fi
  privileged cat "$config" > "$restore_candidate"
  structure_status=0
  validate_structure "$restore_candidate" >/dev/null || structure_status=$?
  if [ "$structure_status" -eq 2 ]; then
    [ "$pair_ownership" = inserted ] || {
      echo 'Pre-existing production Tunnel rules disappeared; refusing restore.' >&2
      rm -f "$restore_candidate"
      return 1
    }
    validate_cloudflared "$restore_candidate" || { rm -f "$restore_candidate"; return 1; }
    rm -f "$restore_candidate"
    [ "$(privileged sha256sum "$config" | awk '{print $1}')" = "$live_hash" ] || return 1
    restart_active
    return
  fi
  [ "$structure_status" -eq 0 ] || {
    echo 'Owned production Tunnel rules changed; refusing surgical restore.' >&2
    rm -f "$restore_candidate"
    return 1
  }
  if [ "$pair_ownership" = preexisting ]; then
    validate_cloudflared "$restore_candidate" || { rm -f "$restore_candidate"; return 1; }
    rm -f "$restore_candidate"
    [ "$(privileged sha256sum "$config" | awk '{print $1}')" = "$live_hash" ] || {
      echo 'Live Tunnel config changed during pre-existing route validation; refusing restart.' >&2
      return 1
    }
    restart_active
    return
  fi
  surgical_candidate="$(mktemp)"
  remove_owned_rules "$restore_candidate" "$surgical_candidate" || {
    rm -f "$restore_candidate" "$surgical_candidate"
    return 1
  }
  rm -f "$restore_candidate"
  restore_candidate="$surgical_candidate"
  structure_status=0
  validate_structure "$restore_candidate" >/dev/null || structure_status=$?
  [ "$structure_status" -eq 2 ] || { rm -f "$restore_candidate"; return 1; }
  validate_cloudflared "$restore_candidate" || { rm -f "$restore_candidate"; return 1; }
  [ "$(privileged sha256sum "$config" | awk '{print $1}')" = "$live_hash" ] || {
    echo 'Live Tunnel config changed during restore validation; refusing overwrite.' >&2
    rm -f "$restore_candidate"
    return 1
  }
  atomic_install "$restore_candidate" || { rm -f "$restore_candidate"; return 1; }
  installed_hash="$(hash_file "$restore_candidate")"
  rm -f "$restore_candidate"
  [ "$(privileged sha256sum "$config" | awk '{print $1}')" = "$installed_hash" ] || return 1
  restart_active
}

on_signal() { echo "Cloudflare ingress transaction received $1." >&2; exit "$2"; }
on_exit() {
  local status="$1"
  trap - EXIT
  if [ "$status" -ne 0 ] && [ "$installed" = true ] && [ "$finished" = false ]; then
    restore_cas || echo 'Automatic Tunnel restore could not pass CAS; checkpoint retained.' >&2
  fi
  [ -z "$candidate" ] || rm -f -- "$candidate"
  exit "$status"
}
trap 'on_signal INT 130' INT
trap 'on_signal TERM 143' TERM
trap 'on_signal HUP 129' HUP
trap 'on_exit $?' EXIT

case "$action" in
  activate)
    privileged test -s "$config" || die 'Tunnel config is unavailable'
    candidate="$(mktemp)"; privileged cat "$config" > "$candidate"
    status=0; validate_structure "$candidate" || status=$?
    case "$status" in
      0)
        live_hash="$(hash_file "$candidate")"
        if privileged test -s "$sidecar"; then read_sidecar || die 'Tunnel transaction sidecar is malformed'; [ "$live_hash" = "$rendered_hash" ] || die 'active config differs from transaction rendered hash';
        else
          privileged cp --preserve=mode,ownership,timestamps -- "$config" "$snapshot"
          printf '%s\n%s\n%s\n' "$live_hash" "$live_hash" preexisting | privileged tee "$sidecar" >/dev/null
        fi
        validate_cloudflared "$candidate" || die 'active Tunnel config failed validation'
        [ "$(privileged sha256sum "$config" | awk '{print $1}')" = "$live_hash" ] || die 'live Tunnel config changed during active validation'
        installed=true
        restart_active || die 'active Tunnel config failed restart'
        ;;
      2)
        live_baseline_hash="$(hash_file "$candidate")"
        if privileged test -e "$sidecar"; then read_sidecar || die 'Tunnel transaction sidecar is malformed'; [ "$pair_ownership" = inserted ] || die 'pre-existing production routes disappeared during activation'; [ "$live_baseline_hash" = "$baseline_hash" ] || die 'inactive config differs from transaction baseline';
        else privileged cp --preserve=mode,ownership,timestamps -- "$config" "$snapshot"; fi
        rendered="$(mktemp)"
        awk -v web="$web_host" -v api="$api_host" -v service="$origin_service" '
          /^  - service: http_status:404[[:space:]]*$/ { print "  - hostname: " web; print "    service: " service; print "  - hostname: " api; print "    service: " service }
          { print }
        ' "$candidate" > "$rendered"; mv -f "$rendered" "$candidate"
        validate_structure "$candidate" >/dev/null || die 'rendered config failed structural validation'
        baseline_hash="$live_baseline_hash"; rendered_hash="$(hash_file "$candidate")"
        printf '%s\n%s\n%s\n' "$baseline_hash" "$rendered_hash" inserted | privileged tee "$sidecar" >/dev/null
        validate_cloudflared "$candidate" || die 'rendered config failed cloudflared validation'
        [ "$(privileged sha256sum "$config" | awk '{print $1}')" = "$baseline_hash" ] || die 'live Tunnel config changed during validation; refusing activation'
        installed=true
        atomic_install "$candidate"
        [ "$(privileged sha256sum "$config" | awk '{print $1}')" = "$rendered_hash" ] || die 'installed Tunnel config changed before restart'
        restart_active || die 'cloudflared did not become active'
        ;;
      *) die 'Tunnel config is malformed or unsafe' ;;
    esac
    finished=true; echo 'Production Tunnel ingress activated.'
    ;;
  restore)
    restore_cas || die 'Tunnel restore failed CAS, validation, or service health'
    finished=true; echo 'Production Tunnel ingress restored from the transaction snapshot.'
    ;;
  finalize)
    if ! privileged test -s "$sidecar"; then
      candidate="$(mktemp)"; privileged cat "$config" > "$candidate"
      validate_structure "$candidate" >/dev/null && validate_cloudflared "$candidate" || die 'finalized Tunnel config is invalid'
      finished=true; echo 'Production Tunnel ingress checkpoint already finalized.'; exit 0
    fi
    read_sidecar
    live_hash="$(privileged sha256sum "$config" | awk '{print $1}')"
    [ "$live_hash" = "$rendered_hash" ] || die 'live Tunnel config changed after activation; refusing finalize'
    candidate="$(mktemp)"; privileged cat "$config" > "$candidate"
    validate_structure "$candidate" >/dev/null && validate_cloudflared "$candidate" || die 'active Tunnel config is invalid'
    [ "$(privileged sha256sum "$config" | awk '{print $1}')" = "$rendered_hash" ] ||
      die 'live Tunnel config changed during finalize validation; retaining checkpoint'
    privileged rm -f -- "$snapshot" "$sidecar"
    finished=true; echo 'Production Tunnel ingress checkpoint finalized.'
    ;;
  *) die 'unsupported action' ;;
esac
