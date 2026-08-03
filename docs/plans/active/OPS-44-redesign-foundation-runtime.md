# Execution Plan: OPS-44 Redesign Foundation Runtime And UI Retirement

Date: 2026-08-03

## Status

Active

## Outcome

Đưa visual/interaction foundation hiện hành của Figma OpsHub vào shared Flutter
layers và migrate toàn bộ declared route surfaces theo các wave có thể rollback.
UI legacy chỉ được retire sau khi không còn consumer và có affected-consumer
proof; business, API, permission, platform và data behavior giữ nguyên.

## Context

- Linear: OPS-44, related OPS-25 and OPS-34.
- Git baseline: `codex/ops-44-redesign-foundation-runtime` at
  `efcf9b9a9dadad08b79fd31ebef3d03fcdc6d6a3`, equal to live `origin/staging`.
- Figma file:
  `mFzSmQzlapSe3RSmUhvzll`; pages Cover `0:1`, Foundation `13:5`,
  Windows `693:17492`, Android mobile `693:17493`, Android tablet `698:2`,
  iOS mobile `1174:2`, iPadOS tablet `1174:3`, Web `1174:4`.
- Figma read-only audit: 8 pages, 393 variables, 21 text styles, 4 effect
  styles, 906 reusable foundation sources, no missing fonts; 43 canonical
  visual route surfaces plus `/reports` redirect and
  `/fifo/inventory-import` alias.
- Runtime authority: `AGENTS.md`, `docs/WORKFLOW.md`, product UI contract,
  redesign workflow, `AppRouter` and existing tests.

## Scope

In scope:

- Reconcile foundation docs, 45 current router declarations, compatibility
  aliases, Figma page inventory and visual-smoke route coverage.
- Map Figma primitives/semantics/components into existing `AppColors`,
  `AppTextStyles`, `AppRadius`, `AppLayoutTokens`, `AppTheme` and shared widgets.
- Migrate shared primitives, shell/auth/system, pilot, operational, admin and
  long-tail surfaces in dependency order.
- Add/update focused tests, affected-consumer proof, staging build evidence,
  Chrome audit and platform evidence.
- Record Figma revisions and Linear decisions whenever a technical constraint
  changes the approved visual target.

Out of scope:

- Big-bang rewrite or deletion of legacy runtime/API compatibility layers.
- Business/API/data/permission/platform/security behavior changes.
- Be Vietnam Pro runtime cutover before local assets, license/provenance,
  fallback and Android/Windows/web proof are complete.
- Direct push, merge, production promotion or marking OPS-44 Done without the
  required release gates.

## Approach

1. Reconcile current docs and smoke guards with the live Figma eight-page file
   and current router; preserve redirect/alias semantics.
2. Capture affected consumers for shared theme, shell, inputs, DateRangePicker,
   command bar, state panels, dialogs and pagination.
3. Implement shared foundation in bounded batches, running focused proof after
   each batch; keep compatibility aliases until consumer migration is proven.
4. Migrate shell/auth, pilot, operational, admin and long-tail route groups.
5. After each merged wave reaches staging, run staging smoke and Chrome audit;
   classify findings as code defects or Figma revision/re-approval work.
6. Remove legacy visual consumers only after route/consumer proof and a
   rollback-ready checkpoint; update Linear with exact evidence before status
   transitions.

## Risks And Recovery

- Shared theme/shell changes have a large blast radius; use existing token APIs,
  focused consumer tests and revertable task branches.
- Figma/code drift: stop the affected batch, create a Figma revision, record
  the blocker and wait for re-approval before continuing that visual change.
- Font assets may remain unavailable; preserve current SF Pro Display on
  unmigrated surfaces and do not silently mix font families.
- Staging/Chrome credentials and Cloudflare Access are protected inputs; never
  place them in commands, issue text, logs or screenshots.

Recovery: use the task branch/PR revert path through `staging`; do not reset,
rebase or force-push protected branches. Retain prior shared component behavior
until the replacement has affected-consumer proof.

## Progress

- [x] Create OPS-44 Linear issue and record implementation start proof.
- [x] Create guarded OPS-44 task worktree from live `origin/staging`.
- [x] Reconcile eight Figma pages, 45 router declarations and route aliases in
      docs, ledger and visual-smoke guard.
- [x] Implement shared foundation/theme/component batch used by migrated
      surfaces; font cutover remains intentionally gated on asset/provenance and
      Android/Windows/web proof.
- [x] Migrate shell/auth/system and pilot routes in the approved frame scope;
      remaining platform proof is a release gate.
- [x] Migrate operational, admin and long-tail Loaded surfaces, including all
      13 admin frames plus Support Chat and API Connections. Shared loading,
      filtered-empty, retryable-error and permission evidence is composed from
      existing Foundation State Panels in Web frame `1793:16377`; this creates
      no new route-level state authority.
- [x] Run local staging web release build and full Flutter regression
      checkpoint; remote staging deploy, Chrome audit and platform proof remain
      pending protected release gates.
- [ ] Retire remaining legacy visual consumers after remote staging/Chrome and
      primary-platform proof confirms no active consumer needs the compatibility
      layer.
- [ ] Record final Linear implementation/proof note and move plan to completed.

## Decisions

- 2026-08-03: The live Figma file has eight official pages, including iOS,
  iPadOS and Web; older repository docs that list five pages are stale.
- 2026-08-03: `/reports` remains a redirect to `/sales-reports`, and
  `/fifo/inventory-import` remains an alias of the canonical inventory-import
  screen; neither receives a duplicate visual design.
- 2026-08-03: Legacy visual retirement is end-state work performed after
  incremental consumer migration, not a single destructive rewrite.
- 2026-08-03: The Figma desktop specimen defines the visual target for the
  brand/logo/topbar; it does not authorize removal of existing Support,
  Notifications or account actions. The supplemental Foundation documentation
  frame `1785:55496` is R2: Support and Notifications remain direct desktop
  topbar actions, the account menu keeps only account actions, and the
  permission/provider-gated metrics chip creates no route, permission or
  business-behavior change. Web specimen `1792:16338` now shows these three
  retained desktop actions directly beside the route-specific topbar action.

## Validation

- Focused proof: affected shared/widget tests plus route and migration guards.
- UI gates: `dart format --output=none --set-exit-if-changed`,
  `git diff --check`, `flutter analyze --no-pub`,
  `flutter test --no-pub --reporter expanded`.
- Runtime proof: staging workflow/SHA, staging smoke checklist, Chrome
  authenticated audit and visual-smoke at relevant viewports; Android/Windows
  proof for primary platform behavior.
- Evidence must record Figma page/frame/revision, viewport/platform and build
  SHA; no generic test-pass claim substitutes for affected-consumer proof.

## Result

Not complete. Local regression/build checkpoint is verified, but remote staging
deploy, Chrome audit, remaining surfaces and platform proof are still pending.
Record verified waves, unverified surfaces, residual risks and follow-up
decisions before moving this plan to `docs/plans/completed/`.
