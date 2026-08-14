# [Implementation] <Feature or Screen>

## Goal

Implement approved redesign scope without changing unrelated behavior.

## Traceability

- Design issue:
- Approved Figma frame/node/revision:
- Approval comment/date:
- Product docs and decision:

### Required node map (complete before UI mutation)

| Viewport/state | Exact Figma node/revision | Flutter shared widget | Token + geometry | Typography/copy/icon | Protected behavior |
| --- | --- | --- | --- | --- | --- |
| | | | | | |

## Scope

- Screens/components:
- Shared foundation/components to evolve:
- User-visible behavior:

## Out of scope

- Business/API/data/permission changes not separately authorized
- Unrelated screens/components

## Protected current behavior and affected consumers

- Old behavior that must continue:
- Shared producers/consumers:
- Path contracts/affected proof command when required:

## Required states and responsive behavior

- Compact `<600`
- Medium `600–899`
- Expanded `900–1199`
- Wide `>=1200` when applicable
- Loading/empty/error/retry/validation/permission/session/domain states

## Accessibility and platform

- Android and Windows primary proof
- Web/additional affected platform proof
- Keyboard/focus/semantics/contrast/touch target/text scaling/reduced motion

## Logging and copy

- `AppLogger` start/success/failure/key branches with sanitized context
- Vietnamese-first/action-oriented UI copy; no technical codes or secrets

## Acceptance criteria

- [ ] UI matches exact approved Figma revision.
- [ ] Node map covers every visible element; no visual choice comes from legacy
  code, runtime screenshots, memory, or "close enough" inference.
- [ ] Product/business/API/permission/platform contracts remain intact.
- [ ] Shared tokens/components are used; no parallel feature design system.
- [ ] Typography and breakpoint behavior follow approved foundation.
- [ ] Required data/form/permission states are implemented.
- [ ] Protected affected consumers pass.
- [ ] Focused and repository-required validation passes.
- [ ] Screenshots/smoke evidence identifies viewport/platform/build SHA.
- [ ] Known differences and residual risk are recorded.

## Verification plan

```powershell
dart format --output=none --set-exit-if-changed <changed Dart files>
git diff --check
node scripts/run-with-toolchain.mjs --profile flutter -- flutter analyze
node scripts/run-with-toolchain.mjs --profile flutter -- flutter test --reporter expanded
```

Add focused widget/unit/golden/visual and affected-consumer commands here.

Evidence must run in this order: node map → geometry widget/golden proof →
local build of the tested SHA → staging deploy → authenticated Chrome/Figma
comparison per affected viewport. A visual fix invalidates all downstream
evidence and requires it to be rerun.

## Delivery gate

- Branch/worktree created by task lifecycle from live `origin/staging`.
- PR `[OPS-123] Description` targets `staging` and uses `Part of OPS-123` while
  awaiting staging QA.
- Linear tracking comment is posted before each forward status transition.
- `Done` requires successful production deployment.
