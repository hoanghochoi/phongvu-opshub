#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
fingerprint="$root/deploy/staging/release-fingerprint.sh"
workflow="$root/.github/workflows/deploy-opshub-staging.yml"

bash -n "$fingerprint"

temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT

mkdir -p "$temp/releases/old/deploy/home-server" \
  "$temp/releases/old/docs/help" \
  "$temp/downloads/help/assets" \
  "$temp/web"
printf 'env\n' > "$temp/env"
printf 'web\n' > "$temp/web/index.html"
printf 'help\n' > "$temp/downloads/help/assets/page.md"
printf 'runtime help\n' > "$temp/releases/old/docs/help/page.md"
printf 'caddy\n' > "$temp/releases/old/deploy/home-server/Caddyfile"
printf 'manifest\n' > "$temp/downloads/latest.json"
printf 'download\n' > "$temp/downloads/download.html"
printf 'icon\n' > "$temp/downloads/opshub-icon-192.png"
printf 'apk\n' > "$temp/downloads/phongvu-opshub-staging-v1.apk"

export OPSHUB_SUDO=''
export CURRENT_DIR="$temp/releases/old"
export OPSHUB_ENV_FILE="$temp/env"
export DOWNLOADS_DIR="$temp/downloads"
export WEB_DIR="$temp/web"

before=$(bash "$fingerprint")
after=$(bash "$fingerprint")
test "$before" = "$after"
grep -Fq "current_release=$temp/releases/old" <<<"$before"

printf 'changed\n' > "$temp/downloads/latest.json"
changed=$(bash "$fingerprint")
test "$before" != "$changed"

grep -Fq 'failure_injection:' "$workflow"
grep -Fq 'after_shared_promotion' "$workflow"
grep -Fq 'after_runtime_switch' "$workflow"
grep -Fq 'public_verification' "$workflow"
grep -Fq 'static_transaction' "$workflow"
grep -Fq 'Capture controlled rollback baseline' "$workflow"
grep -Fq 'Rehearse shared static transaction (staging-only)' "$workflow"
grep -Fq 'Verify controlled staging rollback' "$workflow"

baseline_line=$(grep -n 'name: Capture controlled rollback baseline' "$workflow" | cut -d: -f1)
deploy_job_line=$(grep -n '^  deploy:$' "$workflow" | cut -d: -f1)
artifact_verify_line=$(grep -n 'name: Verify staged client artifacts' "$workflow" | cut -d: -f1)
deploy_line=$(grep -n 'name: Deploy staging backend and publish version metadata' "$workflow" | cut -d: -f1)
rollback_line=$(grep -n 'name: Roll back staging after failed release verification' "$workflow" | cut -d: -f1)
verify_line=$(grep -n 'name: Verify controlled staging rollback' "$workflow" | cut -d: -f1)
test "$(grep -c 'name: Capture controlled rollback baseline' "$workflow")" -eq 1
test "$deploy_job_line" -lt "$baseline_line"
test "$baseline_line" -lt "$artifact_verify_line"
test "$baseline_line" -lt "$deploy_line"
test "$rollback_line" -lt "$verify_line"

echo 'staging release fingerprint and workflow-dispatch failpoint contract passed'
