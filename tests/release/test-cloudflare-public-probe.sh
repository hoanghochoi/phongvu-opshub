#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$ROOT_DIR/deploy/home-server/cloudflare-public-probe.sh"
TMP_DIR="$(mktemp -d)"
BASH_BIN="$(command -v bash)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/bin"

cat > "$TMP_DIR/bin/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
set -euo pipefail
headers_output=''
body_output=''
while (($#)); do
  case "$1" in
    -D)
      headers_output="$2"
      shift 2
      ;;
    -o)
      body_output="$2"
      shift 2
      ;;
    -w)
      shift 2
      ;;
    *) shift ;;
  esac
done
cp "$MOCK_HEADERS_FILE" "$headers_output"
if [[ "$body_output" != '/dev/null' ]]; then
  cp "$MOCK_BODY_FILE" "$body_output"
fi
printf '%s\t%s' "$MOCK_STATUS" "$MOCK_EFFECTIVE_URL"
printf 'curl\n' >> "$MOCK_CURL_LOG"
MOCK_CURL
chmod +x "$TMP_DIR/bin/curl"

printf 'exact-response-body' > "$TMP_DIR/body"

run_probe() {
  local command_name="$1"
  local headers_file="$2"
  local status="$3"
  local effective_url="$4"
  local stdout_file="$5"
  local stderr_file="$6"
  local allowed_hosts_string="${7:-phongvu.work opshub.hoanghochoi.com}"
  local -a allowed_hosts=()
  read -r -a allowed_hosts <<< "$allowed_hosts_string"
  local -a probe_args=("$command_name" 'https://phongvu.work/probe?secret=redacted')
  probe_args+=("${allowed_hosts[@]}")
  set +e
  PATH="$TMP_DIR/bin:$PATH" \
    MOCK_HEADERS_FILE="$headers_file" \
    MOCK_BODY_FILE="$TMP_DIR/body" \
    MOCK_CURL_LOG="$TMP_DIR/curl.log" \
    MOCK_STATUS="$status" \
    MOCK_EFFECTIVE_URL="$effective_url" \
    bash "$PROBE" "${probe_args[@]}" \
      > "$stdout_file" 2> "$stderr_file"
  PROBE_STATUS=$?
  set -e
}

run_streamed_probe() {
  local command_name="$1"
  local headers_file="$2"
  local status="$3"
  local effective_url="$4"
  local stdout_file="$5"
  local stderr_file="$6"
  local allowed_hosts_string="${7:-phongvu.work opshub.hoanghochoi.com}"
  local -a allowed_hosts=()
  read -r -a allowed_hosts <<< "$allowed_hosts_string"
  local -a probe_args=("$command_name" 'https://phongvu.work/probe?secret=redacted')
  probe_args+=("${allowed_hosts[@]}")
  set +e
  PATH="$TMP_DIR/bin:$PATH" \
    MOCK_HEADERS_FILE="$headers_file" \
    MOCK_BODY_FILE="$TMP_DIR/body" \
    MOCK_CURL_LOG="$TMP_DIR/curl.log" \
    MOCK_STATUS="$status" \
    MOCK_EFFECTIVE_URL="$effective_url" \
    "$BASH_BIN" -s -- "${probe_args[@]}" \
      < "$PROBE" > "$stdout_file" 2> "$stderr_file"
  PROBE_STATUS=$?
  set -e
}

assert_failed_without_body() {
  local label="$1"
  if [[ "$PROBE_STATUS" -eq 0 ]]; then
    echo "$label unexpectedly passed." >&2
    exit 1
  fi
  if [[ -s "$TMP_DIR/stdout" ]]; then
    echo "$label emitted a response body on failure." >&2
    exit 1
  fi
}

cat > "$TMP_DIR/403-headers" <<'HEADERS'
HTTP/2 403
server: cloudflare
cf-ray: 1234-SIN

HEADERS
run_probe body "$TMP_DIR/403-headers" 403 'https://phongvu.work/probe' "$TMP_DIR/stdout" "$TMP_DIR/stderr"
assert_failed_without_body '403 with Cloudflare headers'

cat > "$TMP_DIR/missing-server" <<'HEADERS'
HTTP/2 200
cf-ray: 1234-SIN

HEADERS
run_probe body "$TMP_DIR/missing-server" 200 'https://phongvu.work/probe' "$TMP_DIR/stdout" "$TMP_DIR/stderr"
assert_failed_without_body '200 without Server'

cat > "$TMP_DIR/missing-ray" <<'HEADERS'
HTTP/2 200
server: cloudflare

HEADERS
run_probe body "$TMP_DIR/missing-ray" 200 'https://phongvu.work/probe' "$TMP_DIR/stdout" "$TMP_DIR/stderr"
assert_failed_without_body '200 without CF-Ray'

cat > "$TMP_DIR/valid-body" <<'HEADERS'
HTTP/2 200
server: cloudflare
cf-ray: 1234-SIN

HEADERS
run_probe body "$TMP_DIR/valid-body" 200 'https://phongvu.work/probe' "$TMP_DIR/stdout" "$TMP_DIR/stderr"
if [[ "$PROBE_STATUS" -ne 0 ]] || [[ "$(cat "$TMP_DIR/stdout")" != 'exact-response-body' ]]; then
  echo 'Valid Cloudflare body probe did not emit the exact response body.' >&2
  exit 1
fi

run_probe body "$TMP_DIR/valid-body" 200 'https://staging.phongvu.work/probe' "$TMP_DIR/stdout" "$TMP_DIR/stderr"
assert_failed_without_body 'Production body probe reached staging host'

run_probe body "$TMP_DIR/valid-body" 200 'https://phongvu.work:443@evil.example/probe' "$TMP_DIR/stdout" "$TMP_DIR/stderr"
assert_failed_without_body 'Body URL with allowlisted userinfo prefix'

streamed_curl_before="$(wc -l < "$TMP_DIR/curl.log")"
run_streamed_probe body "$TMP_DIR/valid-body" 200 'https://phongvu.work/probe' "$TMP_DIR/stdout" "$TMP_DIR/stderr"
streamed_curl_after="$(wc -l < "$TMP_DIR/curl.log")"
if [[ "$PROBE_STATUS" -ne 0 ]] ||
   [[ "$(cat "$TMP_DIR/stdout")" != 'exact-response-body' ]] ||
   [[ "$streamed_curl_after" -ne $((streamed_curl_before + 1)) ]]; then
  echo 'Streamed Cloudflare body probe did not execute exactly once and emit the exact body.' >&2
  exit 1
fi

cat > "$TMP_DIR/redirect-non-cloudflare" <<'HEADERS'
HTTP/2 302
server: cloudflare
cf-ray: first-SIN
location: https://downloads.example.invalid/file
content-length: 99

HTTP/2 200
server: origin
content-length: 42

HEADERS
run_probe artifact "$TMP_DIR/redirect-non-cloudflare" 200 'https://downloads.example.invalid/file' "$TMP_DIR/stdout" "$TMP_DIR/stderr"
assert_failed_without_body 'Cloudflare redirect to non-Cloudflare final response'

run_streamed_probe artifact "$TMP_DIR/redirect-non-cloudflare" 200 'https://downloads.example.invalid/file' "$TMP_DIR/stdout" "$TMP_DIR/stderr"
assert_failed_without_body 'Streamed Cloudflare redirect to non-Cloudflare final response'

cat > "$TMP_DIR/redirect-cloudflare" <<'HEADERS'
HTTP/2 302
server: cloudflare
cf-ray: first-SIN
location: https://opshub.hoanghochoi.com/file
content-length: 99

HTTP/2 200
server: cloudflare
cf-ray: final-HKG
content-length: 42

HEADERS
run_probe artifact "$TMP_DIR/redirect-cloudflare" 200 'https://phongvu.work:443@evil.example/file' "$TMP_DIR/stdout" "$TMP_DIR/stderr"
assert_failed_without_body 'Artifact URL with allowlisted userinfo prefix'

run_probe artifact "$TMP_DIR/redirect-cloudflare" 200 'https://phongvu.work:8443/file' "$TMP_DIR/stdout" "$TMP_DIR/stderr"
assert_failed_without_body 'Artifact URL with non-contract HTTPS port'

run_probe artifact "$TMP_DIR/redirect-cloudflare" 200 'https://staging.phongvu.work/file' "$TMP_DIR/stdout" "$TMP_DIR/stderr"
assert_failed_without_body 'Production artifact redirected to staging host'

run_probe artifact "$TMP_DIR/redirect-cloudflare" 200 'https://phongvu.work/file' "$TMP_DIR/stdout" "$TMP_DIR/stderr" \
  'staging.phongvu.work opshub-staging.hoanghochoi.com'
assert_failed_without_body 'Staging artifact redirected to production host'

run_probe artifact "$TMP_DIR/redirect-cloudflare" 200 'https://staging.phongvu.work:443/file' "$TMP_DIR/stdout" "$TMP_DIR/stderr" \
  'staging.phongvu.work opshub-staging.hoanghochoi.com'
if [[ "$PROBE_STATUS" -ne 0 ]] || [[ -s "$TMP_DIR/stdout" ]]; then
  echo 'Allowlisted staging host on explicit HTTPS port 443 did not pass.' >&2
  exit 1
fi

run_probe artifact "$TMP_DIR/redirect-cloudflare" 200 'https://opshub.hoanghochoi.com/file' "$TMP_DIR/stdout" "$TMP_DIR/stderr"
if [[ "$PROBE_STATUS" -ne 0 ]] || [[ -s "$TMP_DIR/stdout" ]]; then
  echo 'Allowlisted Cloudflare artifact redirect did not pass cleanly.' >&2
  exit 1
fi

run_probe artifact "$TMP_DIR/redirect-cloudflare" 200 'https://phongvu.work:443/file' "$TMP_DIR/stdout" "$TMP_DIR/stderr"
if [[ "$PROBE_STATUS" -ne 0 ]] || [[ -s "$TMP_DIR/stdout" ]]; then
  echo 'Allowlisted production host on explicit HTTPS port 443 did not pass.' >&2
  exit 1
fi

streamed_curl_before="$(wc -l < "$TMP_DIR/curl.log")"
run_streamed_probe artifact "$TMP_DIR/redirect-cloudflare" 200 'https://opshub.hoanghochoi.com/file' "$TMP_DIR/stdout" "$TMP_DIR/stderr"
streamed_curl_after="$(wc -l < "$TMP_DIR/curl.log")"
if [[ "$PROBE_STATUS" -ne 0 ]] || [[ -s "$TMP_DIR/stdout" ]] ||
   [[ "$streamed_curl_after" -ne $((streamed_curl_before + 1)) ]]; then
  echo 'Streamed allowlisted Cloudflare artifact probe did not execute exactly once.' >&2
  exit 1
fi

cat > "$TMP_DIR/bin/docker" <<'MOCK_DOCKER'
#!/usr/bin/env bash
set -euo pipefail
if IFS= read -r leaked_stdin; then
  echo 'Containerized Node boundary received unexpected stdin.' >&2
  exit 90
fi
printf '%s\n' "$*" > "$MOCK_DOCKER_LOG"
printf 'container-node-result'
MOCK_DOCKER
chmod +x "$TMP_DIR/bin/docker"
container_node_output="$(
  PATH="$TMP_DIR/bin:$PATH" \
    MOCK_DOCKER_LOG="$TMP_DIR/docker.log" \
    OPSHUB_COMPOSE_PROJECT='home-server' \
    OPSHUB_ENV_FILE='/srv/opshub/env' \
    CURRENT_DIR='/srv/opshub/current' \
    bash -c 'source "$1"; opshub_api_node -e "$2" "$3"' \
      _ "$PROBE" 'console.log(JSON.parse(process.argv[1]).error)' '{"error":"invalid_client"}'
)"
if [[ "$container_node_output" != 'container-node-result' ]] ||
   ! grep -Fq 'compose --project-name home-server --env-file /srv/opshub/env -f /srv/opshub/current/deploy/home-server/docker-compose.home.yml exec -T api node -e' "$TMP_DIR/docker.log" ||
   grep -Fq '/tmp/' "$TMP_DIR/docker.log"; then
  echo 'Containerized Node boundary did not preserve the expected Compose, stdin, and argv contract.' >&2
  exit 1
fi

echo 'Cloudflare public body and artifact probe contract PASS'
