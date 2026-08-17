#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

require() {
  local file=$1
  local text=$2
  rg -Fq -- "$text" "$root/$file" || {
    printf 'documentation contract failed: %s omits: %s\n' "$file" "$text" >&2
    exit 1
  }
}

reject() {
  local file=$1
  local text=$2
  if rg -Fq -- "$text" "$root/$file"; then
    printf 'documentation contract failed: %s contains retired path: %s\n' "$file" "$text" >&2
    exit 1
  fi
}

require AGENTS.md 'Start with the requested outcome'
require AGENTS.md 'No control-plane operation is required.'
require docs/WORKFLOW.md '### Bounded Change'
require docs/WORKFLOW.md '### Durable Planned Change'
require docs/HARNESS.md 'ordinary repository task'
require docs/CONTEXT_RULES.md 'The mandatory entry context is `AGENTS.md` plus `docs/WORKFLOW.md`'
require README.md 'The default path requires no local database.'
require scripts/README.md 'The pinned payload is `harness-v0.1.8`.'
require scripts/README.md 'scripts/verify-task.mjs'
require tests/README.md '## Current Core'
require tests/README.md '## Retired Compatibility Proof'
require docs/decisions/0029-adopt-upstream-repository-protocol-and-retire-protocol-v1.md 'OpsHub is a consumer of upstream Harness.'
require docs/migrations/harness-v1-retirement-manifest.json '"issue": "OPS-70"'
require docs/migrations/harness-v1-retirement-manifest.json '"databaseWritten": false'
require docs/migrations/ops-71-plan-disposition.json '"issue": "OPS-71"'
require docs/migrations/ops-72-execution-canary-progress.json '"finalEvidencePath": "docs/migrations/ops-72-live-shadow-evidence.json"'
require docs/migrations/ops-72-execution-canary-progress.json '"promotionEligible": false'
require scripts/verify-harness-retirement.mjs 'HARNESS_RETIREMENT_FAILED'
require scripts/verify-plan-disposition.mjs 'PLAN_DISPOSITION_FAILED'

for file in AGENTS.md docs/WORKFLOW.md docs/HARNESS.md docs/CONTEXT_RULES.md; do
  reject "$file" 'scripts/bin/harness-cli query matrix --active --summary'
  reject "$file" 'first run `scripts/bootstrap-harness.sh`'
done

[[ -x "$root/tests/workflow/test-repository-workflow.sh" ]] || exit 1
node "$root/scripts/verify-harness-retirement.mjs" >/dev/null
node "$root/scripts/verify-plan-disposition.mjs" >/dev/null
require .github/workflows/release-guard-pr.yml 'Check patch whitespace'
[[ ! -e "$root/.github/workflows/harness-cli-release.yml" ]]
[[ ! -e "$root/.github/workflows/harness-release.yml" ]]

echo 'repository authority, upstream Harness boundary, and migration references passed'
