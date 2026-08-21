#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 5 ]; then
  echo 'Usage: prepare-rollback-env.sh <previous-release> <env-snapshot> <prepared-env> <exact-authority-env> <source-commit>' >&2
  exit 64
fi

previous_release="$(readlink -f "$1")"
env_snapshot="$2"
prepared_env="$3"
authority_env="$4"
source_commit="$5"
compose_file="$previous_release/deploy/home-server/docker-compose.home.yml"
release_manifest="$previous_release/release-manifest.json"
release_local_env="$previous_release/deploy/home-server/env.example"
compose_project='home-server'

privileged() { if [ -n "${OPSHUB_SUDO-sudo}" ]; then "${OPSHUB_SUDO-sudo}" "$@"; else "$@"; fi; }
die() { echo "Rollback env preparation: $*" >&2; exit 1; }

[ -d "$previous_release" ] || die 'previous release is unavailable'
[ -f "$compose_file" ] || die 'previous release Compose file is unavailable'
[ -s "$release_manifest" ] || die 'previous release manifest is unavailable'
[ -s "$authority_env" ] || die 'exported exact-Git env authority is unavailable'
privileged test -s "$env_snapshot" || die 'protected env snapshot is unavailable'
[[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || die 'source commit is malformed'

release_name="$(basename "$previous_release")"
case "$release_name" in "$source_commit"-*) ;; *) die 'release directory SHA does not match exact authority commit' ;; esac
manifest_commit="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["sourceCommit"])' "$release_manifest")" ||
  die 'release manifest sourceCommit is unreadable'
[ "$manifest_commit" = "$source_commit" ] || die 'release manifest sourceCommit does not match exact authority commit'

if [ -f "$release_local_env" ]; then
  authority_hash="$(sha256sum "$authority_env" | awk '{print $1}')"
  local_hash="$(sha256sum "$release_local_env" | awk '{print $1}')"
  [ "$authority_hash" = "$local_hash" ] || die 'release-local env.example differs from exact Git authority'
fi

case "$prepared_env" in "$env_snapshot".prepared) ;; *) die 'prepared env must be transaction-local to the protected snapshot' ;; esac
if ! privileged test -e "$prepared_env"; then
  privileged cp --preserve=mode,ownership,timestamps -- "$env_snapshot" "$prepared_env"
fi

read_authority_value() {
  local key="$1"
  awk -F= -v key="$key" '
    $0 ~ "^" key "=" { count++; value=substr($0, length(key) + 2) }
    END { if (count > 1) exit 2; if (count == 1) print value; else exit 1 }
  ' "$authority_env"
}

upsert_value() {
  local key="$1" value="$2" escaped
  escaped="$(printf '%s' "$value" | sed 's/[\\/&]/\\&/g')"
  if privileged grep -q "^${key}=" "$prepared_env"; then
    privileged sed -i "s/^${key}=.*/${key}=${escaped}/" "$prepared_env"
  else
    printf '%s=%s\n' "$key" "$value" | privileged tee -a "$prepared_env" >/dev/null
  fi
}
remove_value() { privileged sed -i "/^${1}=/d" "$prepared_env"; }

required_public_keys=(OPSHUB_DOMAIN PUBLIC_BASE_URL IMAGE_BASE_URL PRIVATE_MEDIA_PUBLIC_BASE_URL ALLOWED_ORIGINS)
optional_public_keys=(OPSHUB_API_DOMAIN OPSHUB_LEGACY_DOMAIN BIDV_H2H_DOMAIN BIDV_H2H_PUBLIC_BASE_URL BIDV_H2H_ENVIRONMENT)
for key in "${required_public_keys[@]}"; do
  value="$(read_authority_value "$key")" || die "exact Git authority is missing or duplicates required key $key"
  [ -n "$value" ] || die "exact Git authority has empty required key $key"
  upsert_value "$key" "$value"
done
for key in "${optional_public_keys[@]}"; do
  status=0; value="$(read_authority_value "$key")" || status=$?
  case "$status" in
    0) [ -n "$value" ] || die "exact Git authority has empty optional key $key"; upsert_value "$key" "$value" ;;
    1) remove_value "$key" ;;
    *) die "exact Git authority duplicates optional key $key" ;;
  esac
done

env_value() { privileged sed -n "s/^${1}=//p" "$prepared_env" | tail -n 1; }
domain="$(env_value OPSHUB_DOMAIN)"
api_domain="$(env_value OPSHUB_API_DOMAIN)"
legacy_domain="$(env_value OPSHUB_LEGACY_DOMAIN)"
public_url="$(env_value PUBLIC_BASE_URL)"
image_url="$(env_value IMAGE_BASE_URL)"
private_media_url="$(env_value PRIVATE_MEDIA_PUBLIC_BASE_URL)"
allowed_origins="$(env_value ALLOWED_ORIGINS)"
bidv_domain="$(env_value BIDV_H2H_DOMAIN)"
bidv_url="$(env_value BIDV_H2H_PUBLIC_BASE_URL)"
bidv_environment="$(env_value BIDV_H2H_ENVIRONMENT)"

for host in "$domain" ${api_domain:+"$api_domain"} ${legacy_domain:+"$legacy_domain"} ${bidv_domain:+"$bidv_domain"}; do
  [[ "$host" =~ ^[A-Za-z0-9.-]+$ ]] || die 'exact authority contains a malformed hostname'
done
[ "$public_url" = "https://${domain}" ] || die 'PUBLIC_BASE_URL does not match OPSHUB_DOMAIN'
[ "$image_url" = "${public_url}/uploads" ] || die 'IMAGE_BASE_URL does not match PUBLIC_BASE_URL'
if [ -n "$api_domain" ]; then
  [ "$private_media_url" = "https://${api_domain}/v1" ] || die 'private media URL does not match API domain namespace'
else
  [ "$private_media_url" = "${public_url}/api" ] || die 'legacy private media URL does not match web domain namespace'
fi
case ",${allowed_origins}," in *,"$public_url",*) ;; *) die 'ALLOWED_ORIGINS does not include PUBLIC_BASE_URL' ;; esac
if [ -n "$bidv_domain$bidv_url$bidv_environment" ]; then
  [ -n "$bidv_domain" ] && [ "$bidv_url" = "https://${bidv_domain}" ] && [ "$bidv_environment" = production ] ||
    die 'legacy BIDV public authority is incomplete or inconsistent'
fi

docker compose --project-name "$compose_project" --env-file "$prepared_env" -f "$compose_file" config >/dev/null < /dev/null ||
  die 'exact previous release Compose config is invalid'
echo 'Exact previous release public authority normalized and Compose-validated.'
