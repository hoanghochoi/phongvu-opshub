#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$root"
node scripts/prepare-task-toolchain.mjs --profile all

cd "$root/backend-nest"
npm test -- --runInBand \
  erp/erp-authorized-request.spec.ts \
  erp/erp-ppm-product.service.spec.ts \
  sales-reports/sales-report-erp.service.spec.ts \
  contract-appendices/contract-appendix-calculator.spec.ts \
  contract-appendices/contract-appendices.service.spec.ts \
  contract-appendices/contract-appendices.controller.spec.ts

cd "$root"
flutter test --no-pub \
  test/contract_appendix_core_test.dart \
  test/contract_appendix_screen_test.dart

git diff --check
