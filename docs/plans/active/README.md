# Active Execution Plans

Only work with a current owner and a concrete next action stays in this
directory. The machine-readable classification for this tree is
[`docs/migrations/ops-71-plan-disposition.json`](../../migrations/ops-71-plan-disposition.json);
validate it with `node scripts/verify-plan-disposition.mjs`.

Current active/release-pending authority:

- OPS-33, OPS-34, OPS-39 (hostname and H2H), OPS-40, OPS-42, OPS-43, OPS-45,
  OPS-52, OPS-60, OPS-62 and OPS-80 retain their own execution plans because
  testing, infrastructure, UAT, authenticated QA or release gates remain open.
- [`OPS-44-redesign-foundation-runtime.md`](OPS-44-redesign-foundation-runtime.md)
  is the release-pending handoff; the long execution journal is retained under
  `docs/plans/completed/`.
- [`OPS-53-redesign-chrome-audit-consolidation.md`](OPS-53-redesign-chrome-audit-consolidation.md)
  is the only current OPS-53 execution summary. Its nine fragments are history.
- [`OPS-64-upstream-harness-repository-cleanup.md`](OPS-64-upstream-harness-repository-cleanup.md)
  remains the initiative master plan; OPS-101 is its current plan-disposition
  reconciliation slice after the OPS-100 staging deployment.

Use `docs/templates/exec-plan.md` for new durable work. Move a plan only after
its requested outcome and validation are recorded; do not infer production
completion from a merge or staging deployment alone.
