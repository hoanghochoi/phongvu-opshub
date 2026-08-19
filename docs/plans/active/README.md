# Active Execution Plans

Only work with a current owner and a concrete next action stays in this
directory. The machine-readable classification for this tree is
[`docs/migrations/ops-71-plan-disposition.json`](../../migrations/ops-71-plan-disposition.json);
validate it with `node scripts/verify-plan-disposition.mjs`.

Current active/release-pending plans are:

- `OPS-33-sales-price-contract.md`
- `OPS-34-design-system-cleanup.md`
- `OPS-39-bankapis-hostnames.md`
- `OPS-39-bidv-h2h-api.md`
- `OPS-40-support-chat-phase-1.md`
- `OPS-42-api-only-staging-ingress.md`
- `OPS-43-local-preset-speaker.md`
- `OPS-44-redesign-foundation-runtime.md`
- `OPS-45-staging-public-verification.md`
- `ops-52-purchased-promotion-kpis.md`
- `OPS-53-redesign-chrome-audit-consolidation.md`
- `OPS-60-home-period-comparison-import.md`
- `OPS-62-home-import-card-order-hotfix.md`
- `OPS-80-home-summary-cache-coverage.md`

The OPS-64 master plan is no longer active. It is retained as
[`../completed/OPS-64-upstream-harness-repository-cleanup.md`](../completed/OPS-64-upstream-harness-repository-cleanup.md)
with production closure evidence in
[`docs/migrations/ops-64-production-closure.json`](../../migrations/ops-64-production-closure.json).

Use `docs/templates/exec-plan.md` for new durable work. Move a plan only after
its requested outcome and validation are recorded. For a task explicitly
classified `documentation-only` under ADR 0031, exact staging deploy/QA proves
repository execution completion; do not infer production publication from that
proof. Runtime and production-affecting plans still require production release.
