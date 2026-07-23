#!/usr/bin/env bash
set -euo pipefail

# Exit successfully only when a changed path can alter the published Harness
# CLI binary, schema, or proof/promotion packaging. Release-path corrections
# must be able to advance past a consumed but unpublished version.
pattern='^('
pattern+='crates/harness-cli/|scripts/schema/|Cargo\.toml$|Cargo\.lock$|'
pattern+='scripts/(build-harness-cli-release|harness-cli-release-changed|promote-harness-cli-release-tag|verify-harness-cli-release-identity)\.sh$|'
pattern+='\.github/workflows/(harness-cli-release|post-merge-maintenance)\.yml$|'
pattern+='tests/installer/test-cli-upgrade-candidate\.sh$|'
pattern+='tests/protocol/smoke-(native|v0\.1\.14-artifact)\.(sh|ps1)$|'
pattern+='tests/release/download-v0\.1\.14-artifact\.sh$'
pattern+=')'
grep -Eq "$pattern"
