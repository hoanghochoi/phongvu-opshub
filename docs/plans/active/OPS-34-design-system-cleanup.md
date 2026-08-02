# Execution Plan: OPS-34 Design System Cleanup And Handoff

Date: 2026-07-29

## Status

Active — the Figma cleanup candidate and durable docs are structurally
complete; Flutter visual implementation is blocked until an exact approved
Figma revision or snapshot is recorded.

## Outcome

Produce a traceable OpsHub design-system handoff for OPS-34: verified Figma
foundation fixes, durable repository rules that match the live file, and
incremental Flutter implementation batches only after the redesign entry gate
is satisfied. Preserve current business, API, permission, route, persistence,
platform, accessibility, and unmigrated-screen behavior.

## Context

- Linear: `OPS-34` — foundation component fixes and Phosphor/navigation rules.
- User brief: `C:/Users/ASUS1/Downloads/codex-figma-design-system-cleanup-prompt.md`.
- Figma file: `mFzSmQzlapSe3RSmUhvzll`; Foundation page `13:5`.
- Authority: `AGENTS.md`, `docs/WORKFLOW.md`,
  `docs/ui-redesign/README.md`, `docs/ui-redesign/ui-redesign-workflow.md`,
  `docs/ui-redesign/design-system-redesign.md`,
  `docs/ui-redesign/flutter-implementation-rules.md`, and
  `docs/product/ui-ux.md`.
- Git checkpoint: branch `codex/ops-34-fix-component-foundation`, HEAD
  `8bb651fa7b5944956cfb4cf9abdccc017f73ef62`, equal to live
  `origin/staging`; rollback stashes `OPS-34 checkpoint before staging sync
  2026-07-29` and `OPS-34 checkpoint before refresh to origin-staging
  8bb651fa 2026-07-29` remain retained.

## Scope

In scope:

- Verify and, when authoritative, correct the OPS-34 Figma masters: Status
  Banner, checkbox/radio/switch focus, inputs/search/textarea/Command Bar,
  DateRangePicker `Hôm qua`, navigation contrast/lightning icon, and compact
  contextual helpers.
- Keep the live five-page platform inventory documented: Cover, Foundation,
  Desktop/Windows, Mobile/Android, and Tablet/Android.
- Map Figma into existing shared Flutter layers (`AppColors`,
  `AppTextStyles`, `AppRadius`, `AppLayoutTokens`, `AppTheme`, and shared
  widgets); do not introduce a parallel `Ops*` design system.
- Split runtime parity into bounded shared-component and consumer batches with
  affected-consumer proof after exact revision approval.

Out of scope without separate authority:

- Be Vietnam Pro runtime cutover before licensed local assets, fallback, and
  Android/Windows/web proof exist.
- Bulk mutation of unbound Figma nodes based only on counts, or repository-wide
  screen migration in one PR.
- Business logic, API, persistence, permission, route, or platform capability
  changes.
- Commit, push, PR, merge, Linear status transition, staging deploy, or release
  without their separate repository authorization and gates.

## Approach

1. Rehydrate the current Figma/Git/Linear state and record a stable audit
   fingerprint for targeted nodes.
2. Reconcile durable docs with the live Figma structure and accessibility
   contracts.
3. Obtain an exact Figma version/revision or explicitly approved snapshot. A
   timestamp or mutable node URL alone is not sufficient.
4. Run an independent UI/UX gate review, then delegate exactly one Flutter
   writer per approved batch.
5. Implement foundation/shared component changes before consumer migrations;
   recompute affected consumers after every batch.
6. Run focused tests, full Flutter gates, representative viewport/platform
   proof, independent review, and Linear evidence before any status movement.

## Risks And Recovery

- Figma drift: re-run the targeted node/page inventory before every visual
  implementation batch and reject stale screenshots or node fingerprints.
- Accessibility conflict: a 40 px Mobile Button is a visual surface only; wrap
  it in a hit target of at least 48 dp on Android or 44 pt on iOS/iPadOS.
- Shared-runtime blast radius: protect every current consumer of shared inputs,
  controls, DateRangePicker, Command Bar, AppShell/navigation, state panels,
  dialog/bottom sheet, pagination, and buttons.
- Dirty-doc recovery: the retained Git stash restores the pre-sync docs; do not
  drop it until the task is safely integrated.
- Source movement: if `origin/staging` or this worktree changes, pause mutation,
  recompute the affected plan, and rerun proof from the new fingerprint.

## Progress

- [x] Read the prompt, Linear issue/comments, repository authority, and skills.
- [x] Sync the existing OPS-34 task branch/worktree to live `origin/staging`
  while retaining a rollback stash and restoring the dirty docs.
- [x] Audit the live Figma inventory: 5 pages, 3 collections/367 variables,
  15 text styles, 4 effect styles.
- [x] Verify targeted Status Banner, form-control focus, input borders,
  Command Bar row, DateRangePicker `Hôm qua`, and mobile lightning color.
- [x] Confirm that `saveVersionHistoryAsync` is unsupported by the active Figma
  Plugin API; no immutable revision was created.
- [x] Reconcile the durable docs and run `git diff --check` plus exact diff
  review.
- [x] Normalize the Foundation taxonomy into exactly seven canonical sections;
  move stray icon masters, screen-pattern sources, mobile controls, and
  documentation specimens without changing node IDs or instance links.
- [x] Verify the cleaned Foundation has zero top-level non-section nodes, zero
  top-level/internal overlaps, zero section overflows, and zero icon masters
  outside `FOUNDATION / Icons — Phosphor`; visually review all seven section
  renders.
- [x] Replace the final 12 Inter source texts with the existing semantic
  Be Vietnam Pro text styles; verify `Inter=0` across all five pages and render
  the affected Dialog, Transaction Order Editor, and Statement Card sources.
- [x] Extend `Mobile Button` `1088:31426` to 10 variants
  (`Primary|Secondary × Default|Focused|Pressed|Disabled|Loading`), with a
  48 dp interaction root, 40 px visual surface, shared SpinnerGap, and zero
  direct-consumer width/collision drift.
- [x] Restore traceable Organization, Payment Monitor, and Settings helper
  states from shared component `1068:12643`; keep nonessential, non-interactive
  copy in the bubble and document keyboard/dismiss/focus-return behavior.
- [x] Run the final five-page structural audit and screenshots: seven canonical
  Foundation sections, zero section/screen overlaps, zero overflow/source
  leakage/icon leakage, and fresh targeted acceptance-component proof.
- [x] Detect live `origin/staging` advancing to `8bb651fa`, checkpoint the docs,
  fast-forward the task branch, re-apply without conflict, and rerun docs proof.
- [x] Publish exact candidate package
  `OPS-34-FIGMA-CANDIDATE-2026-07-29-B` to Linear with five full-page renders,
  targeted component renders, a per-file manifest, and ZIP SHA-256
  `4AC211283006715ED4C804085B42D38230085F4977420309A1702B30DCDA9790`.
- [ ] Record an exact approved Figma revision or snapshot in Linear.
- [ ] Lock the first bounded Flutter implementation batch and affected proof.
- [ ] Implement, test, review, and perform staging visual QA.

## Decisions

- 2026-07-29: The live Figma file has five canonical pages, including
  `Screens — Tablet · Android`; the earlier four-page proof is stale.
- 2026-07-29: Existing repository shared tokens/components are extended instead
  of creating the prompt's illustrative `Ops*` layer.
- 2026-07-29: Be Vietnam Pro remains a target, not an authorized runtime font,
  until the repository foundation/license/platform gate passes.
- 2026-07-29: Figma Mobile Button 40 px geometry does not override Android/iOS
  minimum interaction targets.
- 2026-07-29: No Flutter visual writer is dispatched without an exact approved
  Figma revision or snapshot, even though phase execution otherwise has standing
  user approval.
- 2026-07-29: Foundation source cleanup preserves the existing component and
  instance graph: moved sources retain their node IDs, and screen pages remain
  instance-only platform inventories.
- 2026-07-29: A later `origin/staging` advance was integrated by guarded
  fast-forward after a dedicated stash checkpoint; no reset, rebase, or
  unrelated-file overwrite was used.

## Validation

- Figma focused proof: structural audits and renders for nodes `120:364`,
  `180:2`, `184:65`, `185:415`, `37:7`, `195:434`, `197:422`, `204:578`,
  `216:633`, `226:693`, `229:1021`, and `1068:12643`.
- Foundation taxonomy proof: page `13:5` contains exactly sections `683:16`,
  `683:17`, `683:18`, `683:19`, `683:20`, `693:2090`, and `693:2091`, with
  zero non-section siblings, overlaps, overflows, or icon-source leakage.
- Final file proof: Cover/Foundation/Desktop/Mobile/Tablet are the only pages;
  screen top-level counts are 70/168/2 with overlap `0`, screen component-source
  leakage `0`, and every page has `Inter=0`.
- Mobile Button proof: 10 variants; every linked compact instance has a 48 dp
  root and 40 px visual surface; the 13 nested instance-swap hacks were restored
  to canonical Medium Primary/Secondary buttons so shared composition remains
  valid.
- Contextual-helper proof: exactly three contained instances at 375×812 for
  Organization, Payment Monitor, and Settings; all three renders passed.
- Linear read-back proof: package B attachment and final candidate comment are
  present on OPS-34; issue remains `In Progress` and the package is explicitly
  marked candidate/not owner-approved.
- Documentation proof: `git diff --check` plus exact diff review.
- Future Flutter focused proof: shared component tests and
  `test/design_system_migration_guard_test.dart`, followed by affected feature
  tests selected for the approved batch.
- Future repository gates: `dart format --output=none --set-exit-if-changed`,
  `flutter analyze --no-pub`, `flutter test --no-pub --reporter expanded`, and
  Android/Windows viewport screenshots tied to build SHA and Figma revision.

## Result

Not complete. The Figma cleanup candidate, screenshots, targeted component
proof, and repository docs are verified; the Git worktree is rollback-ready.
An immutable revision or explicitly approved exact snapshot is still required
before any Flutter implementation, staging proof, or production completion.
