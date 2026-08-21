#!/usr/bin/env bash

opshub_cloudflare_final_headers() {
  local headers_file="$1"
  awk '
    function keep_block() {
      if (in_block) {
        last_block = block
      }
    }
    /^HTTP\/[0-9.]+[[:space:]]+[0-9][0-9][0-9]/ {
      keep_block()
      block = $0 ORS
      in_block = 1
      next
    }
    in_block {
      block = block $0 ORS
      if ($0 ~ /^\r?$/) {
        last_block = block
        in_block = 0
      }
    }
    END {
      keep_block()
      printf "%s", last_block
    }
  ' "$headers_file"
}

opshub_cloudflare_header_value() {
  local header_name="$1"
  awk -v expected="${header_name,,}" '
    {
      line = $0
      sub(/\r$/, "", line)
      separator = index(line, ":")
      if (separator == 0) {
        next
      }
      name = tolower(substr(line, 1, separator - 1))
      if (name != expected) {
        next
      }
      value = substr(line, separator + 1)
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      found = value
    }
    END { print found }
  '
}

opshub_cloudflare_trace() {
  local final_headers="$1"
  local cf_ray edge_server
  cf_ray="$(printf '%s\n' "$final_headers" | opshub_cloudflare_header_value 'cf-ray')"
  edge_server="$(printf '%s\n' "$final_headers" | opshub_cloudflare_header_value 'server')"
  printf 'cfRay=%s server=%s' "${cf_ray:-missing}" "${edge_server:-missing}"
}

opshub_cloudflare_headers_valid() {
  local final_headers="$1"
  local cf_ray edge_server
  cf_ray="$(printf '%s\n' "$final_headers" | opshub_cloudflare_header_value 'cf-ray')"
  edge_server="$(printf '%s\n' "$final_headers" | opshub_cloudflare_header_value 'server')"
  [[ "${edge_server,,}" == 'cloudflare' ]] &&
    [[ "$cf_ray" =~ ^[[:alnum:]-]+$ ]]
}

opshub_cloudflare_effective_host() {
  local effective_url="$1"
  local authority host
  [[ "$effective_url" == https://* ]] || return 1
  authority="${effective_url#https://}"
  authority="${authority%%/*}"
  authority="${authority%%\?*}"
  authority="${authority%%#*}"
  if [[ "$authority" =~ ^([[:alnum:].-]+)(:443)?$ ]]; then
    host="${BASH_REMATCH[1]}"
  else
    return 1
  fi
  [[ -n "$host" ]] || return 1
  printf '%s\n' "${host,,}"
}

opshub_cloudflare_artifact_host_allowed() {
  local effective_host="$1"
  shift
  local allowed_host
  (($# > 0)) || return 1
  for allowed_host in "$@"; do
    if [[ "${allowed_host,,}" == "$effective_host" ]]; then
      return 0
    fi
  done
  return 1
}

opshub_cloudflare_public_body() {
  local url="$1"
  shift
  local -a allowed_hosts=("$@")
  local effective_host effective_url final_headers headers_file metadata response_file safe_url status
  headers_file="$(mktemp)"
  response_file="$(mktemp)"
  safe_url="${url%%\?*}"

  if ! metadata="$(curl -sS --connect-timeout 10 --max-time 30 \
    -D "$headers_file" -o "$response_file" \
    -w $'%{http_code}\t%{url_effective}' "$url")"; then
    rm -f "$headers_file" "$response_file"
    echo "Cloudflare public probe transport failed: ${safe_url}." >&2
    return 1
  fi

  IFS=$'\t' read -r status effective_url <<< "$metadata"
  final_headers="$(opshub_cloudflare_final_headers "$headers_file")"
  effective_host="$(opshub_cloudflare_effective_host "$effective_url" || true)"
  if [[ ! "$status" =~ ^2[0-9][0-9]$ ]] ||
     ! opshub_cloudflare_headers_valid "$final_headers" ||
     ! opshub_cloudflare_artifact_host_allowed "$effective_host" "${allowed_hosts[@]}"; then
    echo "Cloudflare public probe rejected HTTP ${status:-missing} ($(opshub_cloudflare_trace "$final_headers") finalHost=${effective_host:-invalid}): ${safe_url}." >&2
    rm -f "$headers_file" "$response_file"
    return 1
  fi

  cat "$response_file"
  rm -f "$headers_file" "$response_file"
}

opshub_cloudflare_public_artifact() {
  local url="$1"
  shift
  local -a allowed_hosts=("$@")
  local content_length effective_host effective_url final_headers headers_file metadata safe_url status
  headers_file="$(mktemp)"
  safe_url="${url%%\?*}"

  if ! metadata="$(curl -sSIL --connect-timeout 10 --max-time 30 \
    -D "$headers_file" -o /dev/null -w $'%{http_code}\t%{url_effective}' \
    --max-redirs 5 "$url")"; then
    rm -f "$headers_file"
    echo "Cloudflare artifact probe transport failed: ${safe_url}." >&2
    return 1
  fi

  IFS=$'\t' read -r status effective_url <<< "$metadata"
  final_headers="$(opshub_cloudflare_final_headers "$headers_file")"
  effective_host="$(opshub_cloudflare_effective_host "$effective_url" || true)"
  content_length="$(printf '%s\n' "$final_headers" | opshub_cloudflare_header_value 'content-length')"

  if [[ ! "$status" =~ ^2[0-9][0-9]$ ]] ||
     ! opshub_cloudflare_headers_valid "$final_headers" ||
     ! opshub_cloudflare_artifact_host_allowed "$effective_host" "${allowed_hosts[@]}" ||
     [[ ! "$content_length" =~ ^[1-9][0-9]*$ ]]; then
    echo "Cloudflare artifact probe rejected HTTP ${status:-missing} ($(opshub_cloudflare_trace "$final_headers") finalHost=${effective_host:-invalid} contentLength=${content_length:-missing}): ${safe_url}." >&2
    rm -f "$headers_file"
    return 1
  fi

  rm -f "$headers_file"
}

opshub_api_node() {
  : "${OPSHUB_COMPOSE_PROJECT:?OPSHUB_COMPOSE_PROJECT is required}"
  : "${OPSHUB_ENV_FILE:?OPSHUB_ENV_FILE is required}"
  : "${CURRENT_DIR:?CURRENT_DIR is required}"
  docker compose --project-name "$OPSHUB_COMPOSE_PROJECT" \
    --env-file "$OPSHUB_ENV_FILE" \
    -f "$CURRENT_DIR/deploy/home-server/docker-compose.home.yml" \
    exec -T api node "$@" < /dev/null
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  command_name="${1:-}"
  probe_url="${2:-}"
  if [[ -z "$probe_url" ]]; then
    echo 'Usage: cloudflare-public-probe.sh <body|artifact> <https-url>' >&2
    exit 2
  fi
  case "$command_name" in
    body) opshub_cloudflare_public_body "$probe_url" "${@:3}" ;;
    artifact) opshub_cloudflare_public_artifact "$probe_url" "${@:3}" ;;
    *)
      echo "Unknown Cloudflare public probe command: ${command_name:-missing}." >&2
      exit 2
      ;;
  esac
fi
