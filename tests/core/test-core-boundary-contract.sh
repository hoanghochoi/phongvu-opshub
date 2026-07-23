#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_TEST="$ROOT_DIR/tests/core/assert-durable-state-boundary.sh"
COMMAND_TEST="$ROOT_DIR/tests/core/assert-command-contract.sh"
CLI="${HARNESS_CLI:-$ROOT_DIR/target/debug/harness-cli}"
[[ -x "$CLI" ]] || CLI="$ROOT_DIR/scripts/bin/harness-cli"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$STATE_TEST" >/dev/null
"$COMMAND_TEST" >/dev/null

cp "$ROOT_DIR/tests/core/harness-command-contract.txt" "$TMP/missing-command.txt"
printf '%s\n' 'removed-product-command' >>"$TMP/missing-command.txt"
if HARNESS_COMMAND_CONTRACT="$TMP/missing-command.txt" "$COMMAND_TEST" >"$TMP/command.out" 2>&1; then
  echo "command contract accepted a missing public command" >&2; exit 1
fi
grep -Fq 'public command is missing' "$TMP/command.out"

make_db() { sqlite3 "$ROOT_DIR/harness.db" ".backup '$1'"; }

make_db "$TMP/story.db"
sqlite3 "$TMP/story.db" "UPDATE story SET id='US-032' WHERE id='US-001';"
if HARNESS_SOURCE_DB="$TMP/story.db" HARNESS_CLI="$CLI" "$STATE_TEST" >"$TMP/story.out" 2>&1; then
  echo "durable boundary accepted a Symphony-owned story" >&2; exit 1
fi
grep -Fq 'fresh core retains a Symphony-owned product story' "$TMP/story.out"

make_db "$TMP/backlog.db"
sqlite3 "$TMP/backlog.db" "UPDATE backlog SET id=10, title='Symphony fixture' WHERE id=3;"
if HARNESS_SOURCE_DB="$TMP/backlog.db" HARNESS_CLI="$CLI" "$STATE_TEST" >"$TMP/backlog.out" 2>&1; then
  echo "durable boundary accepted a Symphony backlog occurrence" >&2; exit 1
fi
grep -Fq 'source Symphony backlog occurrence remains active' "$TMP/backlog.out"

make_db "$TMP/tool.db"
sqlite3 "$TMP/tool.db" "UPDATE tool SET name='web-ui-build' WHERE name='cargo-workspace-tests';"
if HARNESS_SOURCE_DB="$TMP/tool.db" HARNESS_CLI="$CLI" "$STATE_TEST" >"$TMP/tool.out" 2>&1; then
  echo "durable boundary accepted a product UI provider" >&2; exit 1
fi
grep -Fq 'core tool registry contains a Symphony/UI provider' "$TMP/tool.out"

echo "core command and durable-state boundary negative fixtures passed"
