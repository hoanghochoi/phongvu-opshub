# OPS-53 Home responsive fixes

## Status

Active — the Foundation-backed R3 shell revision remains authoritative. Đại Ca
approved the compact Variant A two-row control revision and authorized the
implementation → PR → staging merge → lifecycle cleanup flow.

## Checkpoint

- Canonical `staging` and task branch start at
  `d5483d2a00b4a7f87d4986024e3b4f6309ac4c38`.
- Canonical worktree was clean and `origin/staging` matched before start.
- Task worktree: `opshub-ops-53-compact-long-label`.
- Branch: `codex/ops-53-compact-long-label`.
- Task worktree is clean before implementation.

## Approved incremental scope — compact Variant A

Figma file `mFzSmQzlapSe3RSmUhvzll`, exact approved nodes:

- [Light Variant A — 375×812](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2182-61297)
  (`2182:61297`)
- [Dark Variant A — 375×812](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2182-61399)
  (`2182:61399`)

Node map for the changed compact controls:

| Visible element/state | Exact geometry/copy | Shared Flutter mapping |
| --- | --- | --- |
| Dashboard controls lane, Light/Dark, loaded long-copy | `x=17`, `y=125`, `w=303`, `h=136`; `surface/sunken`, radius 8, 40px controls, 8px row gap | `HomeSummaryHeader` → `_HomeScopeDateControl` inside the compact header |
| Scope control | Full lane width `303×40`, `y=0`; `Phạm vi: Toàn hệ thống`; caret 16px | `_HomeHeaderChip` with `showCaret: true`, shared `AppTextStyles.bodyS`, `AppColors.chipBackgroundOf` |
| Date control | Full lane width `303×40`, `y=48`; `Khoảng ngày: Tất cả ngày`; caret 16px | `_HomeHeaderChip` with `showCaret: true`, canonical `AppDateRangeDropdown` behind the shared menu trigger |
| Refresh metadata | Full lane width `303×40`, `y=96`; info icon 16px; Vietnamese update copy | Existing keyed `_HomeHeaderChip` refresh action and `AppLogger`/provider behavior unchanged |
| Foundation shell and content | Foundation topbar, greeting, overview/cards, Light/Dark surfaces | Existing shared shell/theme/widgets; no new local app bar or fallback path |

The compact control lane is the only visual mutation in this follow-up. Scope
selection, date-range behavior, refresh behavior, provider/API/permission
contracts, and the approved Foundation shell remain protected.

## Figma scope — revision candidate R3

File `mFzSmQzlapSe3RSmUhvzll`, section `2126:60779`, page
`Screens — Desktop · Windows + Web`:

- `2129:60779` compact Light loaded/long-copy
- `2132:60793` compact Dark loaded/long-copy
- `2132:60897` medium Light loaded/long-copy
- `2132:61001` medium Dark loaded/long-copy
- `2133:60835` compact Light loading
- `2133:60944` compact Dark loading
- `2133:61051` medium Light loading
- `2133:61158` medium Dark loading

The map covers `375×812` and `834×1112`, Light/Dark, loaded long-copy and
loading states, Home controls, progress overview, refresh replacement,
notification unread treatment, shared shell, and responsive constraints.
R3 replaces the hand-built R2 app bars with the approved Foundation sources:
compact frames use `228:3` (`shell_topbar`, Mobile App Shell `228:2`) with
compact notification action `2091:146729`; medium frames use `229:75`
(`shell_topbar` from Tablet App Shell `229:60`) with Foundation notification
and account-avatar actions. The proposal bottom destinations remain exactly
`Trang chủ`, `Vận hành`, `Thông báo`, and `Tài khoản`.

R3 replacement node IDs:

- Compact topbars: `2146:2`, `2146:8`, `2146:26`, `2146:32`.
- Medium Foundation rails: `2150:135`, `2150:144`, `2150:162`, `2150:178`.
- Medium topbars: `2150:138`, `2150:147`, `2150:165`, `2150:181`.
- Superseded custom topbars: `2129:60780`, `2132:60794`, `2132:60898`,
  `2132:61002`, `2133:60836`, `2133:60945`, `2133:61052`, `2133:61159`.

Medium now follows Foundation tablet composition: rail + tablet topbar and no
mobile bottom navigation. Home content is fitted to the `698px` main lane with
`24px` inner gutters; progress/store cards use `698px`, store columns use
`206px + 16px` gaps, and the medium loading state note is right-inset at
`16px`. The eight-frame structural readback passed; all eight exact-size
screenshots rendered at `375×812` or `834×1112`, and representative Light/Dark
loaded/loading screenshots were visually checked with no shell/content
clipping. Exact-node approval is recorded by Đại Ca's current direction to
use the Foundation shell sources. R2 comment
`7761edb9-9d96-4718-9672-262736e059bd` must not be treated as current approval
evidence.

Authority note: Foundation mobile source `228:2` explicitly contains the
compact notification action, while the current product contract says mobile
should not duplicate a notification entry in the app bar. Đại Ca's latest
direction selected the Foundation source; the compact notification action is
implemented and covered by shell regression proof.

## Approval gate

The original node-map approval and R2 approval evidence are stale because R3
materially changed the shell source. The Foundation-backed R3 node map plus the
approved compact Variant A nodes above are the visual authority. Do not
implement from the pre-R3 frames or infer a missing compact geometry.

## Affected consumers and proof

- Home source: `lib/features/home/presentation/widgets/home_summary_page.dart`
  and `lib/features/home/presentation/screens/home_screen.dart`.
- Shared shell: `lib/app/navigation/app_shell.dart` and its navigation tests.
- Provider/runtime behavior: `lib/features/home/presentation/providers/home_summary_provider.dart`.
- Primary tests: `test/home_dashboard_test.dart`, shared shell/avatar/support
  tests, and affected route/state consumers identified by CodeGraph.
- Required final proof: geometry/widget tests for every changed viewport/state,
  `dart format`, `git diff --check`, `flutter analyze --no-pub`, focused and
  full Flutter tests, web build, then exact authenticated staging Chrome
  captures at `375×812`, `834×1112`, `1024×768`, and `1440×900` in both themes.

## Progress

- Figma readback completed for Foundation compact `228:3`/R3 `2146:2` and
  tablet `229:75`/R3 `2150:138`; R2 custom app-bar nodes are excluded.
- Runtime now uses the Foundation compact notification action and the
  Foundation tablet rail/topbar at `600–899`, with no medium bottom nav.
- Home loading/header/overview geometry is updated for the approved R3
  compact and medium states; long-copy and loading layouts have no test
  overflow.
- Variant A implementation now stacks the compact scope/date controls at
  `y=0`/`y=48` and keeps refresh metadata at `y=96`, all full-width in the
  approved compact lane; provider/date-picker/refresh behavior is unchanged.
- Verified: Home tests `38` pass including Light/Dark Variant A geometry and
  exact long-copy assertions, full Flutter suite `785` pass with `3`
  pre-existing skips, `flutter analyze --no-pub` pass, and
  `flutter build web --release --no-pub` pass.
- Remaining: commit/push/PR, staging deploy, authenticated Chrome matrix,
  Linear proof readback, and lifecycle cleanup.

## Recovery

Keep changes on the task branch. If the Figma contract changes, re-read the
exact nodes and rerun the downstream geometry and visual proof from the new
node map; do not reuse stale screenshots or test fingerprints.
