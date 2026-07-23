#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
classifier="$root/scripts/harness-cli-release-changed.sh"
workflow="$root/.github/workflows/post-merge-maintenance.yml"

printf '%s\n' \
  crates/harness-cli/src/main.rs \
  scripts/schema/013-changeset-content-sha.sql \
  scripts/build-harness-cli-release.sh \
  scripts/harness-cli-release-changed.sh \
  scripts/promote-harness-cli-release-tag.sh \
  scripts/verify-harness-cli-release-identity.sh \
  .github/workflows/harness-cli-release.yml \
  .github/workflows/post-merge-maintenance.yml \
  tests/installer/test-cli-upgrade-candidate.sh \
  tests/protocol/smoke-native-artifact.sh \
  tests/protocol/smoke-v0.1.14-artifact.ps1 \
  tests/release/download-v0.1.14-artifact.sh \
  Cargo.toml \
  Cargo.lock |
  "$classifier"

for unrelated in \
  crates/harness-symphony/Cargo.toml \
  docs/HARNESS.md \
  .github/workflows/premerge.yml; do
  if printf '%s\n' "$unrelated" | "$classifier"; then
    echo "unrelated path triggered Harness CLI publication: $unrelated" >&2
    exit 1
  fi
done

grep -Fq 'scripts/harness-cli-release-changed.sh <<<"$changed_files"' "$workflow"

echo "Harness CLI post-merge release classification tests passed"
