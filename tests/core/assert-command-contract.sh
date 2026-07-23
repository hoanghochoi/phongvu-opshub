#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTRACT="${HARNESS_COMMAND_CONTRACT:-$ROOT_DIR/tests/core/harness-command-contract.txt}"
BEFORE_CLI="${HARNESS_BEFORE_CLI:-$ROOT_DIR/scripts/bin/harness-cli}"
AFTER_CLI="${HARNESS_AFTER_CLI:-$ROOT_DIR/target/debug/harness-cli}"
EVIDENCE_DIR="${US099_EVIDENCE_DIR:-}"

if [[ ! -x "$AFTER_CLI" ]]; then
  AFTER_CLI="$BEFORE_CLI"
fi
for file in "$CONTRACT" "$BEFORE_CLI" "$AFTER_CLI"; do
  test -e "$file" || { echo "command-contract input is missing: $file" >&2; exit 1; }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

capture() {
  local cli="$1" output="$2" command_line
  : >"$output"
  while IFS= read -r command_line; do
    [[ -z "$command_line" || "$command_line" == \#* ]] && continue
    read -r -a parts <<<"$command_line"
    if ! "$cli" "${parts[@]}" --help >"$tmp/help.out" 2>"$tmp/help.err"; then
      echo "public command is missing from $cli: $command_line" >&2
      cat "$tmp/help.err" >&2
      return 1
    fi
    printf '%s\n' "$command_line" >>"$output"
  done <"$CONTRACT"
}

capture "$BEFORE_CLI" "$tmp/before.txt"
capture "$AFTER_CLI" "$tmp/after.txt"
cmp "$tmp/before.txt" "$tmp/after.txt" >/dev/null || {
  echo "before/after Harness command manifests differ" >&2
  diff -u "$tmp/before.txt" "$tmp/after.txt" >&2 || true
  exit 1
}

before_contract="$(HARNESS_DB_PATH="$ROOT_DIR/harness.db" "$BEFORE_CLI" query contract --json)"
after_contract="$(HARNESS_DB_PATH="$ROOT_DIR/harness.db" "$AFTER_CLI" query contract --json)"
before_capabilities="$(jq -cS '.result.capabilities' <<<"$before_contract")"
after_capabilities="$(jq -cS '.result.capabilities' <<<"$after_contract")"
test "$before_capabilities" = "$after_capabilities" || {
  echo "before/after protocol capabilities differ" >&2; exit 1;
}

if [[ -n "$EVIDENCE_DIR" ]]; then
  mkdir -p "$EVIDENCE_DIR"
  jq -n \
    --arg before_cli "$BEFORE_CLI" --arg after_cli "$AFTER_CLI" \
    --arg before_sha "$(shasum -a 256 "$BEFORE_CLI" | awk '{print $1}')" \
    --arg after_sha "$(shasum -a 256 "$AFTER_CLI" | awk '{print $1}')" \
    --argjson commands "$(jq -Rsc 'split("\n") | map(select(length > 0))' <"$tmp/after.txt")" \
    --argjson capabilities "$after_capabilities" \
    '{version:1,before_cli:$before_cli,after_cli:$after_cli,before_sha256:$before_sha,after_sha256:$after_sha,commands:$commands,capabilities:$capabilities,unchanged:true}' \
    >"$EVIDENCE_DIR/command-contract-comparison.json"
fi

echo "before/after command contract preserves $(wc -l <"$tmp/after.txt" | tr -d ' ') public command paths"
