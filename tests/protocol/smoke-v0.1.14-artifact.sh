#!/usr/bin/env bash
set -euo pipefail

# Frozen compatibility contract for the immutable initial protocol release.
# Do not add current behavior here; current candidates use smoke-native-artifact.sh.
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
baseline_commit=d2f89eeabe8d01df95fd19cd6ba981b01a71730f
artifact=${1:?usage: $0 <harness-cli-v0.1.14-artifact>}
artifact=$(cd "$(dirname "$artifact")" && pwd)/$(basename "$artifact")
actual_version=$($artifact --version)
[[ "$actual_version" == "harness-cli 0.1.14" ]] || {
  echo "frozen v0.1.14 smoke received the wrong binary: $actual_version" >&2
  exit 1
}

git -C "$repo_root" cat-file -e "$baseline_commit^{commit}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git -C "$repo_root" archive --format=tar "$baseline_commit" scripts/schema |
  tar -xf - -C "$tmp"
db="$tmp/harness.db"

run() {
  HARNESS_REPO_ROOT="$tmp" HARNESS_DB_PATH="$db" "$artifact" "$@"
}

run query contract --json >"$tmp/contract.json"
jq -e '
  .protocol_version == 1 and
  .operation == "query.contract" and
  .result.cli_version == "0.1.14" and
  .result.schema_maximum == 13 and
  .result.database_state == "missing"
' "$tmp/contract.json" >/dev/null
test ! -e "$db"

run init >/dev/null
run story add --id US-A --title Alpha --lane normal --verify true --json >"$tmp/add-a.json"
run story add --id US-B --title Beta --lane normal --verify true --json >"$tmp/add-b.json"
jq -e '.result.changed and .result.story.id == "US-A"' "$tmp/add-a.json" >/dev/null

run story dependency add --blocker US-A --blocked US-B --json >/dev/null
run story hierarchy add --parent US-A --child US-B --json >/dev/null
run query work-graph --json >"$tmp/graph-before.json"
jq -e '
  (.result.revision | length) == 64 and
  (.result.stories[] | select(.id == "US-A").runnable) == true and
  (.result.stories[] | select(.id == "US-B").runnable) == false and
  .result.dependencies == [{"blocker":"US-A","blocked":"US-B"}] and
  .result.hierarchy == [{"parent":"US-A","child":"US-B"}]
' "$tmp/graph-before.json" >/dev/null

# This direct transition is historical v0.1.14 behavior, not a current rule.
run story update --id US-A --status implemented --expected-status planned \
  --require-runnable --json >"$tmp/cas.json"
jq -e '
  .result.before_status == "planned" and
  .result.after_status == "implemented" and
  .result.runnable_before
' "$tmp/cas.json" >/dev/null
run query stories --json |
  jq -e '(.result.stories[] | select(.id == "US-B").runnable) == true' >/dev/null

set +e
run story hierarchy add --parent US-B --child US-A --json >"$tmp/conflict.json"
conflict_exit=$?
set -e
test "$conflict_exit" -eq 3
jq -e '.error.code == "CONFLICT" and .operation == "story.hierarchy.add"' \
  "$tmp/conflict.json" >/dev/null

changeset="$tmp/protocol-smoke.jsonl"
printf '%s\n' '{"base_schema_version":13,"op":"changeset.header","run_id":"protocol_smoke","version":1}' >"$changeset"
run db changeset status "$changeset" --json |
  jq -e '.result.applied == false and .result.operation_count == 0' >/dev/null
run db changeset apply "$changeset" --json |
  jq -e '.result.applied == true and .result.operations == 0 and (.result.content_sha256 | length) == 64' >/dev/null
run db changeset status "$changeset" --json |
  jq -e '.result.applied == true' >/dev/null

snapshot="$tmp/path with spaces/snapshot.db"
mkdir -p "$(dirname "$snapshot")"
run db snapshot --output "$snapshot" --json >"$tmp/snapshot.json"
jq -e --arg output "$snapshot" '
  .result.output == $output and
  (.result.snapshot_file_sha256 | length) == 64 and
  (.result.source_logical_sha256 | length) == 64
' "$tmp/snapshot.json" >/dev/null
HARNESS_REPO_ROOT="$tmp" HARNESS_DB_PATH="$snapshot" "$artifact" query contract --json |
  jq -e '.result.database_state == "current"' >/dev/null

echo "frozen harness-cli v0.1.14 protocol smoke passed"
