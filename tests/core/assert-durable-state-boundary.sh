#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="${HARNESS_CLI:-$ROOT_DIR/target/debug/harness-cli}"
SOURCE_DB="${HARNESS_SOURCE_DB:-$ROOT_DIR/harness.db}"
OWNERSHIP="$ROOT_DIR/docs/stories/epics/E11-symphony-repository-separation/US-089-separation-boundary-and-frozen-baselines/evidence/durable-ownership-map.json"
POLICY="$ROOT_DIR/docs/provenance/e11-us097-disposition-policy.json"
EVIDENCE_DIR="${US099_EVIDENCE_DIR:-}"

[[ -x "$CLI" ]] || CLI="$ROOT_DIR/scripts/bin/harness-cli"
for command in sqlite3 jq; do
  command -v "$command" >/dev/null || { echo "required command is missing: $command" >&2; exit 1; }
done
for file in "$CLI" "$SOURCE_DB" "$OWNERSHIP" "$POLICY"; do
  test -e "$file" || { echo "durable-boundary input is missing: $file" >&2; exit 1; }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
sqlite3 "$SOURCE_DB" ".backup '$tmp/core.db'"

run() { HARNESS_DB_PATH="$tmp/core.db" "$CLI" "$@"; }
run query stories --json >"$tmp/stories.json"
run query matrix >"$tmp/matrix.txt"
run query backlog --open >"$tmp/backlog.txt"
run query tools --json >"$tmp/tools.json"
run query improvement-health >"$tmp/improvement-health.txt"
run audit >"$tmp/audit.txt"
run propose >"$tmp/propose.txt"

# Frozen product-owned story identities must not survive the fresh core epoch.
jq -r '.records[] | select(.table == "story" and .owner == "symphony") | .identity' "$OWNERSHIP" \
  | LC_ALL=C sort -u >"$tmp/forbidden-story-ids.txt"
jq -r '.result.stories[].id' "$tmp/stories.json" | LC_ALL=C sort -u >"$tmp/current-story-ids.txt"
if comm -12 "$tmp/forbidden-story-ids.txt" "$tmp/current-story-ids.txt" | grep -q .; then
  echo "fresh core retains a Symphony-owned product story" >&2
  comm -12 "$tmp/forbidden-story-ids.txt" "$tmp/current-story-ids.txt" >&2
  exit 1
fi

# Cross-repository receipt proxies are the only target-owned story overlap.
jq -r '.allowed_target_overlap[] | select(.[0] == "story") | .[1]' "$POLICY" \
  | LC_ALL=C sort -u >"$tmp/allowed-proxies.txt"
printf '%s\n' US-093 US-094 US-095 US-096 | LC_ALL=C sort >"$tmp/expected-proxies.txt"
cmp "$tmp/expected-proxies.txt" "$tmp/allowed-proxies.txt" >/dev/null || {
  echo "historical receipt-proxy allowlist changed unexpectedly" >&2; exit 1;
}
while IFS= read -r story_id; do
  jq -e --arg id "$story_id" '
    [.result.stories[] | select(.id == $id and .status == "implemented" and (.runnable | not))] | length == 1
  ' "$tmp/stories.json" >/dev/null || {
    echo "historical receipt proxy is missing, runnable, or incomplete: $story_id" >&2; exit 1;
  }
done <"$tmp/allowed-proxies.txt"

# Automatic work selection is represented by the stable runnable projection.
# It may never return target-owned work or a row bearing active product wording.
jq -e --slurpfile forbidden <(jq -R . <"$tmp/forbidden-story-ids.txt" | jq -s .) '
  [.result.stories[] | select(.runnable) |
    select((.id as $id | $forbidden[0] | index($id)) != null or (.title | test("symphony"; "i")))] | length == 0
' "$tmp/stories.json" >/dev/null || {
  echo "automatic selection contains active Symphony work" >&2; exit 1;
}

# Product backlog occurrences and UI/design providers are never core state.
for backlog_id in 10 11 12 14; do
  test "$(sqlite3 "$tmp/core.db" "SELECT count(*) FROM backlog WHERE id=$backlog_id;")" = 0 || {
    echo "source Symphony backlog occurrence remains active: $backlog_id" >&2; exit 1;
  }
done
test "$(sqlite3 "$tmp/core.db" "
  SELECT count(*) FROM backlog
  WHERE status='proposed' AND lower(
    coalesce(title,'') || ' ' || coalesce(discovered_while,'') || ' ' ||
    coalesce(current_pain,'') || ' ' || coalesce(suggested_improvement,'') || ' ' ||
    coalesce(predicted_impact,'') || ' ' || coalesce(notes,'')
  ) LIKE '%symphony%';
")" = 0 || { echo "active backlog contains Symphony product wording" >&2; exit 1; }
test "$(sqlite3 "$tmp/core.db" "SELECT count(*) FROM tool WHERE name IN ('impeccable','web-ui-build','web-ui-e2e','web-ui-desktop-smoke') OR lower(command||' '||description||' '||coalesce(scan_target,'')) LIKE '%symphony%';")" = 0 || {
  echo "core tool registry contains a Symphony/UI provider" >&2; exit 1;
}
jq -e '[.[] | select(.source == "registered") | select(.name == "impeccable" or (.name | startswith("web-ui-")) or (.command | test("symphony";"i")))] | length == 0' "$tmp/tools.json" >/dev/null

# During a story's own verification its configured command may intentionally
# not yet be recorded as passing. US-099 is the historical default; a caller
# may name exactly one current self-verifying story through
# ALLOW_AUDIT_STORY_ID. Normal completion reduces the score from 5 to zero.
allowed_audit_story_id="${ALLOW_AUDIT_STORY_ID:-US-099}"
allowed_audit_story_title="$(jq -r --arg id "$allowed_audit_story_id" '.result.stories[] | select(.id == $id) | .title' "$tmp/stories.json")"
test -n "$allowed_audit_story_title" || {
  echo "allowed audit story is missing: $allowed_audit_story_id" >&2; exit 1;
}
audit_score="$(sed -n 's/^Entropy score: \([0-9][0-9]*\)\/100.*/\1/p' "$tmp/audit.txt")"
[[ "$audit_score" =~ ^[0-9]+$ && "$audit_score" -le 5 ]] || {
  echo "core audit has unexpected entropy" >&2; cat "$tmp/audit.txt" >&2; exit 1;
}
unexpected_audit_rows="$(grep -E '^  - ' "$tmp/audit.txt" | grep -Fv "$allowed_audit_story_id: $allowed_audit_story_title" || true)"
test -z "$unexpected_audit_rows" || {
  echo "core audit contains a finding other than $allowed_audit_story_id" >&2; printf '%s\n' "$unexpected_audit_rows" >&2; exit 1;
}
for output in "$tmp/backlog.txt" "$tmp/improvement-health.txt" "$tmp/audit.txt" "$tmp/propose.txt"; do
  if grep -Eiq 'symphony|web-ui-(build|e2e|desktop)|electron|playwright|impeccable' "$output"; then
    echo "core query leaked an active product/provider reference: $output" >&2
    exit 1
  fi
done

if [[ -n "$EVIDENCE_DIR" ]]; then
  mkdir -p "$EVIDENCE_DIR"
  cp "$tmp/matrix.txt" "$EVIDENCE_DIR/matrix.txt"
  cp "$tmp/backlog.txt" "$EVIDENCE_DIR/backlog-open.txt"
  cp "$tmp/audit.txt" "$EVIDENCE_DIR/audit.txt"
  cp "$tmp/propose.txt" "$EVIDENCE_DIR/propose.txt"
  cp "$tmp/improvement-health.txt" "$EVIDENCE_DIR/improvement-health.txt"
  cp "$tmp/tools.json" "$EVIDENCE_DIR/tools.json"
  jq '{operation,protocol_version,result:{stories:[.result.stories[] | select(.runnable or (.id | test("^US-09[3-6]$")))]}}' \
    "$tmp/stories.json" >"$EVIDENCE_DIR/selection-and-proxies.json"
fi

echo "core durable-state boundary excludes product work and preserves four completed receipt proxies"
