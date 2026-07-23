#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
crate_manifest=${HARNESS_COHERENCE_CRATE_MANIFEST:-$root/crates/harness-cli/Cargo.toml}
lockfile=${HARNESS_COHERENCE_LOCKFILE:-$root/Cargo.lock}
release_tag_file=${HARNESS_COHERENCE_RELEASE_TAG_FILE:-$root/scripts/harness-cli-release-tag}
schema_dir=${HARNESS_COHERENCE_SCHEMA_DIR:-$root/scripts/schema}
command_manifest=${HARNESS_COHERENCE_COMMAND_MANIFEST:-$root/tests/core/harness-command-contract.txt}

fail() {
  printf 'revision coherence failed: %s\n' "$*" >&2
  exit 1
}

for file in "$crate_manifest" "$lockfile" "$release_tag_file" "$command_manifest"; do
  [[ -f "$file" ]] || fail "missing input: $file"
done
[[ -d "$schema_dir" ]] || fail "missing schema directory: $schema_dir"

crate_version=$(awk -F'"' '/^version = / { print $2; exit }' "$crate_manifest")
lock_version=$(awk -F'"' '
  $0 == "name = \"harness-cli\"" { package = 1; next }
  package && /^version = / { print $2; exit }
' "$lockfile")
release_tag=$(awk 'NF && $1 !~ /^#/ { print $1; exit }' "$release_tag_file")

[[ -n "$crate_version" ]] || fail "could not read Harness CLI crate version"
[[ "$lock_version" == "$crate_version" ]] ||
  fail "Cargo.lock version $lock_version does not match crate version $crate_version"
[[ "$release_tag" == "harness-cli-v$crate_version" ]] ||
  fail "pinned release $release_tag does not match crate version $crate_version"

schema_files=()
while IFS= read -r file; do schema_files+=("$file"); done < <(
  find "$schema_dir" -maxdepth 1 -type f -name '*.sql' -print | LC_ALL=C sort
)
[[ ${#schema_files[@]} -gt 0 ]] || fail "no schema migrations found"
for ((index=0; index<${#schema_files[@]}; index++)); do
  printf -v expected '%03d-' "$((index + 1))"
  actual=$(basename "${schema_files[$index]}")
  [[ "$actual" == "$expected"* ]] ||
    fail "schema sequence gap: expected prefix $expected, found $actual"
done
schema_maximum=${#schema_files[@]}

if [[ ${HARNESS_COHERENCE_SKIP_RUNTIME:-0} == 1 ]]; then
  printf 'revision metadata coherent: cli=%s schema=001-%03d\n' "$crate_version" "$schema_maximum"
  exit 0
fi

for command in cargo jq sqlite3 rg; do
  command -v "$command" >/dev/null 2>&1 || fail "required command is missing: $command"
done
cargo build --quiet --manifest-path "$root/Cargo.toml" -p harness-cli --locked
cli=${HARNESS_COHERENCE_CLI:-$root/target/debug/harness-cli}
[[ -x "$cli" ]] || fail "Harness CLI is not executable: $cli"

temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
missing_db="$temp/missing.db"
contract=$(HARNESS_REPO_ROOT="$root" HARNESS_DB_PATH="$missing_db" "$cli" query contract --json)
[[ ! -e "$missing_db" ]] || fail "contract discovery created the missing database"
jq -e --arg version "$crate_version" --argjson maximum "$schema_maximum" '
  .protocol_version == 1 and
  .result.protocol_version == 1 and
  .result.cli_version == $version and
  .result.schema_minimum == 1 and
  .result.schema_maximum == $maximum and
  .result.database_state == "missing" and
  .result.database_schema_version == null
' <<<"$contract" >/dev/null || fail "source CLI contract does not match revision metadata"

HARNESS_CLI="$cli" HARNESS_DB_PATH="$temp/bootstrap.db" "$root/scripts/bootstrap-harness.sh" >/dev/null
current_contract=$(HARNESS_REPO_ROOT="$root" HARNESS_DB_PATH="$temp/bootstrap.db" "$cli" query contract --json)
jq -e --argjson maximum "$schema_maximum" '
  .result.database_state == "current" and
  .result.database_schema_version == $maximum
' <<<"$current_contract" >/dev/null || fail "bootstrap did not produce a current database"

HARNESS_CLI="$cli" \
HARNESS_SCHEMA_DIR="$schema_dir" \
HARNESS_COMMAND_MANIFEST="$command_manifest" \
  "$root/tests/core/assert-schema-replay-command-contract.sh" >/dev/null

printf 'revision coherent: cli=%s protocol=1 schema=001-%03d bootstrap=current commands=present\n' \
  "$crate_version" "$schema_maximum"
