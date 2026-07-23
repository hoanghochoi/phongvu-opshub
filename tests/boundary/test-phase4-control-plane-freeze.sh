#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cli=${HARNESS_CLI:-$root/target/debug/harness-cli}
[[ -x "$cli" ]] || {
  echo "Phase 4 boundary test requires a built Harness CLI: $cli" >&2
  exit 1
}

temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT

prepare_schema() {
  local fixture=$1
  mkdir -p "$fixture/scripts/schema"
  cp "$root"/scripts/schema/*.sql "$fixture/scripts/schema/"
}

source_fixture="$temp/source"
prepare_schema "$source_fixture"
mkdir -p "$source_fixture/crates/harness-cli"
printf '[workspace]\n' >"$source_fixture/Cargo.toml"
printf '[package]\nname = "harness-cli"\nversion = "0.0.0"\n' \
  >"$source_fixture/crates/harness-cli/Cargo.toml"

run_source() {
  HARNESS_REPO_ROOT="$source_fixture" "$cli" "$@"
}

run_source init >/dev/null

set +e
run_source intake --type change_request --summary "accidental source write" \
  --lane normal >"$temp/frozen.out" 2>"$temp/frozen.err"
frozen_exit=$?
set -e
[[ "$frozen_exit" -eq 1 ]]
grep -Fq "lifecycle write 'intake' is frozen" "$temp/frozen.err"
grep -Fq -- '--compatibility-write' "$temp/frozen.err"
[[ $(sqlite3 "$source_fixture/harness.db" 'SELECT COUNT(*) FROM intake;') -eq 0 ]]
[[ ! -e "$source_fixture/.harness/changesets" ]]

run_source --compatibility-write intake --type change_request \
  --summary "explicit compatibility maintenance" --lane normal \
  >"$temp/explicit.out" 2>"$temp/explicit.err"
grep -Fq 'Intake #1 recorded.' "$temp/explicit.out"
grep -Fq "explicitly selected compatibility write 'intake'" "$temp/explicit.err"
[[ $(sqlite3 "$source_fixture/harness.db" 'SELECT COUNT(*) FROM intake;') -eq 1 ]]
[[ $(find "$source_fixture/.harness/changesets" -maxdepth 1 -type f | wc -l) -eq 1 ]]

# Protocol-v1 JSON is retained even when it targets the source default DB.
run_source story add --id MACHINE-1 --title "Protocol consumer" --lane normal \
  --verify true --json >"$temp/machine.json" 2>"$temp/machine.err"
jq -e '.operation == "story.add" and .result.story.id == "MACHINE-1"' \
  "$temp/machine.json" >/dev/null
[[ ! -s "$temp/machine.err" ]]

# Explicit database selection is already compatibility intent.
isolated_db="$source_fixture/isolated.db"
HARNESS_REPO_ROOT="$source_fixture" HARNESS_DB_PATH="$isolated_db" \
  "$cli" init >/dev/null
HARNESS_REPO_ROOT="$source_fixture" HARNESS_DB_PATH="$isolated_db" \
  "$cli" intake --type change_request --summary "isolated fixture" \
  --lane normal >/dev/null
[[ $(sqlite3 "$isolated_db" 'SELECT COUNT(*) FROM intake;') -eq 1 ]]

# An installed consumer has no source markers and retains its local lifecycle.
consumer_fixture="$temp/consumer"
prepare_schema "$consumer_fixture"
HARNESS_REPO_ROOT="$consumer_fixture" "$cli" init >/dev/null
HARNESS_REPO_ROOT="$consumer_fixture" "$cli" intake --type change_request \
  --summary "consumer-local lifecycle" --lane normal >/dev/null
[[ $(sqlite3 "$consumer_fixture/harness.db" 'SELECT COUNT(*) FROM intake;') -eq 1 ]]

# Reads and maintenance stay available without compatibility-write.
run_source query intakes >"$temp/intakes.out" 2>"$temp/intakes.err"
grep -Fq 'explicit compatibility maintenance' "$temp/intakes.out"
[[ ! -s "$temp/intakes.err" ]]
run_source migrate >"$temp/migrate.out" 2>"$temp/migrate.err"
[[ ! -s "$temp/migrate.err" ]]

echo "Phase 4 source-write freeze, explicit intent, protocol, isolation, and read boundaries passed"
