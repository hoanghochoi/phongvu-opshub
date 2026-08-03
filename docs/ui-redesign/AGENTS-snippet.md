## UI/UX Redesign Initiative

The new OpsHub UI/UX redesign is governed by `docs/ui-redesign/`. For any task
that changes the visual or interaction target of a redesigned/migrated surface,
read:

1. `docs/ui-redesign/README.md`.
2. `docs/ui-redesign/ui-redesign-workflow.md`.
3. The relevant design, Figma, Linear, Flutter, and QA documents in that folder.
4. `docs/product/ui-ux.md` and the affected feature product contract.

The redesign is incremental. Existing Redesign V2 code/Figma is the current
runtime baseline, not the automatic visual target for the new redesign.
Unmigrated screens must keep working while migrated scopes follow approved new
frames.

For every migrated/redesigned surface, retire the old visual UI completely.
Current code may preserve business/runtime behavior only; it is forbidden as a
visual fallback, spacing/copy/icon reference, or "close enough" implementation.
If Figma has no exact node for a visible element, stop that visual scope, revise
Figma, record the decision in Linear, and wait for approval.

Non-negotiable rules:

- Preserve business logic, API/data contracts, permission, platform behavior,
  security, privacy, Vietnamese-first copy, and existing affected consumers
  unless a separate authoritative product change explicitly changes them.
- Keep the existing official brand palette/assets. Be Vietnam Pro is the target
  font only after an approved foundation issue supplies licensed local assets,
  shared-theme integration, compatibility handling, and platform proof.
- Use shared breakpoint tokens: compact `<600`, medium `600–899`, expanded
  `900–1199`, and wide desktop `>=1200`; do not add feature-local breakpoints.
- No approved Figma frame/revision means no visual redesign implementation.
  Review/test/docs and restorative fixes that do not change intended design may
  use the existing approved behavior without creating a new frame.
- Figma must not invent routes, data, permission, or business behavior. Stop
  and request product authority when a design requires a new contract.
- Before any UI mutation, retrieve exact Figma node(s) for the target viewport
  and map tokens, geometry, typography, icon, copy, state, and responsive
  constraints to shared Flutter components. Do not implement from memory,
  screenshots alone, or legacy code.
- UI delivery is a strict ordered gate: exact approved Figma node/revision for
  every affected viewport/state → node map → geometry widget/golden proof →
  build of the exact source SHA → staging deploy → authenticated Chrome/Figma
  screenshot comparison at every affected viewport. A missing, failed or stale
  step blocks completion; a visual fix requires all downstream proof again.
- Current/legacy UI may preserve runtime behavior only. It must never supply a
  visual reference, fallback, placeholder or gap-fill: layout, spacing, color,
  typography, icon, copy, component shape, responsive behavior and old
  screenshots are all forbidden visual inputs for a migrated surface.
- Every UI change needs geometry/widget or golden proof for each changed
  breakpoint and a local build. After staging deploy, audit the authenticated
  Chrome app at every affected viewport against those exact nodes; unapproved
  visual difference fails the scope and must be fixed and re-audited.
- Evolve shared theme/tokens/components before adding feature-local variants.
  Continue to reuse the canonical DateRangePicker, command-input layout,
  related-flow modal model, AppLogger, and accessibility/platform contracts.
- Every redesign work item needs a Linear `OPS-*` issue. Only work that changes
  repository files starts a `codex/ops-*-short-slug` branch/worktree from live
  `origin/staging` through `scripts/task-lifecycle.mjs`; Figma-only design or
  review does not create a Git worktree unless it also changes repository
  documentation or assets. Feature PRs target `staging`.
- Record implementation/proof in Linear before a forward status transition.
  Staging merge/deploy or QA approval is not `Done`; production deployment is.

Authority is scoped, not a single override list:

1. Repository safety/release rules and accepted business/API/permission/
   platform/security contracts remain mandatory.
2. Đại Ca's current explicit direction selects product/design intent within
   those boundaries.
3. Approved Figma controls visual/interaction target for its exact scope.
4. `docs/ui-redesign/design-system-redesign.md` controls redesign foundation.
5. Linear acceptance criteria control work-item scope and proof.
6. Current code/tests protect unmigrated and affected behavior.
