#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_FIXTURE_ROOT="$ROOT_DIR/tests/fixtures/changesets/generic-rebuild"
CHANGESET_DIR="${HARNESS_CHANGESET_DIR:-$DEFAULT_FIXTURE_ROOT/positive}"
EXPECTED_FILE="${HARNESS_CHANGESET_EXPECTED:-$DEFAULT_FIXTURE_ROOT/expected.json}"

select_harness_cli() {
  local root_dir="$1"
  if [[ -n "${HARNESS_CLI:-}" ]]; then
    printf '%s\n' "$HARNESS_CLI"
    return
  fi
  if [[ "${HARNESS_VALIDATOR_SKIP_BUILD:-0}" != "1" ]]; then
    cargo build --quiet --manifest-path "$root_dir/Cargo.toml" -p harness-cli
  fi
  printf '%s\n' "$root_dir/target/debug/harness-cli"
}

proof_is_valid() {
  local database="$1"
  local story_id="$2"
  [[ "$(sqlite3 "$database" "
    SELECT CASE WHEN last_verified_result='pass'
      AND length(last_verified_at)=19
      AND last_verified_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]'
      AND datetime(last_verified_at)=last_verified_at
    THEN 1 ELSE 0 END
    FROM story WHERE id='$story_id';")" == "1" ]]
}

assert_json_equal() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  local expected_canonical actual_canonical
  expected_canonical="$(jq -cS . <<<"$expected")"
  actual_canonical="$(jq -cS . <<<"$actual")"
  if [[ "$actual_canonical" != "$expected_canonical" ]]; then
    echo "generic rebuild mismatch: $label" >&2
    echo "expected: $expected_canonical" >&2
    echo "actual:   $actual_canonical" >&2
    exit 1
  fi
}

if [[ "${HARNESS_VALIDATOR_LIBRARY_ONLY:-0}" == "1" ]]; then
  return 0 2>/dev/null || exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fixtures)
      [[ $# -ge 2 ]] || { echo "--fixtures requires a directory" >&2; exit 2; }
      CHANGESET_DIR="$2"
      shift 2
      ;;
    --expected)
      [[ $# -ge 2 ]] || { echo "--expected requires a file" >&2; exit 2; }
      EXPECTED_FILE="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

for command in jq sqlite3; do
  command -v "$command" >/dev/null 2>&1 || { echo "required command not found: $command" >&2; exit 1; }
done
[[ -d "$CHANGESET_DIR" ]] || { echo "changeset fixture directory not found: $CHANGESET_DIR" >&2; exit 1; }
[[ -f "$EXPECTED_FILE" ]] || { echo "expected fixture manifest not found: $EXPECTED_FILE" >&2; exit 1; }

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
FIXTURE_REPO="$TMP_DIR/repo"
mkdir -p "$FIXTURE_REPO/scripts"
cp -R "$ROOT_DIR/scripts/schema" "$FIXTURE_REPO/scripts/schema"
FIXTURE_DB="$FIXTURE_REPO/harness.db"
HARNESS_CLI="$(select_harness_cli "$ROOT_DIR")"
if [[ ! -x "$HARNESS_CLI" ]]; then
  echo "Harness CLI not found; build it with: cargo build -p harness-cli" >&2
  exit 1
fi

echo "rebuild validator executable: $HARNESS_CLI"
echo "rebuild validator fixtures: $CHANGESET_DIR"

rebuild_output="$(HARNESS_REPO_ROOT="$FIXTURE_REPO" HARNESS_DB_PATH="$FIXTURE_DB" "$HARNESS_CLI" db rebuild --from "$CHANGESET_DIR")"

expected_schema="$(jq -r '.schema_version' "$EXPECTED_FILE")"
expected_changesets="$(jq -r '.changesets' "$EXPECTED_FILE")"
expected_operations="$(jq -r '.operations' "$EXPECTED_FILE")"
actual_schema="$(sqlite3 "$FIXTURE_DB" 'SELECT MAX(version) FROM schema_version;')"
[[ "$actual_schema" == "$expected_schema" ]] || { echo "expected schema $expected_schema, got $actual_schema" >&2; exit 1; }
grep -Fq "$expected_changesets changeset(s)" <<<"$rebuild_output"
grep -Fq "$expected_operations operation(s)" <<<"$rebuild_output"

actual_stories="$(sqlite3 -json "$FIXTURE_DB" "SELECT id,status,unit_proof,integration_proof,e2e_proof,platform_proof,evidence,verify_command FROM story ORDER BY id;")"
assert_json_equal stories "$(jq -c '.stories' "$EXPECTED_FILE")" "$actual_stories"

verification_id="$(jq -r '.verification.id' "$EXPECTED_FILE")"
proof_is_valid "$FIXTURE_DB" "$verification_id"
actual_verification="$(sqlite3 -json "$FIXTURE_DB" "SELECT id,last_verified_result AS result,last_verified_at AS verified_at FROM story WHERE id='$verification_id';")"
assert_json_equal verification "[$(jq -c '.verification' "$EXPECTED_FILE")]" "$actual_verification"

actual_dependencies="$(sqlite3 -json "$FIXTURE_DB" "SELECT story_id AS blocker,blocks_story_id AS blocked FROM story_dependency ORDER BY story_id,blocks_story_id;")"
assert_json_equal dependencies "$(jq -c '.dependencies' "$EXPECTED_FILE")" "$actual_dependencies"
actual_hierarchy="$(sqlite3 -json "$FIXTURE_DB" "SELECT parent_story_id AS parent,child_story_id AS child FROM story_hierarchy ORDER BY parent_story_id,child_story_id;")"
assert_json_equal hierarchy "$(jq -c '.hierarchy' "$EXPECTED_FILE")" "$actual_hierarchy"

actual_tools="$(sqlite3 -json "$FIXTURE_DB" "SELECT name,status,kind,capability FROM tool ORDER BY name;")"
assert_json_equal retained-tools "$(jq -c '.retained_tools' "$EXPECTED_FILE")" "$actual_tools"
while IFS= read -r removed_tool; do
  [[ "$(sqlite3 "$FIXTURE_DB" "SELECT COUNT(*) FROM tool WHERE name='$removed_tool';")" == "0" ]]
done < <(jq -r '.removed_tools[]' "$EXPECTED_FILE")

actual_remap="$(sqlite3 -json "$FIXTURE_DB" "SELECT (SELECT COUNT(*) FROM intake) AS intakes,(SELECT COUNT(*) FROM trace) AS traces,(SELECT COUNT(DISTINCT intake_id) FROM trace) AS distinct_trace_intake_ids,(SELECT COUNT(*) FROM trace JOIN intake ON intake.id=trace.intake_id) AS closed_trace_intake_links;")"
assert_json_equal local-id-remap "[$(jq -c '.remap' "$EXPECTED_FILE")]" "$actual_remap"

actual_run_ids="$(sqlite3 -json "$FIXTURE_DB" "SELECT id FROM changeset_applied ORDER BY id;" | jq -c '[.[].id]')"
assert_json_equal applied-run-ids "$(jq -c '.run_ids' "$EXPECTED_FILE")" "$actual_run_ids"
missing_sha="$(sqlite3 "$FIXTURE_DB" "SELECT COUNT(*) FROM changeset_applied WHERE content_sha256 IS NULL OR length(content_sha256)<>64;")"
[[ "$missing_sha" == "0" ]] || { echo "applied fixtures must retain exact content SHA-256" >&2; exit 1; }

before="$(sqlite3 "$FIXTURE_DB" "SELECT (SELECT COUNT(*) FROM story)||'|'||(SELECT COUNT(*) FROM story_dependency)||'|'||(SELECT COUNT(*) FROM story_hierarchy)||'|'||(SELECT COUNT(*) FROM intake)||'|'||(SELECT COUNT(*) FROM trace)||'|'||(SELECT COUNT(*) FROM tool)||'|'||(SELECT COUNT(*) FROM changeset_applied);")"
while IFS= read -r fixture; do
  second_apply="$(HARNESS_REPO_ROOT="$FIXTURE_REPO" HARNESS_DB_PATH="$FIXTURE_DB" "$HARNESS_CLI" db changeset apply "$fixture")"
  grep -Fq 'already applied; skipped' <<<"$second_apply"
done < <(find "$CHANGESET_DIR" -maxdepth 1 -type f -name '*.changeset.jsonl' -print | sort)
after="$(sqlite3 "$FIXTURE_DB" "SELECT (SELECT COUNT(*) FROM story)||'|'||(SELECT COUNT(*) FROM story_dependency)||'|'||(SELECT COUNT(*) FROM story_hierarchy)||'|'||(SELECT COUNT(*) FROM intake)||'|'||(SELECT COUNT(*) FROM trace)||'|'||(SELECT COUNT(*) FROM tool)||'|'||(SELECT COUNT(*) FROM changeset_applied);")"
[[ "$before" == "$after" ]] || { echo "idempotent replay changed generic fixture state" >&2; exit 1; }

echo "generic changeset rebuild passed: $expected_changesets fixtures, $expected_operations operations"
