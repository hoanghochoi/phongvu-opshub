#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo 'Usage: verify-production-origin.sh <runtime-env> <downloads-dir>' >&2
  exit 64
fi
runtime_env="$1" downloads_dir="$2" origin='http://127.0.0.1:8090'
temp="$(mktemp -d)"; trap 'rm -rf "$temp"' EXIT

request_status() {
  local host="$1" path="$2" expected="$3"
  shift 3
  local status
  status="$(curl -sS -o /dev/null -w '%{http_code}' "$@" -H "Host: $host" -H 'X-Forwarded-Proto: https' "${origin}${path}")"
  [ "$status" = "$expected" ] || { echo "Direct origin ${host}${path} returned ${status}; expected ${expected}." >&2; return 1; }
}
request_content() {
  local host="$1" path="$2" output="$3" status
  status="$(curl -sS -o "$output" -w '%{http_code}' -H "Host: $host" -H 'X-Forwarded-Proto: https' "${origin}${path}")"
  [ "$status" = 200 ] && [ -s "$output" ] || { echo "Direct origin ${host}${path} failed the 200/non-empty contract." >&2; return 1; }
}

request_content phongvu.work / "$temp/index"
request_content phongvu.work /help "$temp/help"
request_content phongvu.work /download "$temp/download"
request_content api.phongvu.work /v1/health "$temp/health"
request_content opshub.hoanghochoi.com /api/health "$temp/legacy-health"
request_status phongvu.work /api/health 404
request_status phongvu.work /ws 404
request_status api.phongvu.work /health 404
request_status api.phongvu.work /v1/bidv/unknown 404
request_status unknown.phongvu.work /health 404

ws_status="$(curl --http1.1 --max-time 10 -sS -o "$temp/ws" -w '%{http_code}' \
  -H 'Host: api.phongvu.work' -H 'X-Forwarded-Proto: https' \
  -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' \
  -H 'Sec-WebSocket-Key: MDEyMzQ1Njc4OWFiY2RlZg==' "${origin}/v1/ws/v2")"
[ "$ws_status" = 401 ] || { echo "Direct origin realtime ticket denial returned ${ws_status}; expected 401." >&2; exit 1; }

legacy_headers="$temp/legacy-help.headers"
legacy_status="$(curl -sS -D "$legacy_headers" -o /dev/null -w '%{http_code}' \
  -H 'Host: opshub.hoanghochoi.com' -H 'X-Forwarded-Proto: https' "${origin}/help")"
legacy_location="$(awk 'tolower($1) == "location:" { $1=""; sub(/^[[:space:]]+/, ""); sub(/\r$/, ""); print; exit }' "$legacy_headers")"
[ "$legacy_status" = 308 ] && [ "$legacy_location" = 'https://phongvu.work/help' ] || {
  echo "Direct origin legacy Help bridge returned ${legacy_status} Location=${legacy_location:-<missing>}." >&2; exit 1;
}

for platform in android windows web; do
  request_content api.phongvu.work "/v1/app-version?platform=${platform}" "$temp/${platform}.json"
done
request_content phongvu.work /downloads/latest.json "$temp/latest.json"
cmp -s "$temp/latest.json" "$downloads_dir/latest.json" || { echo 'Served manifest differs from candidate shared manifest.' >&2; exit 1; }

python3 - "$runtime_env" "$downloads_dir" "$temp" <<'PY'
import hashlib, json, pathlib, sys, urllib.parse
def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''): value.update(chunk)
    return value.hexdigest()
env_path, downloads, responses = map(pathlib.Path, sys.argv[1:])
env = {}
for line in env_path.read_text(encoding='utf-8').splitlines():
    if line and not line.startswith('#') and '=' in line:
        key, value = line.split('=', 1); env[key] = value
for platform, prefix in {'android':'APP_ANDROID_', 'windows':'APP_WINDOWS_', 'web':'APP_WEB_'}.items():
    payload = json.loads((responses / f'{platform}.json').read_text(encoding='utf-8'))
    if payload.get('latestBuild') != int(env[f'{prefix}APP_BUILD_NUMBER']) or str(payload.get('latestVersion')) != env[f'{prefix}APP_VERSION']:
        raise SystemExit(f'{platform} app-version values differ from candidate env')
    if platform == 'web': continue
    url = str(payload.get('packageUrl') or '')
    if url != env[f'{prefix}APP_PACKAGE_URL'] or payload.get('updateUrl') != url:
        raise SystemExit(f'{platform} advertised package URL differs from candidate env')
    package = downloads / pathlib.PurePosixPath(urllib.parse.urlparse(url).path).name
    if not package.is_file() or package.stat().st_size <= 0: raise SystemExit(f'{platform} advertised package is missing')
    if package.stat().st_size != int(env[f'{prefix}APP_PACKAGE_SIZE_BYTES']): raise SystemExit(f'{platform} package size mismatch')
    if digest(package) != env[f'{prefix}APP_PACKAGE_SHA256']: raise SystemExit(f'{platform} package hash mismatch')
manifest = json.loads((responses / 'latest.json').read_text(encoding='utf-8'))
if str(manifest.get('version')) != env['APP_VERSION'] or manifest.get('build') != int(env['APP_BUILD_NUMBER']):
    raise SystemExit('candidate manifest version/build differs from candidate env')
expected_urls = {'apk': env['APP_ANDROID_APP_PACKAGE_URL'], 'windowsInstaller': env['APP_WINDOWS_APP_PACKAGE_URL']}
for key, item in (manifest.get('files') or {}).items():
    if key in expected_urls and str(item.get('url') or '') != expected_urls[key]: raise SystemExit(f'candidate manifest {key} URL mismatch')
    file = downloads / pathlib.PurePosixPath(urllib.parse.urlparse(str(item.get('url') or '')).path).name
    if not file.is_file() or file.stat().st_size != int(item.get('sizeBytes') or 0): raise SystemExit('manifest path is missing or has wrong size')
PY

token_status="$(curl -sS -o "$temp/token.json" -w '%{http_code}' -X POST \
  -H 'Host: api.phongvu.work' -H 'X-Forwarded-Proto: https' \
  -H 'Content-Type: application/x-www-form-urlencoded' -H 'Authorization: Basic aW52YWxpZDppbnZhbGlk' \
  --data 'grant_type=client_credentials' "${origin}/v1/bidv/oauth2/token")"
balance_status="$(curl -sS -o "$temp/balance.json" -w '%{http_code}' -X POST \
  -H 'Host: api.phongvu.work' -H 'X-Forwarded-Proto: https' -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer invalid' -H 'REQUESTID: opshub-release-gate' \
  --data '{"bankCode":"BIDV","data":"QQ=="}' "${origin}/v1/bidv/balance-changes")"
python3 - "$token_status" "$temp/token.json" "$balance_status" "$temp/balance.json" <<'PY'
import json, pathlib, sys
token_status, token_path, balance_status, balance_path = sys.argv[1:]
try:
    token_error = json.loads(pathlib.Path(token_path).read_text(encoding='utf-8')).get('error')
    balance_error = json.loads(pathlib.Path(balance_path).read_text(encoding='utf-8')).get('error')
except Exception as error:
    raise SystemExit(f'BIDV namespace returned malformed JSON: {error}')
pairs = {
    ('503', 'temporarily_unavailable', '503', 'temporarily_unavailable'),
    ('401', 'invalid_client', '401', 'invalid_token'),
}
actual = (token_status, token_error, balance_status, balance_error)
if actual not in pairs:
    raise SystemExit(f'BIDV namespace returned incoherent policy pair: {actual}')
PY

echo 'Production direct-origin web, API, realtime, BIDV policy, metadata and package coherence passed.'
