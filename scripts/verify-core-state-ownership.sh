#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cli=${HARNESS_CLI:-$root/target/debug/harness-cli}
db=${HARNESS_SOURCE_DB:-$root/harness.db}
ownership="$root/docs/stories/epics/E11-symphony-repository-separation/US-089-separation-boundary-and-frozen-baselines/evidence/durable-ownership-map.json"

fail() {
  printf 'core state ownership failed: %s\n' "$*" >&2
  exit 1
}

for command in jq sqlite3; do
  command -v "$command" >/dev/null 2>&1 || fail "required command is missing: $command"
done
for file in "$cli" "$db" "$ownership"; do
  [[ -e "$file" ]] || fail "missing input: $file"
done

temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
HARNESS_REPO_ROOT="$root" HARNESS_DB_PATH="$db" "$cli" query stories --json >"$temp/stories.json"
HARNESS_REPO_ROOT="$root" HARNESS_DB_PATH="$db" "$cli" query tools --json >"$temp/tools.json"

jq -r '.records[] | select(.table == "story" and .owner == "symphony") | .identity' \
  "$ownership" | LC_ALL=C sort -u >"$temp/forbidden.txt"
jq -r '.result.stories[].id' "$temp/stories.json" | LC_ALL=C sort -u >"$temp/current.txt"
leaked=$(comm -12 "$temp/forbidden.txt" "$temp/current.txt")
[[ -z "$leaked" ]] || fail "database contains Symphony-owned stories: $(tr '\n' ' ' <<<"$leaked" | sed 's/ $//')"

for proxy in US-093 US-094 US-095 US-096; do
  jq -e --arg id "$proxy" '
    [.result.stories[] | select(.id == $id and .status == "implemented" and (.runnable | not))] | length == 1
  ' "$temp/stories.json" >/dev/null || fail "required core receipt proxy is missing or invalid: $proxy"
done

foreign_tools=$(jq -r '.[] | select(.name == "impeccable" or (.name | startswith("web-ui-"))) | .name' \
  "$temp/tools.json" | LC_ALL=C sort -u)
[[ -z "$foreign_tools" ]] ||
  fail "tool registry contains product-owned providers: $(tr '\n' ' ' <<<"$foreign_tools" | sed 's/ $//')"

foreign_backlog=$(sqlite3 "$db" "
  SELECT count(*) FROM backlog
  WHERE status IN ('proposed','accepted') AND lower(
    coalesce(title,'') || ' ' || coalesce(discovered_while,'') || ' ' ||
    coalesce(current_pain,'') || ' ' || coalesce(suggested_improvement,'') || ' ' ||
    coalesce(predicted_impact,'') || ' ' || coalesce(notes,'')
  ) LIKE '%symphony%';
")
[[ "$foreign_backlog" == 0 ]] || fail "active backlog contains Symphony product work"

echo "core state ownership excludes product work and preserves four receipt proxies"
