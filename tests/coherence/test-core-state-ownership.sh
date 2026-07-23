#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
cli="$root/target/debug/harness-cli"
verify="$root/scripts/verify-core-state-ownership.sh"

cargo build --quiet --manifest-path "$root/Cargo.toml" -p harness-cli --locked
db="$temp/core.db"
HARNESS_REPO_ROOT="$root" HARNESS_DB_PATH="$db" "$cli" init >/dev/null
sqlite3 "$db" <<'SQL'
INSERT INTO story(id,title,risk_lane,status) VALUES
  ('US-093','Receipt 1','high_risk','implemented'),
  ('US-094','Receipt 2','high_risk','implemented'),
  ('US-095','Receipt 3','high_risk','implemented'),
  ('US-096','Receipt 4','high_risk','implemented'),
  ('CORE-1','Core work','normal','planned');
SQL
HARNESS_CLI="$cli" HARNESS_SOURCE_DB="$db" "$verify" >"$temp/pass.out"
grep -Fq 'preserves four receipt proxies' "$temp/pass.out"

story_db="$temp/story.db"
sqlite3 "$db" ".backup '$story_db'"
sqlite3 "$story_db" "INSERT INTO story(id,title,risk_lane,status) VALUES('US-032','Symphony Crate','normal','implemented');"
if HARNESS_CLI="$cli" HARNESS_SOURCE_DB="$story_db" "$verify" >"$temp/story.out" 2>&1; then
  echo "ownership gate unexpectedly accepted a Symphony story" >&2
  exit 1
fi
grep -Fq 'database contains Symphony-owned stories: US-032' "$temp/story.out"

tool_db="$temp/tool.db"
sqlite3 "$db" ".backup '$tool_db'"
sqlite3 "$tool_db" "INSERT INTO tool(name,provider,command,description,responsibility,status) VALUES('web-ui-build','custom','npm','product tool','Verification','unknown');"
if HARNESS_CLI="$cli" HARNESS_SOURCE_DB="$tool_db" "$verify" >"$temp/tool.out" 2>&1; then
  echo "ownership gate unexpectedly accepted a product tool" >&2
  exit 1
fi
grep -Fq 'tool registry contains product-owned providers: web-ui-build' "$temp/tool.out"

empty_db="$temp/empty.db"
HARNESS_REPO_ROOT="$root" HARNESS_DB_PATH="$empty_db" "$cli" init >/dev/null
if HARNESS_CLI="$cli" HARNESS_SOURCE_DB="$empty_db" "$verify" >"$temp/empty.out" 2>&1; then
  echo "ownership gate unexpectedly accepted empty source state" >&2
  exit 1
fi
grep -Fq 'required core receipt proxy is missing or invalid: US-093' "$temp/empty.out"

echo "core ownership positive, foreign-story, product-tool, and empty-state fixtures passed"
