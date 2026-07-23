#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
renderer="$root/scripts/render-changelog-files.py"
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT

python3 - <<'PY' >"$temp/many.json"
import json
print(json.dumps([[{"filename": f"removed/path-{index}.txt"} for index in range(1, 26)]]))
PY
python3 "$renderer" --limit 20 <"$temp/many.json" >"$temp/many.md"
grep -Fxq -- '- Changed files: 25 total (first 20 shown)' "$temp/many.md"
[[ "$(grep -c '^  - `removed/path-' "$temp/many.md")" == 20 ]]
grep -Fxq -- '  - _… 5 additional file(s) omitted from this entry._' "$temp/many.md"
! grep -Fq 'path-21.txt' "$temp/many.md"

printf '%s\n' '[[{"filename":"plain.txt"},{"filename":"tick`name.txt"}]]' |
  python3 "$renderer" --limit 20 >"$temp/small.md"
grep -Fxq -- '- Changed files: 2 total' "$temp/small.md"
grep -Fxq -- '  - `tick\`name.txt`' "$temp/small.md"

if printf '[]\n' | python3 "$renderer" --limit 0 >"$temp/zero.out" 2>&1; then
  echo "renderer accepted a non-positive cap" >&2
  exit 1
fi

echo "bounded changelog changed-file rendering tests passed"
