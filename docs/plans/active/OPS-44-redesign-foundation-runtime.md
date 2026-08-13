# OPS-44 — Redesign foundation runtime handoff

## Status

`release-pending` — Linear OPS-44 remains `Ready for QA`. The implementation
and local/staging evidence are preserved in
[`OPS-44-redesign-foundation-runtime-history.md`](../completed/OPS-44-redesign-foundation-runtime-history.md);
this file is the current release handoff and authority pointer.

## Owner and dependencies

- Owner: UI/UX runtime and release owner for OPS-44.
- Dependencies: approved Figma Foundation nodes, OPS-34 foundation cleanup,
  OPS-53 Chrome/audit follow-ups, staging deployment and physical-platform QA.
- Next action: run the remaining exact-node state matrix on the deployed merge
  SHA, record authenticated Chrome/platform evidence, then complete staging QA
  and the production release lifecycle before changing Linear status.

## Approved authority

- Figma file: `mFzSmQzlapSe3RSmUhvzll` and the approved Foundation/Desktop,
  compact, medium, state and Home revisions recorded in the history file.
- Repository product/design authority: [`docs/product/ui-ux.md`](../../product/ui-ux.md),
  [`docs/ui-redesign/README.md`](../../ui-redesign/README.md), and the exact
  node maps linked from the history file.
- Runtime contract: preserve routes, API/DTO/permission behavior, platform
  audio behavior, Vietnamese copy and shared breakpoint geometry. A missing
  Figma node blocks visual work; legacy widgets are not a fallback path.

## Shipped scope and proof

- Shared Foundation shell, theme/tokens, route/state panels and the approved
  Home/Operations/Notifications/Account visual waves are implemented.
- Local Flutter analyzer, focused geometry/state tests, full Flutter tests,
  Web release/Wasm dry run, Android staging debug and relevant backend/Go
  consumer proof are recorded in the history file and Linear OPS-44 comments.
- Exact staging deploy/route smoke evidence exists for the shipped SHA; it is
  not a substitute for the remaining state-by-state visual gate.

## Remaining release gap

- Authenticated Chrome comparison is still required for every declared
  viewport/theme and loaded, loading, empty, unavailable/permission and
  retryable-error state where the route exposes it.
- Physical Windows/Android/iOS audio and platform evidence remains open where
  the affected route uses a platform-specific speaker contract.
- Production deployment is required before OPS-44 can be marked `Done`.

## Recovery

Revert only the reviewed OPS-44 merge through `staging`; do not reset protected
branches or delete the historical evidence. Re-run the complete downstream
visual and platform ladder after any UI change.
