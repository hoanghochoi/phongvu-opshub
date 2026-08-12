# OPS-53 — FIFO compact Quick Action parity

## Status

Approved Figma authority is mapped to Flutter and the bounded implementation
has passed local verification. Publication and deployed staging proof remain
pending.

## Checkpoint and ownership

- Canonical staging worktree: `C:\Users\ASUS1\Documents\flutter_projects\phongvu-opshub`.
- Task worktree: `C:\Users\ASUS1\Documents\flutter_projects\opshub-ops-53`.
- Branch: `codex/ops-53-fifo-quick-action-parity`.
- Exact base: `b1f1dbcc202e84864a84829b6ccc424a75892b80`.
- `staging` and `origin/staging` matched exactly before lifecycle `start`.
- Both canonical and task worktrees were clean before this plan was created.
- Runtime ownership is limited to the shared compact Quick Action launcher,
  mobile shell slot, semantic tokens, and their direct/affected tests.
- The latest FIFO result-card spacing revision remains outside production edits
  until its post-correction frames receive a separate explicit approval.

## Approved authority and node map

- Figma file: `mFzSmQzlapSe3RSmUhvzll`.
- Shared component: `406:16778`; button `406:16779`; icon `406:16780`.
- Approved state board: `2331:2325`; Light `2331:2328`; Dark `2331:2358`.
- Approval recorded in OPS-53 comment
  `5cfda081-c954-4eb9-913f-74a3a5a4b8e1`.
- Fresh design-context and screenshot read-back completed before production
  edits on 2026-08-12.

| Figma element/state | Exact contract | Flutter code target | Protected behavior |
| --- | --- | --- | --- |
| Slot `406:16778` | `84×68`; omitted when unavailable | `lib/app/navigation/app_shell.dart`: compact fifth `NavigationDestination` slot | Permission/platform filtering, selected index mapping, four normal destinations |
| Button `406:16779` | `48×48`, `x=18/y=10`, radius `20` | `QuickActionsLauncher.buttonSize`; compact slot wrapper; launcher shape | 48dp hit target, no label overlap/clipping, safe-area behavior |
| Default Light/Dark | navigation selected content `#1435C3` / `#8EA0FF` | context-aware shared navigation color token | Existing destination selected-color contract |
| Pressed | `#0D1F75` Light / `#6F83F7` Dark | launcher pressed-state resolver | Ink response and keyboard activation remain functional |
| Focused | default fill + outside 2px `#2563EB` / `#93C5FD` | focus-aware launcher decoration | FocusNode lifecycle, traversal and semantics |
| Menu open | pressed visual | `_overlay != null` launcher state | Toggle/close behavior, route callbacks, cache revalidation and Escape dismissal |
| Shadow | offset `(0,8)`, blur `18`, spread `-4`, `rgba(8,18,56,.20)` | explicit `BoxShadow`; no generic Material elevation | Exact Light/Dark visual recipe |
| Icon | Phosphor Lightning Regular `20×20` | existing `PhosphorIconsRegular.lightning` | no new asset/package; approved foreground semantics |
| Accessibility | label `Mở Thao tác nhanh`; tooltip `Thao tác nhanh` | existing `Semantics` and shell tooltip | Vietnamese-first accessible name and 48dp target |

## Planned files

- `lib/app/theme/app_colors.dart`
- `lib/app/navigation/app_shell.dart`
- `lib/features/quick_actions/presentation/quick_actions_launcher.dart`
- `test/quick_actions_launcher_test.dart`
- `test/app_shell_route_viewport_test.dart`
- This plan, then move it to `docs/plans/completed/` only after all local and
  publication proof is complete.

## Affected consumers and proof

- Primary: FIFO Check at compact `375×812`, Light and Dark.
- Shared-shell regression: Home, Operations, Notifications and Account at
  compact width when Quick Actions are available.
- Availability regression: user without Quick Actions renders four destinations
  and no empty fifth slot.
- Behavior regression: open/close menu, cache revalidation, route selection,
  keyboard focus/Escape and existing Windows 64px launcher geometry.
- Geometry proof: slot `84×68`, button `48×48`, button top offset `10`, radius
  `20`, icon `20`, exact colors/shadow/focus ring and no bottom-nav clipping.

## Implementation sequence

1. Add the smallest context-aware navigation pressed/focus token helpers.
2. Make the compact launcher render exact default/pressed/focused/menu-open
   decoration while preserving the Windows 64px circular path.
3. Give the mobile shell an explicit 84×68 slot and 10px top placement.
4. Update focused launcher and AppShell geometry/state tests.
5. Run format, focused tests, analyzer, full tests, Web release build and final
   diff review.
6. Record proof in Linear, commit/push, open PR to `staging`, wait for CI/QA,
   merge, run guarded lifecycle `finish`, then open a promotion PR from exact
   `origin/staging` to `main`.

## Verification commands

```powershell
dart format --output=none --set-exit-if-changed <changed-dart-files>
flutter test --no-pub test/quick_actions_launcher_test.dart test/app_shell_route_viewport_test.dart
flutter analyze --no-pub
flutter test --no-pub --reporter compact
flutter build web --release --no-pub
git diff --check
git status --short --branch
git diff --stat
git diff -- <owned paths>
```

## Recovery and stop conditions

- Never edit canonical `staging`, reset/rebase protected branches, or overwrite
  unrelated work.
- Stop if `origin/staging` or this worktree HEAD changes unexpectedly, Figma
  authority changes, another writer edits owned paths, CI fails outside the
  bounded patch, or authenticated staging proof cannot identify the exact SHA.
- Revert only this bounded task patch via a reviewed inverse patch.
- Any post-proof source/test/plan edit invalidates downstream evidence and
  requires rerunning it.
- Do not merge staging or open the promotion PR until required checks and exact
  SHA evidence pass. Do not merge the main promotion PR without a separate
  explicit user command if repository protection requires final approval.

## Progress

- [x] Lifecycle dry-run and `start --execute` passed.
- [x] Exact latest `origin/staging` checkpoint recorded.
- [x] Approved Figma component/state board read back.
- [x] Reviewable node map and affected-consumer matrix recorded before code.
- [x] Implement shared Flutter parity.
- [x] Complete focused and broad local proof.
- [ ] Push and merge the staging PR after CI/QA.
- [ ] Run lifecycle finish and open the main promotion PR.

## Local proof — 2026-08-12

- Focused launcher and AppShell tests: 39 passed.
- `flutter analyze --no-pub`: passed with no issues.
- `flutter test --no-pub --reporter compact`: passed (exit 0).
- `flutter build web --release --no-pub`: passed; Web release bundle built and
  Wasm dry run succeeded.
- Dart format check: five owned Dart files formatted, zero changes required.
- `git diff --check`: passed after proving and restoring content-identical
  generated localization line-ending noise.
- Protected consumers exercised: FIFO compact shell, Home, Operations,
  Notifications and Account destination mapping, unavailable four-slot shell,
  Light/Dark launcher states, menu behavior, focus/semantics, and legacy
  Windows launcher geometry.
- Remaining visual proof: exact deployed staging SHA and authenticated Chrome
  comparison at `375×812` in Light/Dark before visual completion or promotion.
