#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
verifier="$root/tests/core/assert-schema-replay-command-contract.sh"
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT

if HARNESS_CLI="$temp/missing-cli" "$verifier" >/dev/null 2>&1; then
  echo "core contract accepted a missing CLI" >&2
  exit 1
fi

cp "$root/tests/core/harness-command-contract.txt" "$temp/commands.txt"
printf '%s\n' 'removed-public-command' >>"$temp/commands.txt"
if HARNESS_COMMAND_MANIFEST="$temp/commands.txt" "$verifier" >/dev/null 2>&1; then
  echo "core contract accepted a missing public command" >&2
  exit 1
fi

mkdir "$temp/schema"
cp "$root"/scripts/schema/0{01,02,03,04,05,06,07,08,09}-*.sql "$temp/schema/"
cp "$root"/scripts/schema/01{0,1,2}-*.sql "$temp/schema/"
if HARNESS_SCHEMA_DIR="$temp/schema" "$verifier" >/dev/null 2>&1; then
  echo "core contract accepted a schema set missing the current migration" >&2
  exit 1
fi

echo "core schema/replay/command contract negative tests passed"
