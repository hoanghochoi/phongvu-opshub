# Execution Plan: OPS-25 Redesign Foundation Pack

Date: 2026-07-26

## Status

Completed

## Outcome

Produce a review-ready, internally consistent foundation package for the new
OpsHub UI/UX redesign before any Figma screen work begins. The package must
contain a bounded brief, a fresh evidence-backed audit, a complete inventory of
the 44 declared router paths, and exact three-layer design tokens with recorded
contrast proof.

## Context

- Linear issue: OPS-25, related to governance issue OPS-22.
- Governance baseline: GitHub PR #36, merged into `staging` at
  `3fe2e5cd9a7b14813399e68f522e266bd0c958f5`.
- Redesign authority: `docs/ui-redesign/README.md`,
  `docs/ui-redesign/ui-redesign-workflow.md`, and
  `docs/ui-redesign/design-system-redesign.md`.
- Product UI contract: `docs/product/ui-ux.md` and affected feature contracts.
- Runtime evidence: `lib/app/navigation/app_router.dart`, shared navigation,
  theme, layout, widgets, feature screens, tests, assets, and `pubspec.yaml`.
- Historical comparison only:
  `docs/product/opshub-redesign-audit-2026-06-30.md` and
  `docs/product/opshub-redesign-gap-map-2026-07-01.md`.

## Scope

In scope:

- `docs/ui-redesign/foundation/README.md`.
- `docs/ui-redesign/foundation/brief.md`.
- `docs/ui-redesign/foundation/audit-2026-07-26.md`.
- `docs/ui-redesign/foundation/screen-inventory.md`.
- `docs/ui-redesign/foundation/design-tokens.md`.
- `docs/ui-redesign/foundation/design-tokens.json`.
- Required redesign index/foundation-reference updates.
- Source-derived validation and contrast calculations.

Out of scope:

- Figma screens, components, variables, or revision links.
- Flutter/runtime, route, API, data, permission, or business-flow changes.
- Font asset acquisition or licensing claims.
- Approval on Đại Ca's behalf.

## Approach

1. Inventory route, navigation, permission, screen, state, responsive, theme,
   asset, and shared-component evidence from the current baseline.
2. Separate verified source/runtime facts from historical evidence and
   unverified visual observations.
3. Draft the brief, fresh audit, and 44-route screen inventory from the same
   evidence set.
4. Define primitive, semantic, and component token layers with exact values;
   provide matching Markdown and W3C DTCG-aligned JSON.
5. Calculate critical semantic contrast pairs and revise values until the
   proposed set meets its stated WCAG targets.
6. Cross-review route counts, token aliases, terminology, status, blockers,
   and repository references; record the final evidence and stop at
   `Review-ready`.

## Risks And Recovery

- Authenticated runtime screens may not be locally observable. Mark those
  observations unverified; do not infer visual truth from source alone.
- Be Vietnam Pro has no committed assets/license proof. Keep typography as a
  proposed target and a Figma/runtime blocker.
- Existing color APIs include legacy and semantic values with overlapping
  names. Preserve the official brand primitive while clearly separating the
  proposed semantic mapping from current runtime behavior.
- The router contains redirects, aliases, parameterized details, and platform
  fallbacks. Count declared paths exactly and classify each rather than treating
  every path as a unique top-level screen.
- Recovery: all work is docs-only on the OPS-25 branch. Revert the bounded
  foundation/index patch without touching runtime files if the pack is rejected.

## Progress

- [x] OPS-22 governance merged and lifecycle finish passed.
- [x] OPS-25 issue/worktree created from live `origin/staging`.
- [x] Current route/theme/screen evidence captured.
- [x] Brief, audit, and screen inventory drafted.
- [x] Exact tokens and contrast proof drafted.
- [x] Cross-review and repository checks passed.
- [x] Linear proof recorded and pack presented as `Review-ready`.
- [x] Đại Ca approved revision `OPS-25-2026-07-26` for Figma foundation work.
- [x] Historical Figma rollout closed and handed off to OPS-34 without
  publishing stale shared-workflow files.

## Decisions

- 2026-07-26: Keep the Foundation Pack in separate OPS-25 scope after OPS-22;
  Đại Ca selected this lifecycle path explicitly.
- 2026-07-26: The pack may be self-reviewed but not self-approved. Only Đại Ca
  can approve it and unlock Figma screen work.
- 2026-07-26: Historical Redesign V2 documents are comparison evidence, not the
  current redesign audit.
- 2026-07-26: No live visual claim is considered verified without an observable
  authenticated runtime surface or current screenshot evidence.
- 2026-07-26: Đại Ca approved Foundation Pack revision `OPS-25-2026-07-26`.
  Approval opens Figma variables/styles/core components only; Figma screens
  remain gated by a separately approved Figma foundation revision.
- 2026-07-29: Close OPS-25 as the approved Foundation Pack and historical Figma
  snapshot. OPS-34 owns the subsequently reorganized five-page live file and
  current shared redesign documentation.

Promote lasting product or architecture decisions into `docs/decisions/`.

## Validation

- Focused proof: exact 44-path reconciliation; token alias validation; WCAG
  contrast calculation for critical semantic pairs; JSON parse.
- Integration or end-to-end proof: not applicable; runtime files were not
  affected and authenticated visual capture was unavailable.
- Repository-required checks: strict UTF-8 for 9 changed docs/JSON/plan files,
  repository path-reference check, no trailing whitespace, cross-artifact
  terminology/count review, and `git diff --check`.
- Baseline protected-consumer proof: focused Flutter suite 47/47 pass before
  docs-only changes.

## Result

Foundation Pack revision `OPS-25-2026-07-26` was approved by Đại Ca. Its
subsequent Figma rollout is retained as historical evidence and handed off to
OPS-34, which owns the live five-page file. Be Vietnam Pro local
asset/platform proof remains a separate runtime gate. No runtime files are part
of the OPS-25 closeout diff.
