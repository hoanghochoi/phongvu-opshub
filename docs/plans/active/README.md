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
  remains the initiative master plan; OPS-183 is the current canary-cohort
  reconciliation after the OPS-182 authority guard. PR #307 is the fifth
  real schema-v4 execution-canary observation (run `32007203966`), with
  `stale=false`, zero unmatched paths and zero reruns. The progress ledger is
  now `complete` at 5/5 but remains `promotionEligible=false`; the selected
  Harness/docs/verification-runner lane is observational, and the Flutter,
  NestJS and Go dependency-heavy profiles remain fail-closed/deferred. OPS-72
  stays `revise`/`do-not-promote`: execution-canary timing has no comparable
  baseline, TTAF has no failure sample and rerun reduction is unmeasurable.
  No profile is suppressed and no product failure is retried to green. OPS-182
  is the preceding authority guard, squash-merged through PR #307 at
  `7c7e2240`; OPS-181 is the preceding execution-canary slice through PR #306
  at `dfe09618`; OPS-180 is the preceding progress slice through PR #305 at
  `d2be1f44`; OPS-179 is the preceding reconciliation through PR #304 at
  `e4968c3f`; OPS-178 is the preceding execution-canary lane through PR #303
  at `14224af1`. The upstream updater blocker, dependency/affected-consumer
  proof closure, User/Auth authority follow-ups and remaining Phase 10
  production gates stay open. OPS-177 is the
  preceding reconciliation, squash-merged through PR #302 at `df20b4e7` and
  staging-deployed by `31998307023`; OPS-175 is squash-merged through PR #301
  at `2e5dc7b2` and staging-deployed by `31997427099`; OPS-176 is squash-
  merged through PR #300 at `c2ec9c31`, staging-deployed by `31996291315`,
  with focused toolchain proof, guarded lifecycle cleanup and deployment gates
  passed. Its later full Flutter run remains unverified after stopping at 521
  tests. OPS-174 is the preceding reconciliation after the OPS-75 installer
  fallback slice. OPS-75 is
  squash-merged through PR #298 at `75abf3d9`, staging-deployed by
  `31991597879`, with guarded lifecycle cleanup and `Ready for QA` proof. The
  installer fallback is verified, while the upstream updater exit-code blocker
  remains explicit. OPS-173 is the preceding Phase 9 ownership audit after
  the OPS-172 reconciliation and OPS-171 ERP cache-page extraction. OPS-171 is
  squash-merged through PR #295 at `1809b49f`, staging-deployed by
  `31986109215`, with guarded lifecycle cleanup and `Ready for QA` proof.
  OPS-168 MAP persistence and OPS-169 ERP cache-page characterization remain
  the preceding checkpoints. Their Flutter/Go affected-consumer proof, like
  OPS-171's, remains explicitly fail-closed and unverified under the approved
  local dependency deferral; no profile was suppressed and no product failure
  was retried to green. The Phase 9 ownership audit records two explicit
  User/Auth security follow-ups with no current owner: atomic assignment
  transaction hardening and generic admin-policy scope authorization. The next
  bounded action is collect one more real execution-canary observation, then
  decide whether OPS-72 can leave revise/do-not-promote; the upstream updater
  blocker, dependency/affected-consumer proof closure and the remaining Phase
  10 production gates stay open. OPS-170 is the preceding reconciliation
  after OPS-168/OPS-169;
  OPS-167 is the preceding reconciliation after OPS-166; OPS-165
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
