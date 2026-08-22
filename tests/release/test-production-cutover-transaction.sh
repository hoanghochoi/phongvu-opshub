#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT

mock_bin="$temp/bin"
mkdir -p "$mock_bin"

cat > "$mock_bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_DOCKER_LOG"
if [ "${1:-}" = compose ] && [ -n "${MOCK_EXPECT_OPSHUB_ENV_FILE:-}" ] && \
   [ "${OPSHUB_ENV_FILE:-}" != "$MOCK_EXPECT_OPSHUB_ENV_FILE" ]; then
  echo "Compose did not receive the exact runtime env path: ${OPSHUB_ENV_FILE:-<missing>}" >&2
  exit 25
fi
if [ "${MOCK_BASELINE_MODE:-false}" = true ]; then
  if [[ " $* " == *" ps --status running --services "* ]]; then printf '%s\n' redis api realtime caddy; exit 0; fi
  if [[ " $* " == *" ps -q "* ]]; then printf 'fixture-%s\n' "${*: -1}"; exit 0; fi
  if [[ " $* " == *" exec -T caddy sha256sum /etc/caddy/Caddyfile "* ]]; then printf '%s  /etc/caddy/Caddyfile\n' "$MOCK_CADDY_HASH"; exit 0; fi
  if [[ " $* " == *"com.docker.compose.project.config_files"* ]]; then printf '%s\n' "$MOCK_COMPOSE_FILE"; exit 0; fi
  if [[ " $* " == *"{{.Image}}"* ]]; then printf 'sha256:%s%s\n' "${*: -1}" "${MOCK_IMAGE_SUFFIX:-}"; exit 0; fi
fi
if [[ " $* " == *" up "* && -n "${MOCK_FAIL_RELEASE:-}" && " $* " == *" $MOCK_FAIL_RELEASE/"* ]]; then
  exit 23
fi
if [[ " $* " == *" config "* && -n "${MOCK_INVALID_ENV:-}" && " $* " == *" --env-file $MOCK_INVALID_ENV "* ]]; then
  exit 24
fi
if [[ " $* " == *" up "* && -n "${MOCK_SIGNAL_RELEASE:-}" && " $* " == *" $MOCK_SIGNAL_RELEASE/"* && ! -e "$MOCK_SIGNAL_MARKER" ]]; then
  : > "$MOCK_SIGNAL_MARKER"
  kill -HUP "$PPID"
fi
MOCK

cat > "$mock_bin/cloudflared" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
test "$1" = --config
test -s "$2"
test "$3 $4 $5" = 'tunnel ingress validate'
grep -Fq '  - service: http_status:404' "$2"
if [ -n "${MOCK_CLOUDFLARED_DRIFT_CONFIG:-}" ] && [ ! -e "$MOCK_CLOUDFLARED_DRIFT_MARKER" ]; then
  count_file="${MOCK_CLOUDFLARED_DRIFT_MARKER}.count"
  count=0
  [ ! -s "$count_file" ] || count="$(cat "$count_file")"
  count=$((count + 1))
  printf '%s\n' "$count" > "$count_file"
  if [ "$count" -ge "${MOCK_CLOUDFLARED_DRIFT_AFTER:-1}" ]; then
    : > "$MOCK_CLOUDFLARED_DRIFT_MARKER"
    sed -i '/  - service: http_status:404/i\  - hostname: concurrent-validation.example.com\n    service: http://localhost:9997' "$MOCK_CLOUDFLARED_DRIFT_CONFIG"
  fi
fi
MOCK

cat > "$mock_bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_SYSTEMCTL_LOG"
if [ "$1" = restart ] && [ -n "${MOCK_SYSTEMCTL_FAIL_ONCE:-}" ] && [ ! -e "$MOCK_SYSTEMCTL_FAIL_ONCE" ]; then
  : > "$MOCK_SYSTEMCTL_FAIL_ONCE"
  exit 24
fi
if [ "$1" = restart ] && [ -n "${MOCK_SYSTEMCTL_SIGNAL_ONCE:-}" ] && [ ! -e "$MOCK_SYSTEMCTL_SIGNAL_ONCE" ]; then
  : > "$MOCK_SYSTEMCTL_SIGNAL_ONCE"
  kill -HUP "$PPID"
fi
case "$1" in restart) exit 0 ;; is-active) exit 0 ;; *) exit 64 ;; esac
MOCK

cat > "$mock_bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [ "${MOCK_ORIGIN_MODE:-false}" != true ]; then exit 0; fi
host='' output='' headers='' url='' method='GET'
while (($#)); do
  case "$1" in
    -H) case "$2" in Host:\ *) host="${2#Host: }" ;; esac; shift 2 ;;
    -o) output="$2"; shift 2 ;;
    -D) headers="$2"; shift 2 ;;
    -w) shift 2 ;;
    -X) method="$2"; shift 2 ;;
    --data) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
path="/${url#*://*/}"
status=404
case "$host|$method|$path" in
  'phongvu.work|GET|/'|'phongvu.work|GET|/help'|'phongvu.work|GET|/download'|\
  'api.phongvu.work|GET|/v1/health'|'opshub.hoanghochoi.com|GET|/api/health'|\
  'api.phongvu.work|GET|/v1/app-version?platform=android'|\
  'api.phongvu.work|GET|/v1/app-version?platform=windows'|\
  'api.phongvu.work|GET|/v1/app-version?platform=web'|'phongvu.work|GET|/downloads/latest.json') status=200 ;;
  'opshub.hoanghochoi.com|GET|/health'|\
  'opshub.hoanghochoi.com|GET|/api/app-version?platform=android'|\
  'opshub.hoanghochoi.com|GET|/api/app-version?platform=windows'|\
  'opshub.hoanghochoi.com|GET|/api/app-version?platform=web') status=200 ;;
  'api.phongvu.work|GET|/v1/ws/v2') status=401 ;;
  'api.phongvu.work|POST|/v1/bidv/oauth2/token'|'api.phongvu.work|POST|/v1/bidv/balance-changes') if [ "${MOCK_BIDV_ENABLED:-false}" = true ]; then status=401; else status=503; fi ;;
  'opshub.hoanghochoi.com|GET|/help') status=308 ;;
esac
if [ -n "$output" ] && [ "$output" != /dev/null ]; then
  case "$path" in
    '/v1/app-version?platform=android'|'/api/app-version?platform=android') cp "$MOCK_ORIGIN_FIXTURES/android.json" "$output" ;;
    '/v1/app-version?platform=windows'|'/api/app-version?platform=windows') cp "$MOCK_ORIGIN_FIXTURES/windows.json" "$output" ;;
    '/v1/app-version?platform=web'|'/api/app-version?platform=web') cp "$MOCK_ORIGIN_FIXTURES/web.json" "$output" ;;
    '/downloads/latest.json') cp "$MOCK_ORIGIN_FIXTURES/latest.json" "$output" ;;
    '/v1/bidv/oauth2/token') if [ "${MOCK_BIDV_ENABLED:-false}" = true ]; then printf '{"error":"invalid_client"}\n'; else printf '{"error":"temporarily_unavailable"}\n'; fi > "$output" ;;
    '/v1/bidv/balance-changes') if [ "${MOCK_BIDV_ENABLED:-false}" = true ]; then printf '{"error":"invalid_token"}\n'; else printf '{"error":"temporarily_unavailable"}\n'; fi > "$output" ;;
    *) printf 'fixture body\n' > "$output" ;;
  esac
fi
if [ -n "$headers" ]; then
  printf 'HTTP/1.1 %s Fixture\r\n' "$status" > "$headers"
  if [ "$host|$path" = 'opshub.hoanghochoi.com|/help' ]; then
    printf 'Location: https://phongvu.work/help\r\n' >> "$headers"
  fi
fi
printf '%s' "$status"
MOCK
chmod +x "$mock_bin/docker" "$mock_bin/cloudflared" "$mock_bin/systemctl" "$mock_bin/curl"

export PATH="$mock_bin:$PATH"
export OPSHUB_SUDO=''
export MOCK_DOCKER_LOG="$temp/docker.log"
export MOCK_SYSTEMCTL_LOG="$temp/systemctl.log"
export CLOUDFLARED_BIN="$mock_bin/cloudflared"
export SYSTEMCTL_BIN="$mock_bin/systemctl"

write_release_manifest() {
  local release="$1" source_commit="$2"
  python3 - "$release" "$source_commit" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
files = []
for path in sorted(p for p in root.rglob('*') if p.is_file() and p.name != 'release-manifest.json'):
    data = path.read_bytes()
    files.append({'path': path.relative_to(root).as_posix(), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
(root / 'release-manifest.json').write_text(json.dumps({'schemaVersion': 1, 'sourceCommit': sys.argv[2], 'files': files}), encoding='utf-8')
PY
}

# The exact previous release may require the retired dedicated BIDV hostname.
# Only the tracked env.example from that release may supply the compatibility
# values; secret-bearing snapshot values must remain untouched and unprinted.
legacy_sha='430e1ffd9d7f1afae36f27df3a70dd10a24f3e5b'
legacy_release="$temp/releases/${legacy_sha}-old-run"
mkdir -p "$legacy_release/deploy/home-server"
mkdir -p "$legacy_release/backend-nest" "$legacy_release/backend-go"
cat > "$legacy_release/deploy/home-server/docker-compose.home.yml" <<'YAML'
services:
  api:
    image: example.invalid/opshub
    environment:
      BIDV_H2H_DOMAIN: ${BIDV_H2H_DOMAIN:?required}
YAML
printf 'legacy caddy\n' > "$legacy_release/deploy/home-server/Caddyfile"
printf 'legacy transaction\n' > "$legacy_release/deploy/home-server/release-transaction.sh"
printf 'legacy nest dockerfile\n' > "$legacy_release/backend-nest/Dockerfile"
printf 'legacy go dockerfile\n' > "$legacy_release/backend-go/Dockerfile"
write_release_manifest "$legacy_release" "$legacy_sha"
bash "$root/deploy/home-server/verify-release-manifest.sh" "$legacy_release" >/dev/null
authority_env="$temp/exact-authority.env.example"
cat > "$authority_env" <<'ENV'
OPSHUB_DOMAIN=opshub.hoanghochoi.com
PUBLIC_BASE_URL=https://opshub.hoanghochoi.com
IMAGE_BASE_URL=https://opshub.hoanghochoi.com/uploads
PRIVATE_MEDIA_PUBLIC_BASE_URL=https://opshub.hoanghochoi.com/api
ALLOWED_ORIGINS=https://opshub.hoanghochoi.com
BIDV_H2H_DOMAIN=bankapis.hoanghochoi.com
BIDV_H2H_PUBLIC_BASE_URL=https://bankapis.hoanghochoi.com
BIDV_H2H_ENVIRONMENT=production
ENV
cat > "$temp/env.snapshot" <<'ENV'
OPSHUB_DOMAIN=phongvu.work
OPSHUB_API_DOMAIN=api.phongvu.work
OPSHUB_LEGACY_DOMAIN=opshub.hoanghochoi.com
PUBLIC_BASE_URL=https://phongvu.work
IMAGE_BASE_URL=https://phongvu.work/uploads
PRIVATE_MEDIA_PUBLIC_BASE_URL=https://api.phongvu.work/v1
ALLOWED_ORIGINS=https://phongvu.work,https://opshub.hoanghochoi.com
JWT_SECRET=do-not-print-this-secret
ENV

prepare_output="$temp/prepare-output"
bash "$root/deploy/home-server/prepare-rollback-env.sh" \
  "$legacy_release" "$temp/env.snapshot" "$temp/env.snapshot.prepared" \
  "$authority_env" "$legacy_sha" > "$prepare_output"
grep -Fxq 'OPSHUB_DOMAIN=opshub.hoanghochoi.com' "$temp/env.snapshot.prepared"
grep -Fxq 'PUBLIC_BASE_URL=https://opshub.hoanghochoi.com' "$temp/env.snapshot.prepared"
grep -Fxq 'IMAGE_BASE_URL=https://opshub.hoanghochoi.com/uploads' "$temp/env.snapshot.prepared"
grep -Fxq 'PRIVATE_MEDIA_PUBLIC_BASE_URL=https://opshub.hoanghochoi.com/api' "$temp/env.snapshot.prepared"
! grep -q '^OPSHUB_API_DOMAIN=' "$temp/env.snapshot.prepared"
! grep -q '^OPSHUB_LEGACY_DOMAIN=' "$temp/env.snapshot.prepared"
grep -Fxq 'BIDV_H2H_DOMAIN=bankapis.hoanghochoi.com' "$temp/env.snapshot.prepared"
grep -Fxq 'BIDV_H2H_PUBLIC_BASE_URL=https://bankapis.hoanghochoi.com' "$temp/env.snapshot.prepared"
grep -Fxq 'BIDV_H2H_ENVIRONMENT=production' "$temp/env.snapshot.prepared"
grep -Fxq 'JWT_SECRET=do-not-print-this-secret' "$temp/env.snapshot.prepared"
! grep -Fq 'do-not-print-this-secret' "$prepare_output"
grep -Fq -- '--project-name home-server' "$MOCK_DOCKER_LOG"

cp "$authority_env" "$legacy_release/deploy/home-server/env.example"
printf '# local drift\n' >> "$legacy_release/deploy/home-server/env.example"
cp "$temp/env.snapshot" "$temp/env-bad.snapshot"
if bash "$root/deploy/home-server/prepare-rollback-env.sh" \
  "$legacy_release" "$temp/env-bad.snapshot" "$temp/env-bad.snapshot.prepared" \
  "$authority_env" "$legacy_sha" 2>/dev/null; then
  echo 'release-local authority drift unexpectedly passed exact Git hash gate' >&2
  exit 1
fi
rm -f "$legacy_release/deploy/home-server/env.example"
cp "$legacy_release/deploy/home-server/Caddyfile" "$temp/legacy-caddy"
printf 'tampered\n' >> "$legacy_release/deploy/home-server/Caddyfile"
if bash "$root/deploy/home-server/verify-release-manifest.sh" "$legacy_release" >/dev/null 2>&1; then
  echo 'tampered exact release Caddyfile unexpectedly passed manifest validation' >&2
  exit 1
fi
mv "$temp/legacy-caddy" "$legacy_release/deploy/home-server/Caddyfile"
cp "$legacy_release/deploy/home-server/docker-compose.home.yml" "$temp/legacy-compose"
printf '# tampered\n' >> "$legacy_release/deploy/home-server/docker-compose.home.yml"
if bash "$root/deploy/home-server/verify-release-manifest.sh" "$legacy_release" >/dev/null 2>&1; then
  echo 'tampered exact release Compose unexpectedly passed manifest validation' >&2
  exit 1
fi
mv "$temp/legacy-compose" "$legacy_release/deploy/home-server/docker-compose.home.yml"

# Tunnel activation inserts only the two production rules before the existing
# catch-all. Restore must reproduce the original config byte-for-byte.
tunnel_config="$temp/cloudflared.yml"
tunnel_snapshot="$temp/cloudflared.snapshot"
cat > "$tunnel_config" <<'YAML'
tunnel: 11111111-1111-1111-1111-111111111111
credentials-file: /etc/cloudflared/11111111-1111-1111-1111-111111111111.json
ingress:
  # unrelated rules and comments must survive unchanged
  - hostname: img.hoanghochoi.com
    service: http://localhost:8088
  - hostname: opshub.hoanghochoi.com
    service: http://localhost:8090
  - service: http_status:404
YAML
cp "$tunnel_config" "$temp/cloudflared.original"

export MOCK_CLOUDFLARED_DRIFT_CONFIG="$tunnel_config" MOCK_CLOUDFLARED_DRIFT_MARKER="$temp/cloudflared-drifted"
if bash "$root/deploy/home-server/cloudflare-ingress-transaction.sh" \
  activate "$tunnel_config" "$tunnel_snapshot" >/dev/null 2>&1; then
  echo 'Tunnel activation CAS unexpectedly accepted concurrent validation drift' >&2
  exit 1
fi
unset MOCK_CLOUDFLARED_DRIFT_CONFIG MOCK_CLOUDFLARED_DRIFT_MARKER
grep -Fq 'concurrent-validation.example.com' "$tunnel_config"
cp "$temp/cloudflared.original" "$tunnel_config"
rm -f "$tunnel_snapshot" "${tunnel_snapshot}.hashes"

export MOCK_SYSTEMCTL_FAIL_ONCE="$temp/systemctl-failed-once"
if bash "$root/deploy/home-server/cloudflare-ingress-transaction.sh" \
  activate "$tunnel_config" "$tunnel_snapshot" >/dev/null 2>&1; then
  echo 'Tunnel activation unexpectedly passed after an injected restart failure' >&2
  exit 1
fi
unset MOCK_SYSTEMCTL_FAIL_ONCE
cmp "$temp/cloudflared.original" "$tunnel_config"

bash "$root/deploy/home-server/cloudflare-ingress-transaction.sh" \
  activate "$tunnel_config" "$tunnel_snapshot"
test "$(grep -Fc '  - hostname: phongvu.work' "$tunnel_config")" -eq 1
test "$(grep -Fc '  - hostname: api.phongvu.work' "$tunnel_config")" -eq 1
test "$(grep -Fc '    service: http://localhost:8090' "$tunnel_config")" -eq 3
prod_line=$(grep -n '  - hostname: phongvu.work' "$tunnel_config" | cut -d: -f1)
catchall_line=$(grep -n '  - service: http_status:404' "$tunnel_config" | cut -d: -f1)
test "$prod_line" -lt "$catchall_line"

# A repeated activation is safe and does not duplicate routes or snapshots.
snapshot_hash=$(sha256sum "$tunnel_snapshot" | awk '{print $1}')
bash "$root/deploy/home-server/cloudflare-ingress-transaction.sh" \
  activate "$tunnel_config" "$tunnel_snapshot"
test "$(grep -Fc '  - hostname: phongvu.work' "$tunnel_config")" -eq 1
test "$(sha256sum "$tunnel_snapshot" | awk '{print $1}')" = "$snapshot_hash"

cp "$tunnel_config" "$temp/cloudflared.active"
sed -i '/  - service: http_status:404/i\  - hostname: unrelated-new.example.com\n    service: http://localhost:9998' "$tunnel_config"
cp "$tunnel_config" "$temp/cloudflared.concurrent-drift"
bash "$root/deploy/home-server/cloudflare-ingress-transaction.sh" \
  restore "$tunnel_config" "$tunnel_snapshot"
grep -Fq 'unrelated-new.example.com' "$tunnel_config"
! grep -Fq '  - hostname: phongvu.work' "$tunnel_config"
! grep -Fq '  - hostname: api.phongvu.work' "$tunnel_config"
cp "$temp/cloudflared.concurrent-drift" "$temp/cloudflared.concurrent-expected"
sed -i '/  - hostname: phongvu.work/{N;d;}' "$temp/cloudflared.concurrent-expected"
sed -i '/  - hostname: api.phongvu.work/{N;d;}' "$temp/cloudflared.concurrent-expected"
cmp "$temp/cloudflared.concurrent-expected" "$tunnel_config"

# A validation-time edit after the surgical candidate is rendered must trip
# the final live CAS and remain untouched, including the owned pair.
cp "$temp/cloudflared.original" "$tunnel_config"
rm -f "$tunnel_snapshot" "${tunnel_snapshot}.hashes"
bash "$root/deploy/home-server/cloudflare-ingress-transaction.sh" \
  activate "$tunnel_config" "$tunnel_snapshot"
export MOCK_CLOUDFLARED_DRIFT_CONFIG="$tunnel_config" \
  MOCK_CLOUDFLARED_DRIFT_MARKER="$temp/cloudflared-restore-race" \
  MOCK_CLOUDFLARED_DRIFT_AFTER=2
if bash "$root/deploy/home-server/cloudflare-ingress-transaction.sh" \
  restore "$tunnel_config" "$tunnel_snapshot" >/dev/null 2>&1; then
  echo 'Tunnel restore CAS unexpectedly overwrote a validation-time edit' >&2
  exit 1
fi
unset MOCK_CLOUDFLARED_DRIFT_CONFIG MOCK_CLOUDFLARED_DRIFT_MARKER MOCK_CLOUDFLARED_DRIFT_AFTER
grep -Fq 'concurrent-validation.example.com' "$tunnel_config"
grep -Fq '  - hostname: phongvu.work' "$tunnel_config"
grep -Fq '  - hostname: api.phongvu.work' "$tunnel_config"

# A change to either owned rule is not unrelated drift and must fail closed.
cp "$temp/cloudflared.original" "$tunnel_config"
rm -f "$tunnel_snapshot" "${tunnel_snapshot}.hashes"
bash "$root/deploy/home-server/cloudflare-ingress-transaction.sh" \
  activate "$tunnel_config" "$tunnel_snapshot"
sed -i '/  - hostname: api.phongvu.work/{n;s#http://localhost:8090#http://localhost:9999#;}' "$tunnel_config"
cp "$tunnel_config" "$temp/cloudflared-owned-drift"
if bash "$root/deploy/home-server/cloudflare-ingress-transaction.sh" \
  restore "$tunnel_config" "$tunnel_snapshot" >/dev/null 2>&1; then
  echo 'Tunnel restore unexpectedly accepted drift in an owned rule' >&2
  exit 1
fi
cmp "$temp/cloudflared-owned-drift" "$tunnel_config"

cp "$temp/cloudflared.original" "$tunnel_config"
rm -f "$tunnel_snapshot" "${tunnel_snapshot}.hashes"
bash "$root/deploy/home-server/cloudflare-ingress-transaction.sh" \
  activate "$tunnel_config" "$tunnel_snapshot"

bash "$root/deploy/home-server/cloudflare-ingress-transaction.sh" \
  restore "$tunnel_config" "$tunnel_snapshot"
cmp "$temp/cloudflared.original" "$tunnel_config"
bash "$root/deploy/home-server/cloudflare-ingress-transaction.sh" \
  restore "$tunnel_config" "$tunnel_snapshot"

export MOCK_SYSTEMCTL_SIGNAL_ONCE="$temp/systemctl-signalled-once"
if bash "$root/deploy/home-server/cloudflare-ingress-transaction.sh" \
  activate "$tunnel_config" "$tunnel_snapshot" >/dev/null 2>&1; then
  echo 'Tunnel activation unexpectedly returned success after HUP' >&2
  exit 1
fi
unset MOCK_SYSTEMCTL_SIGNAL_ONCE
cmp "$temp/cloudflared.original" "$tunnel_config"

# Reactivate and finalize; a validation-time privileged edit must retain the
# checkpoint instead of deleting the only rollback authority.
bash "$root/deploy/home-server/cloudflare-ingress-transaction.sh" \
  activate "$tunnel_config" "$tunnel_snapshot"
export MOCK_CLOUDFLARED_DRIFT_CONFIG="$tunnel_config" \
  MOCK_CLOUDFLARED_DRIFT_MARKER="$temp/cloudflared-finalize-race"
if bash "$root/deploy/home-server/cloudflare-ingress-transaction.sh" \
  finalize "$tunnel_config" "$tunnel_snapshot" >/dev/null 2>&1; then
  echo 'Tunnel finalize unexpectedly discarded its checkpoint after validation-time drift' >&2
  exit 1
fi
unset MOCK_CLOUDFLARED_DRIFT_CONFIG MOCK_CLOUDFLARED_DRIFT_MARKER
test -s "$tunnel_snapshot"
test -s "${tunnel_snapshot}.hashes"
grep -Fq 'concurrent-validation.example.com' "$tunnel_config"

cp "$temp/cloudflared.original" "$tunnel_config"
rm -f "$tunnel_snapshot" "${tunnel_snapshot}.hashes"
bash "$root/deploy/home-server/cloudflare-ingress-transaction.sh" \
  activate "$tunnel_config" "$tunnel_snapshot"
bash "$root/deploy/home-server/cloudflare-ingress-transaction.sh" \
  finalize "$tunnel_config" "$tunnel_snapshot"
bash "$root/deploy/home-server/cloudflare-ingress-transaction.sh" \
  finalize "$tunnel_config" "$tunnel_snapshot"
test ! -e "$tunnel_snapshot"
grep -Fq 'restart cloudflared.service' "$MOCK_SYSTEMCTL_LOG"
grep -Fq 'is-active --quiet cloudflared.service' "$MOCK_SYSTEMCTL_LOG"

# A transaction that finds the exact production pair already active does not
# own those routes. Unrelated drift must survive restore together with both
# pre-existing production rules.
preexisting_config="$temp/cloudflared-preexisting.yml"
preexisting_snapshot="$temp/cloudflared-preexisting.snapshot"
cp "$temp/cloudflared.original" "$preexisting_config"
sed -i '/  - service: http_status:404/i\  - hostname: phongvu.work\n    service: http://localhost:8090\n  - hostname: api.phongvu.work\n    service: http://localhost:8090' "$preexisting_config"
bash "$root/deploy/home-server/cloudflare-ingress-transaction.sh" \
  activate "$preexisting_config" "$preexisting_snapshot"
test "$(sed -n '3p' "${preexisting_snapshot}.hashes")" = preexisting
sed -i '/  - service: http_status:404/i\  - hostname: unrelated-preexisting.example.com\n    service: http://localhost:9996' "$preexisting_config"
bash "$root/deploy/home-server/cloudflare-ingress-transaction.sh" \
  restore "$preexisting_config" "$preexisting_snapshot"
grep -Fq '  - hostname: phongvu.work' "$preexisting_config"
grep -Fq '  - hostname: api.phongvu.work' "$preexisting_config"
grep -Fq '  - hostname: unrelated-preexisting.example.com' "$preexisting_config"
test "$(grep -Fc '    service: http://localhost:8090' "$preexisting_config")" -eq 3
rm -f "$preexisting_snapshot" "${preexisting_snapshot}.hashes"

for fixture in wrong-service cross-environment duplicate missing-catchall after-catchall quoted-target; do
  fixture_config="$temp/$fixture.yml"
  cp "$temp/cloudflared.original" "$fixture_config"
  case "$fixture" in
    wrong-service)
      sed -i '/  - service: http_status:404/i\  - hostname: phongvu.work\n    service: http://localhost:9999\n  - hostname: api.phongvu.work\n    service: http://localhost:8090' "$fixture_config"
      ;;
    cross-environment)
      sed -i '/  - service: http_status:404/i\  - hostname: staging.phongvu.work\n    service: http://localhost:8090' "$fixture_config"
      ;;
    duplicate)
      sed -i '/  - service: http_status:404/i\  - hostname: img.hoanghochoi.com\n    service: http://localhost:8090' "$fixture_config"
      ;;
    missing-catchall)
      sed -i '/  - service: http_status:404/d' "$fixture_config"
      ;;
    after-catchall)
      printf '%s\n' '  - hostname: late.example.com' '    service: http://localhost:9999' >> "$fixture_config"
      ;;
    quoted-target)
      sed -i '/  - service: http_status:404/i\  - hostname: "phongvu.work"\n    service: http://localhost:8090' "$fixture_config"
      ;;
  esac
  if bash "$root/deploy/home-server/cloudflare-ingress-transaction.sh" \
    activate "$fixture_config" "$fixture_config.snapshot" >/dev/null 2>&1; then
    echo "unsafe Tunnel fixture unexpectedly passed: $fixture" >&2
    exit 1
  fi
done

origin_fixture="$temp/origin-fixture"
mkdir -p "$origin_fixture/downloads"
printf 'android package\n' > "$origin_fixture/downloads/app.apk"
printf 'windows package\n' > "$origin_fixture/downloads/app.exe"
printf 'download page\n' > "$origin_fixture/downloads/download.html"
printf 'download icon\n' > "$origin_fixture/downloads/opshub-icon-192.png"
android_size=$(stat -c%s "$origin_fixture/downloads/app.apk")
windows_size=$(stat -c%s "$origin_fixture/downloads/app.exe")
android_hash=$(sha256sum "$origin_fixture/downloads/app.apk" | awk '{print $1}')
windows_hash=$(sha256sum "$origin_fixture/downloads/app.exe" | awk '{print $1}')
cat > "$origin_fixture/runtime.env" <<ENV
APP_VERSION=1.2.3
APP_BUILD_NUMBER=123
APP_ANDROID_APP_VERSION=1.2.3
APP_ANDROID_APP_BUILD_NUMBER=123
APP_ANDROID_APP_PACKAGE_URL=https://opshub.hoanghochoi.com/downloads/app.apk
APP_ANDROID_APP_PACKAGE_SIZE_BYTES=$android_size
APP_ANDROID_APP_PACKAGE_SHA256=$android_hash
APP_WINDOWS_APP_VERSION=1.2.3
APP_WINDOWS_APP_BUILD_NUMBER=123
APP_WINDOWS_APP_PACKAGE_URL=https://opshub.hoanghochoi.com/downloads/app.exe
APP_WINDOWS_APP_PACKAGE_SIZE_BYTES=$windows_size
APP_WINDOWS_APP_PACKAGE_SHA256=$windows_hash
APP_WEB_APP_VERSION=1.2.3
APP_WEB_APP_BUILD_NUMBER=123
ENV
printf '%s\n' '{"latestVersion":"1.2.3","latestBuild":123,"packageUrl":"https://opshub.hoanghochoi.com/downloads/app.apk","updateUrl":"https://opshub.hoanghochoi.com/downloads/app.apk"}' > "$origin_fixture/android.json"
printf '%s\n' '{"latestVersion":"1.2.3","latestBuild":123,"packageUrl":"https://opshub.hoanghochoi.com/downloads/app.exe","updateUrl":"https://opshub.hoanghochoi.com/downloads/app.exe"}' > "$origin_fixture/windows.json"
printf '%s\n' '{"latestVersion":"1.2.3","latestBuild":123}' > "$origin_fixture/web.json"
printf '%s\n' "{\"version\":\"1.2.3\",\"build\":123,\"files\":{\"apk\":{\"url\":\"https://opshub.hoanghochoi.com/downloads/app.apk\",\"sizeBytes\":$android_size},\"windowsInstaller\":{\"url\":\"https://opshub.hoanghochoi.com/downloads/app.exe\",\"sizeBytes\":$windows_size}}}" > "$origin_fixture/latest.json"
cp "$origin_fixture/latest.json" "$origin_fixture/downloads/latest.json"
export MOCK_ORIGIN_MODE=true MOCK_ORIGIN_FIXTURES="$origin_fixture"
bash "$root/deploy/home-server/verify-production-origin.sh" \
  "$origin_fixture/runtime.env" "$origin_fixture/downloads"
MOCK_BIDV_ENABLED=true bash "$root/deploy/home-server/verify-production-origin.sh" \
  "$origin_fixture/runtime.env" "$origin_fixture/downloads"
unset MOCK_ORIGIN_MODE

baseline_release="$temp/releases/baseline"
drift_release="$temp/releases/drift"
mkdir -p "$baseline_release/deploy/home-server" "$drift_release" \
  "$origin_fixture/web" "$origin_fixture/downloads/help/assets" \
  "$origin_fixture/downloads/help/content"
printf 'services: {}\n' > "$baseline_release/deploy/home-server/docker-compose.home.yml"
printf 'baseline caddy\n' > "$baseline_release/deploy/home-server/Caddyfile"
printf 'web\n' > "$origin_fixture/web/index.html"
printf 'compiled app\n' > "$origin_fixture/web/main.dart.js"
mkdir -p "$origin_fixture/web/assets/nested"
printf 'nested asset\n' > "$origin_fixture/web/assets/nested/data.bin"
printf 'help\n' > "$origin_fixture/downloads/help/assets/help.md"
printf '[{"key":"help","title":"Help","file":"help.md"}]\n' > "$origin_fixture/downloads/help/navigation.json"
printf 'baseline Help content\n' > "$origin_fixture/downloads/help/content/help.md"
{
  printf '%s\n' 'OPSHUB_DOMAIN=opshub.hoanghochoi.com'
  cat "$origin_fixture/runtime.env"
} > "$origin_fixture/baseline.env"
cp "$origin_fixture/baseline.env" "$origin_fixture/live-drift.env"
sed -i 's/^OPSHUB_DOMAIN=.*/OPSHUB_DOMAIN=phongvu.work/' "$origin_fixture/live-drift.env"
ln -s "$drift_release" "$origin_fixture/current"
export MOCK_ORIGIN_MODE=true MOCK_BASELINE_MODE=true
export MOCK_CADDY_HASH="$(sha256sum "$baseline_release/deploy/home-server/Caddyfile" | awk '{print $1}')"
export MOCK_COMPOSE_FILE="$baseline_release/deploy/home-server/docker-compose.home.yml"
if bash "$root/deploy/home-server/verify-production-baseline.sh" \
  "$baseline_release" "$origin_fixture/baseline.env" "$origin_fixture/live-drift.env" \
  "$origin_fixture/current" "$origin_fixture/downloads" "$origin_fixture/web" >/dev/null 2>&1; then
  echo 'split previous-release baseline unexpectedly passed coherence verification' >&2
  exit 1
fi
rm -f "$origin_fixture/current"; ln -s "$baseline_release" "$origin_fixture/current"
cp "$origin_fixture/baseline.env" "$origin_fixture/live-drift.env"
unset OPSHUB_ENV_FILE
export MOCK_EXPECT_OPSHUB_ENV_FILE="$origin_fixture/baseline.env"
bash "$root/deploy/home-server/verify-production-baseline.sh" \
  "$baseline_release" "$origin_fixture/baseline.env" "$origin_fixture/live-drift.env" \
  "$origin_fixture/current" "$origin_fixture/downloads" "$origin_fixture/web"

identity_sha='3333333333333333333333333333333333333333'
identity_release="$temp/releases/${identity_sha}-identity"
mkdir -p "$identity_release/deploy/home-server" "$identity_release/backend-nest" "$identity_release/backend-go"
cp "$baseline_release/deploy/home-server/docker-compose.home.yml" "$identity_release/deploy/home-server/docker-compose.home.yml"
cp "$baseline_release/deploy/home-server/Caddyfile" "$identity_release/deploy/home-server/Caddyfile"
printf 'identity transaction\n' > "$identity_release/deploy/home-server/release-transaction.sh"
printf 'identity nest\n' > "$identity_release/backend-nest/Dockerfile"
printf 'identity go\n' > "$identity_release/backend-go/Dockerfile"
write_release_manifest "$identity_release" "$identity_sha"
rm -f "$origin_fixture/current"; ln -s "$identity_release" "$origin_fixture/current"
export MOCK_COMPOSE_FILE="$identity_release/deploy/home-server/docker-compose.home.yml"
export MOCK_CADDY_HASH="$(sha256sum "$identity_release/deploy/home-server/Caddyfile" | awk '{print $1}')"
identity_record="$origin_fixture/runtime-identity.json"
bash "$root/deploy/home-server/production-runtime-identity.sh" write "$identity_record" \
  "$identity_release" "$origin_fixture/baseline.env" "$origin_fixture/downloads" \
  "$origin_fixture/web" "$origin_fixture/current"
bash "$root/deploy/home-server/production-runtime-identity.sh" verify "$identity_record" \
  "$identity_release" "$origin_fixture/baseline.env" "$origin_fixture/downloads" \
  "$origin_fixture/web" "$origin_fixture/current"
MOCK_IMAGE_SUFFIX=-different bash "$root/deploy/home-server/production-runtime-identity.sh" verify "$identity_record" \
  "$identity_release" "$origin_fixture/baseline.env" "$origin_fixture/downloads" \
  "$origin_fixture/web" "$origin_fixture/current" >/dev/null 2>&1 && {
    echo 'same-version runtime with different image IDs unexpectedly passed identity proof' >&2; exit 1;
  }
printf 'stale web\n' >> "$origin_fixture/web/index.html"
if bash "$root/deploy/home-server/production-runtime-identity.sh" verify "$identity_record" \
  "$identity_release" "$origin_fixture/baseline.env" "$origin_fixture/downloads" \
  "$origin_fixture/web" "$origin_fixture/current" >/dev/null 2>&1; then
  echo 'stale web unexpectedly passed runtime identity proof' >&2; exit 1
fi
printf 'web\n' > "$origin_fixture/web/index.html"
printf 'tampered compiled app\n' >> "$origin_fixture/web/main.dart.js"
if bash "$root/deploy/home-server/production-runtime-identity.sh" verify "$identity_record" \
  "$identity_release" "$origin_fixture/baseline.env" "$origin_fixture/downloads" \
  "$origin_fixture/web" "$origin_fixture/current" >/dev/null 2>&1; then
  echo 'tampered main.dart.js unexpectedly passed runtime identity proof' >&2; exit 1
fi
printf 'compiled app\n' > "$origin_fixture/web/main.dart.js"
printf 'tampered nested asset\n' >> "$origin_fixture/web/assets/nested/data.bin"
if bash "$root/deploy/home-server/production-runtime-identity.sh" verify "$identity_record" \
  "$identity_release" "$origin_fixture/baseline.env" "$origin_fixture/downloads" \
  "$origin_fixture/web" "$origin_fixture/current" >/dev/null 2>&1; then
  echo 'tampered nested web asset unexpectedly passed runtime identity proof' >&2; exit 1
fi
printf 'nested asset\n' > "$origin_fixture/web/assets/nested/data.bin"
printf ' ' >> "$origin_fixture/downloads/latest.json"
if bash "$root/deploy/home-server/production-runtime-identity.sh" verify "$identity_record" \
  "$identity_release" "$origin_fixture/baseline.env" "$origin_fixture/downloads" \
  "$origin_fixture/web" "$origin_fixture/current" >/dev/null 2>&1; then
  echo 'stale manifest unexpectedly passed runtime identity proof' >&2; exit 1
fi
cp "$origin_fixture/latest.json" "$origin_fixture/downloads/latest.json"
unset MOCK_EXPECT_OPSHUB_ENV_FILE

# A successful static-only publication updates shared Help/landing metadata,
# keeps the immutable release manifest valid, and refreshes runtime identity
# before its rollback checkpoint is removed.
static_input="$temp/static-input"
mkdir -p "$static_input/help/assets" "$static_input/help/content"
cp "$origin_fixture/downloads/latest.json" "$static_input/latest.json"
cp "$origin_fixture/downloads/download.html" "$static_input/download.html"
cp "$origin_fixture/downloads/opshub-icon-192.png" "$static_input/opshub-icon-192.png"
printf 'static refreshed help\n' > "$static_input/help/assets/help.md"
printf '[{"key":"static-help","title":"Static Help","file":"static.md"}]\n' > "$static_input/help/navigation.json"
printf 'static refreshed Help content sentinel\n' > "$static_input/help/content/static.md"
tar -C "$static_input/help" -czf "$static_input/docs-help.tar.gz" .
(
  source "$root/deploy/home-server/release-transaction.sh"
  export OPSHUB_SUDO='' DEPLOY_RUN_ID=850 DEPLOY_RUN_ATTEMPT=1 \
    OPSHUB_ENV_FILE="$origin_fixture/baseline.env" OPSHUB_SSD_ROOT="$temp/static-ssd" \
    OPSHUB_REMOTE_APP_DIR="$temp" CURRENT_DIR="$origin_fixture/current" \
    REMOTE_RELEASE_DIR="$origin_fixture/current" DOWNLOADS_DIR="$origin_fixture/downloads" \
    WEB_DIR="$origin_fixture/web" TXN_INPUT_DIR="$static_input" OPSHUB_TXN_STATIC_ONLY=true
  opshub_txn_begin
  opshub_txn_promote_static
  opshub_txn_require_promoted
  bash "$root/deploy/home-server/verify-release-manifest.sh" "$identity_release" >/dev/null
  bash "$root/deploy/home-server/production-runtime-identity.sh" write "$identity_record" \
    "$identity_release" "$origin_fixture/baseline.env" "$origin_fixture/downloads" \
    "$origin_fixture/web" "$origin_fixture/current"
  bash "$root/deploy/home-server/production-runtime-identity.sh" verify "$identity_record" \
    "$identity_release" "$origin_fixture/baseline.env" "$origin_fixture/downloads" \
    "$origin_fixture/web" "$origin_fixture/current"
  opshub_txn_cleanup
)
grep -Fxq 'static refreshed help' "$origin_fixture/downloads/help/assets/help.md"
test ! -e "$temp/static-ssd/rollback/deploy-850-1.state"

# Historical shared reconciliation owns its recovery boundary. An injected HUP
# immediately after removing the live web/Help trees must still leave the exact
# historical web, Help, manifest, landing assets and versioned packages in
# place before the interrupted process exits.
reconcile_ssd="$temp/reconcile-ssd"
reconcile_rollback="$reconcile_ssd/rollback"
historical_state="$reconcile_rollback/deploy-900-1.state"
historical_shared="$reconcile_rollback/deploy-900-1.shared"
reconcile_live_env="$temp/reconcile-live.env"
mkdir -p "$historical_shared/downloads" "$historical_shared/versioned"
cp -a "$origin_fixture/web" "$historical_shared/web"
cp -a "$origin_fixture/downloads/help" "$historical_shared/downloads/help"
for name in latest.json download.html opshub-icon-192.png; do
  cp -a "$origin_fixture/downloads/$name" "$historical_shared/downloads/$name"
done
cp -a "$origin_fixture/downloads/app.apk" "$historical_shared/versioned/app.apk"
cp -a "$origin_fixture/downloads/app.exe" "$historical_shared/versioned/app.exe"
touch "$historical_shared/DOWNLOADS_DIR_PRESENT" "$historical_shared/SNAPSHOT_READY" "$historical_shared/PROMOTED"
printf '%s\n%s\n' "$identity_release" "$identity_release" > "$historical_state"
cp "$origin_fixture/baseline.env" "$reconcile_live_env"
cp "$reconcile_live_env" "${reconcile_live_env}.rollback.901-1"
printf '%s\n%s\n' "$identity_release" "$identity_release" > "$reconcile_rollback/deploy-901-1.state"

rm -rf "$origin_fixture/web" "$origin_fixture/downloads/help"
mkdir -p "$origin_fixture/web/assets/nested" "$origin_fixture/downloads/help/assets"
printf 'partial candidate web\n' > "$origin_fixture/web/index.html"
printf 'partial candidate asset\n' > "$origin_fixture/web/assets/nested/data.bin"
printf 'partial candidate help\n' > "$origin_fixture/downloads/help/assets/help.md"
printf 'partial candidate manifest\n' > "$origin_fixture/downloads/latest.json"
printf 'partial candidate page\n' > "$origin_fixture/downloads/download.html"
printf 'partial candidate icon\n' > "$origin_fixture/downloads/opshub-icon-192.png"
printf 'partial candidate apk\n' > "$origin_fixture/downloads/app.apk"
printf 'partial candidate installer\n' > "$origin_fixture/downloads/app.exe"

signal_sudo="$mock_bin/signal-sudo"
signal_marker="$temp/reconcile-hup.marker"
cat > "$signal_sudo" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
command_name="$1"
shift
"$command_name" "$@"
if [ "$command_name" = rm ] && [ ! -e "$MOCK_RECONCILE_SIGNAL_MARKER" ] && \
   [[ " $* " == *" $MOCK_RECONCILE_WEB_DIR "* ]]; then
  : > "$MOCK_RECONCILE_SIGNAL_MARKER"
  kill -HUP "$PPID"
fi
MOCK
chmod +x "$signal_sudo"
export MOCK_RECONCILE_SIGNAL_MARKER="$signal_marker" MOCK_RECONCILE_WEB_DIR="$origin_fixture/web"
export DEPLOY_RUN_ID=901 DEPLOY_RUN_ATTEMPT=1 OPSHUB_SSD_ROOT="$reconcile_ssd" \
  OPSHUB_ENV_FILE="$reconcile_live_env" DOWNLOADS_DIR="$origin_fixture/downloads" \
  WEB_DIR="$origin_fixture/web" APK_NAME=app.apk WINDOWS_INSTALLER_NAME=app.exe \
  WINDOWS_ZIP_NAME='' WINDOWS_CHECKSUM_NAME=''
if OPSHUB_SUDO="$signal_sudo" bash "$root/deploy/home-server/reconcile-production-baseline.sh" \
  "$identity_release" "$origin_fixture/baseline.env" "$reconcile_live_env" \
  "$origin_fixture/current" "$origin_fixture/downloads" "$origin_fixture/web" \
  "$identity_record" >/dev/null 2>&1; then
  echo 'historical shared reconciliation unexpectedly returned success after HUP' >&2
  exit 1
fi
test -e "$signal_marker"
diff -qr "$historical_shared/web" "$origin_fixture/web" >/dev/null
diff -qr "$historical_shared/downloads/help" "$origin_fixture/downloads/help" >/dev/null
for name in latest.json download.html opshub-icon-192.png; do
  cmp "$historical_shared/downloads/$name" "$origin_fixture/downloads/$name"
done
cmp "$historical_shared/versioned/app.apk" "$origin_fixture/downloads/app.apk"
cmp "$historical_shared/versioned/app.exe" "$origin_fixture/downloads/app.exe"
unset MOCK_RECONCILE_SIGNAL_MARKER MOCK_RECONCILE_WEB_DIR DEPLOY_RUN_ID DEPLOY_RUN_ATTEMPT \
  OPSHUB_SSD_ROOT OPSHUB_ENV_FILE DOWNLOADS_DIR WEB_DIR APK_NAME WINDOWS_INSTALLER_NAME \
  WINDOWS_ZIP_NAME WINDOWS_CHECKSUM_NAME
unset MOCK_ORIGIN_MODE MOCK_BASELINE_MODE MOCK_CADDY_HASH MOCK_COMPOSE_FILE

# Runtime rollback uses the existing home-server Compose project. If the target
# recreate fails, it recreates and proves the pre-attempt release before exit.
candidate_sha='1111111111111111111111111111111111111111'
target_sha='2222222222222222222222222222222222222222'
candidate_release="$temp/releases/${candidate_sha}-candidate"
target_release="$temp/releases/${target_sha}-target"
mkdir -p "$candidate_release/deploy/home-server" "$target_release/deploy/home-server" \
  "$target_release/backend-nest" "$target_release/backend-go"
printf 'services: {}\n' > "$candidate_release/deploy/home-server/docker-compose.home.yml"
printf 'services: {}\n' > "$target_release/deploy/home-server/docker-compose.home.yml"
printf 'target caddy\n' > "$target_release/deploy/home-server/Caddyfile"
printf 'target transaction\n' > "$target_release/deploy/home-server/release-transaction.sh"
printf 'target nest\n' > "$target_release/backend-nest/Dockerfile"
printf 'target go\n' > "$target_release/backend-go/Dockerfile"
write_release_manifest "$target_release" "$target_sha"
printf 'OPSHUB_DOMAIN=phongvu.work\nRELEASE=candidate\n' > "$temp/live.env"
printf 'OPSHUB_DOMAIN=opshub.hoanghochoi.com\nRELEASE=target\n' > "$temp/target.env"
ln -s "$candidate_release" "$temp/current"

export MOCK_INVALID_ENV="$temp/live.env"
export MOCK_EXPECT_OPSHUB_ENV_FILE="$temp/target.env"
bash "$root/deploy/home-server/rollback-runtime.sh" \
  "$target_release" "$temp/target.env" "$temp/live.env" "$temp/current"
test "$(readlink -f "$temp/current")" = "$target_release"
grep -Fxq 'RELEASE=target' "$temp/live.env"
test "$(grep -Fc -- '--project-name home-server' "$MOCK_DOCKER_LOG")" -ge 3
! grep -Fq -- '--project-name opshub' "$MOCK_DOCKER_LOG"

unset MOCK_INVALID_ENV MOCK_EXPECT_OPSHUB_ENV_FILE
rm -f "$temp/current"; ln -s "$candidate_release" "$temp/current"
printf 'OPSHUB_DOMAIN=phongvu.work\nRELEASE=candidate\n' > "$temp/live.env"
export MOCK_FAIL_RELEASE="$target_release"
if bash "$root/deploy/home-server/rollback-runtime.sh" \
  "$target_release" "$temp/target.env" "$temp/live.env" "$temp/current"; then
  echo 'injected target runtime rollback failure unexpectedly passed' >&2
  exit 1
fi
unset MOCK_FAIL_RELEASE
test "$(readlink -f "$temp/current")" = "$candidate_release"
grep -Fxq 'RELEASE=candidate' "$temp/live.env"

rm -f "$temp/current"; ln -s "$candidate_release" "$temp/current"
printf 'OPSHUB_DOMAIN=phongvu.work\nRELEASE=candidate\n' > "$temp/live.env"
export MOCK_SIGNAL_RELEASE="$target_release" MOCK_SIGNAL_MARKER="$temp/runtime-signal-marker"
if bash "$root/deploy/home-server/rollback-runtime.sh" \
  "$target_release" "$temp/target.env" "$temp/live.env" "$temp/current"; then
  echo 'runtime rollback unexpectedly returned success after HUP' >&2
  exit 1
fi
unset MOCK_SIGNAL_RELEASE MOCK_SIGNAL_MARKER
if [ "$(readlink -f "$temp/current")" = "$target_release" ]; then
  grep -Fxq 'RELEASE=target' "$temp/live.env"
else
  test "$(readlink -f "$temp/current")" = "$candidate_release"
  grep -Fxq 'RELEASE=candidate' "$temp/live.env"
fi

bash "$root/deploy/home-server/rollback-runtime.sh" \
  "$target_release" "$temp/target.env" "$temp/live.env" "$temp/current"
test "$(readlink -f "$temp/current")" = "$target_release"
grep -Fxq 'RELEASE=target' "$temp/live.env"

echo 'production Tunnel, legacy rollback env, and coherent runtime transaction contract passed'
