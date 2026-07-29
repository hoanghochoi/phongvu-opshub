# Execution Plan: OPS-25 Foundation Skill-Routing Revision

Date: 2026-07-26

## Status

Completed — historical Figma revision; repository routing edits superseded

## Checkpoint

- Branch: `codex/ops-25-redesign-foundation-pack`.
- Base HEAD: `3fe2e5cd9a7b14813399e68f522e266bd0c958f5`.
- Existing uncommitted Foundation Pack work is user-approved task state and must
  be preserved.
- Figma file: `OpsHub Redesign Foundation — OPS-25`.
- Primary Button component set before this revision: `22:32`, 15 variants.

## Goal

Apply the installed UI/UX design skills consistently to the existing Primary
Button and make skill selection a durable part of the redesign workflow.

## Scope

1. Audit the Primary Button with `ui-ux-pro-max`, `ux-designer`,
   `design-system`, `figma-use`, and `figma-generate-library`.
2. Preserve the approved OPS-25 brand, typography, token architecture, and
   component scope; change the component only when the audit identifies a
   concrete gap.
3. Add task-based skill routing to the root redesign instructions and the
   relevant redesign workflow documents.
4. Validate Figma structure/bindings/visual output and repository documentation.

## Boundaries

- Do not create Input/Combobox, Card, product screens, or runtime code.
- Do not replace approved brand or token authority with generic skill output.
- Do not commit, push, open/update a PR, or transition Linear.
- Preserve unrelated and previously approved uncommitted work.

## Verification

- Figma: 15 Button variants, state/size matrix, component properties, token
  bindings, focus/disabled treatment, touch-target guidance, Light/Dark
  behavior, and final screenshot.
- Docs: root/snippet consistency, valid links, bounded diff, and
  `git diff --check`.

## Recovery

- Figma edits are limited to the existing Button page/component and must return
  every mutated node ID.
- Repository edits remain uncommitted and can be reverted file-by-file without
  touching the pre-existing Foundation Pack changes.

## Validation

- Primary Button metadata: 15 variants, three sizes, five states, Label TEXT
  property, and zero binding/state audit issues.
- Primary Button visual: Light and Dark renders inspected; final file restored
  to Light. Default/Focused fallback paint now matches `#1435C3`; focus ring is
  a 2 px outside stroke.
- Contrast from resolved Figma variables: enabled content ranges from 5.80:1 to
  14.29:1 across Light/Dark states; disabled content is 3.90:1 Light and 4.04:1
  Dark.
- Workflow docs: referenced skill files exist, root `AGENTS.md` matches
  `AGENTS-snippet.md`, and `git diff --check` passes.

## Result

The approved Primary Button visual now resolves the brand default correctly and
documents the implementation-only touch-target requirement without changing the
approved 40 px Small visual token. Future redesign tasks are required to select
and report the relevant installed skills automatically.

Closeout note, 2026-07-29: the Figma result remains historical OPS-25 evidence.
The associated root/shared-workflow edits were intentionally excluded from the
OPS-25 publication scope because OPS-34 and the current repository instructions
contain newer authority for the reorganized live file. The original edits remain
recoverable in the named OPS-25 scope-split stash.

## Progress

- [x] Approved scope and Git checkpoint recorded.
- [x] Primary Button audited and revised if required.
- [x] Redesign skill-routing documentation updated.
- [x] Figma and repository validation passed.
