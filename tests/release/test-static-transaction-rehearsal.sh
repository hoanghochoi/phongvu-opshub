#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CURRENT_DIR="$root" bash "$root/deploy/staging/static-transaction-rehearsal.sh"
