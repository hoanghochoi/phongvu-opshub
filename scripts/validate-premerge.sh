#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

for command in git rg node python; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "pre-merge validation requires: $command" >&2
    exit 1
  }
done

while IFS= read -r script; do
  bash -n "$script"
done < <(find scripts tests -type f -name '*.sh' -print | LC_ALL=C sort)

node scripts/verify-harness-retirement.mjs >/dev/null
node --test tests/verification/*.test.mjs
python -m unittest discover -s tests/migration -p 'test_*.py'
tests/docs/test-doc-contracts.sh
tests/workflow/test-repository-workflow.sh

git diff --check

echo "pre-merge repository contract passed"
