#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 6 ]; then
  echo 'Usage: verify-production-baseline.sh <release> <expected-env> <live-env> <current-link> <downloads-dir> <web-dir>' >&2
  exit 64
fi

release="$(readlink -f "$1")"
expected_env="$2"
live_env="$3"
current_link="$4"
downloads_dir="$5"
web_dir="$6"
compose_project='home-server'
compose_file="$release/deploy/home-server/docker-compose.home.yml"

privileged() { if [ -n "${OPSHUB_SUDO-sudo}" ]; then "${OPSHUB_SUDO-sudo}" "$@"; else "$@"; fi; }
fail() { echo "Production baseline verification: $*" >&2; exit 1; }
env_value() { privileged sed -n "s/^${2}=//p" "$1" | tail -n 1; }

[ "$(readlink -f "$current_link" || true)" = "$release" ] || fail 'release pointer is split from expected baseline'
privileged cmp -s "$expected_env" "$live_env" || fail 'live env is split from expected baseline'
compose=(docker compose --project-name "$compose_project" --env-file "$expected_env" -f "$compose_file")
compose_cmd() { "${compose[@]}" "$@" < /dev/null; }
compose_cmd config >/dev/null || fail 'expected baseline Compose config is invalid'

running_services="$(compose_cmd ps --status running --services)"
for service in redis api realtime caddy; do
  printf '%s\n' "$running_services" | grep -Fxq "$service" || fail "home-server service is not running: $service"
  container_id="$(compose_cmd ps -q "$service")"
  [ -n "$container_id" ] || fail "home-server service container is missing: $service"
  config_files="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project.config_files" }}' "$container_id")"
  [ "$config_files" = "$compose_file" ] || fail "home-server service $service belongs to a different Compose config"
done

expected_caddy_hash="$(sha256sum "$release/deploy/home-server/Caddyfile" | awk '{print $1}')"
mounted_caddy_hash="$(compose_cmd exec -T caddy sha256sum /etc/caddy/Caddyfile | awk '{print $1}')"
[ "$mounted_caddy_hash" = "$expected_caddy_hash" ] || fail 'mounted Caddyfile hash differs from release baseline'

domain="$(env_value "$expected_env" OPSHUB_DOMAIN)"
api_domain="$(env_value "$expected_env" OPSHUB_API_DOMAIN)"
if [ -n "$api_domain" ]; then api_host="$api_domain"; api_prefix='/v1'; else api_host="$domain"; api_prefix='/api'; fi
curl -fsS -H "Host: $domain" -H 'X-Forwarded-Proto: https' 'http://127.0.0.1:8090/health' >/dev/null ||
  fail 'baseline Caddy health check failed'

temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
for platform in android windows web; do
  curl -fsS -o "$temp/${platform}.json" -H "Host: $api_host" -H 'X-Forwarded-Proto: https' \
    "http://127.0.0.1:8090${api_prefix}/app-version?platform=${platform}" >/dev/null ||
    fail "baseline app-version endpoint failed for $platform"
done

python3 - "$expected_env" "$downloads_dir" "$temp" <<'PY'
import hashlib, json, os, pathlib, sys, urllib.parse
def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''): value.update(chunk)
    return value.hexdigest()

env_path, downloads_path, response_path = map(pathlib.Path, sys.argv[1:])
env = {}
for line in env_path.read_text(encoding='utf-8').splitlines():
    if line and not line.startswith('#') and '=' in line:
        key, value = line.split('=', 1)
        env[key] = value

prefixes = {'android': 'APP_ANDROID_', 'windows': 'APP_WINDOWS_', 'web': 'APP_WEB_'}
for platform, prefix in prefixes.items():
    payload = json.loads((response_path / f'{platform}.json').read_text(encoding='utf-8'))
    expected_build = int(env[f'{prefix}APP_BUILD_NUMBER'])
    if payload.get('latestBuild') != expected_build:
        raise SystemExit(f'{platform} app-version build differs from expected baseline')
    expected_version = env[f'{prefix}APP_VERSION']
    if str(payload.get('latestVersion')) != expected_version:
        raise SystemExit(f'{platform} app-version version differs from expected baseline')
    if platform == 'web':
        continue
    package_url = str(payload.get('packageUrl') or '')
    expected_url = env[f'{prefix}APP_PACKAGE_URL']
    if package_url != expected_url:
        raise SystemExit(f'{platform} package URL differs from expected baseline')
    package = downloads_path / pathlib.PurePosixPath(urllib.parse.urlparse(package_url).path).name
    if not package.is_file() or package.stat().st_size <= 0:
        raise SystemExit(f'{platform} advertised package is absent from shared downloads')
    expected_size = int(env.get(f'{prefix}APP_PACKAGE_SIZE_BYTES') or 0)
    if expected_size > 0 and package.stat().st_size != expected_size:
        raise SystemExit(f'{platform} advertised package size differs from shared downloads')
    expected_hash = env.get(f'{prefix}APP_PACKAGE_SHA256', '')
    if expected_hash and digest(package) != expected_hash:
        raise SystemExit(f'{platform} advertised package hash differs from shared downloads')

manifest_path = downloads_path / 'latest.json'
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
if str(manifest.get('version')) != env['APP_VERSION'] or manifest.get('build') != int(env['APP_BUILD_NUMBER']):
    raise SystemExit('download manifest version/build differs from exact env')
expected_urls = {
    'apk': env['APP_ANDROID_APP_PACKAGE_URL'],
    'windowsInstaller': env['APP_WINDOWS_APP_PACKAGE_URL'],
}
for key, entry in (manifest.get('files') or {}).items():
    url = str(entry.get('url') or '')
    if key in expected_urls and url != expected_urls[key]:
        raise SystemExit(f'download manifest {key} URL differs from app-version env')
    package = downloads_path / pathlib.PurePosixPath(urllib.parse.urlparse(url).path).name
    if not package.is_file() or package.stat().st_size <= 0 or package.stat().st_size != int(entry.get('sizeBytes') or 0):
        raise SystemExit('download manifest advertises an absent shared file')
PY

privileged test -s "$downloads_dir/latest.json" || fail 'shared download manifest is absent'
privileged test -s "$web_dir/index.html" || fail 'shared web baseline is absent'
privileged test -d "$downloads_dir/help/assets" || fail 'shared Help baseline is absent'
echo 'Production release pointer, env, home-server containers, Caddy and shared metadata are coherent.'
