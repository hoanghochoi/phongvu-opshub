# Active Execution Plans

Only work with a current owner and a concrete next action stays in this
directory. The machine-readable classification for this tree is
[`docs/migrations/ops-71-plan-disposition.json`](../../migrations/ops-71-plan-disposition.json);
validate it with `node scripts/verify-plan-disposition.mjs`.

Current active/release-pending authority:

- OPS-33, OPS-34, OPS-39 (hostname handoff and H2H runtime), OPS-40, OPS-42,
  OPS-43, OPS-45, OPS-52, OPS-60, OPS-62 and OPS-80 retain their own execution plans because
  testing, infrastructure, UAT, authenticated QA or release gates remain open.
- The OPS-39 H2H plan is canonical for runtime/API behavior; the shorter
  hostname plan owns only the external DNS, TLS and tunnel handoff.
- [`OPS-44-redesign-foundation-runtime.md`](OPS-44-redesign-foundation-runtime.md)
  is the release-pending handoff; the long execution journal is retained under
  `docs/plans/completed/`.
- [`OPS-53-redesign-chrome-audit-consolidation.md`](OPS-53-redesign-chrome-audit-consolidation.md)
  is the only current OPS-53 execution summary. Its nine fragments are history.
- [`OPS-64-upstream-harness-repository-cleanup.md`](OPS-64-upstream-harness-repository-cleanup.md)
  remains the initiative master plan; OPS-170 is the current docs-only
  reconciliation after the OPS-168/OPS-169 Phase 9 MAP persistence and ERP
  cache-page characterization slices. OPS-168 is squash-merged through PR
  #292 at `a1ef5922`, staging-deployed by `31980348208`, with guarded
  lifecycle cleanup and `Ready for QA` proof. OPS-169 is squash-merged through
  PR #293 at `490a5ce5`, staging-deployed by `31981556234`, with guarded
  lifecycle cleanup and `Ready for QA` proof. Their Flutter/Go
  affected-consumer proof remains explicitly fail-closed and unverified under
  the approved local dependency deferral; no profile was suppressed and no
  product failure was retried to green. The next bounded Phase 9D runtime
  boundary is ERP cache-page mapping extraction from `SalesReportsService`;
  MAP persistence is already collaborator-owned. Atomic assignment transactions
  and generic admin-policy scope authorization remain separate full-fix/security
  follow-ups. OPS-167 is the preceding reconciliation after OPS-166; OPS-165
  is the preceding reconciliation after OPS-164; OPS-163 is the preceding
  reconciliation after OPS-162; OPS-161 is the preceding reconciliation after
  OPS-160; OPS-159 is the preceding reconciliation after OPS-158. OPS-157 is
  the earlier plan reconciliation at `98d48f5e`,
  staging-deployed by `31962662658`, with guarded lifecycle cleanup and
  `Ready for QA` proof. OPS-156 is the preceding completed Phase 9F UserService access/scope runtime
  checkpoint at merge `6849ddb0`, staging deploy `31961307152`, with guarded
  lifecycle cleanup and `Ready for QA` proof. OPS-155 is the preceding
  protected-credential runtime slice, and OPS-154 is
  the preceding completed Phase 9C runtime checkpoint after its PR merge,
  staging deployment and guarded lifecycle cleanup. OPS-153 reconciled the plan
  after the finance-metrics extraction merged, staging-deployed and passed
  guarded lifecycle cleanup. OPS-152 is the preceding completed runtime
  checkpoint; OPS-151 is the legacy sales-metrics checkpoint, OPS-150 the
  main-KPI checkpoint, OPS-149 the sales-progress checkpoint and OPS-148 the
  comparison checkpoint;
  Phase 8 has an evidence-backed no-deletion disposition; Phase 9/10 and
  production-pending work stay active until their release gates pass.

Use `docs/templates/exec-plan.md` for new durable work. Move a plan only after
its requested outcome and validation are recorded; do not infer production
completion from a merge or staging deployment alone.
