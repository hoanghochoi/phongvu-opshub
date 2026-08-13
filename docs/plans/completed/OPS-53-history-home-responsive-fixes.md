# OPS-53 Home responsive fixes

## Status

Active — authenticated staging audit found one final Windows FAB visual parity
gap; the corrective branch is in implementation and verification.
Đại Ca approved the four REVIEW nodes, authorized self-approval for any
additional OPS-53 nodes, and authorized one accumulated PR → staging merge →
authenticated Chrome audit → lifecycle cleanup flow.

## Checkpoint

- Canonical `staging` and the current task branch start at
  `dd637d4afe70e129b7d34a8985ac841f15461247`.
- Canonical worktree was clean and `origin/staging` matched before start.
- Task worktree: `phongvu-opshub-ops-53-final-residuals`.
- Branch: `codex/ops-53-final-residual-fixes`.
- Task worktree is clean before implementation.

## Approved final residual scope

- Follow-up Light `2190:151155` and Dark `2190:151217`.
- Profile password dialog Light `2194:23395` and Dark `2195:23521`.
- Sales Reports compact row `380:8036`; notification unread variants
  `2100:56208`.
- Quick Actions compact component `406:16778`, Support topbar action `228:675`,
  and Windows Home FAB stack `1771:100236` / `2003:144239` /
  `2003:144331`.
- Replace every production Material `Icons.*` usage with a semantic
  `PhosphorIconsRegular` equivalent, migrate icon assertions/fixtures, and add
  a repository guard against regressions.
- Preserve the approved Windows Home `64×64` Lightning/Headset stack with a
  `12px` gap even when quick actions or in-app support are unavailable; denied
  actions remain disabled and Support retains the existing Seatalk fallback.
- Restore first-shell logo rendering by preloading the active brand asset
  before `runApp`, with sanitized start/success/failure logs and a timeout.

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
- Final residuals implemented: notification count caps at `99+`; compact
  Sales Reports and Follow-up action rows match the approved `375px` geometry
  and shrink safely at `360px`/`320px`; password dialog copy/geometry and eye
  controls match the four approved REVIEW nodes.
- Quick/Support Windows Home stack is fixed at `64×64`, Lightning `24px`,
  Headset `28px`, `12px` gap, right `16px`, bottom `24px`; non-Windows and
  non-Home Support offsets retain their previous contract.
- Material icon migration completed across `65` production Dart files and all
  affected tests; `rg '\bIcons\.' lib test --glob '*.dart'` returns no hits.
- The post-merge audit re-read Quick Actions `406:16778`, Support `228:675`,
  and Windows stack `1771:100236` / `2003:144239` / `2003:144331`. It found
  that the Windows Quick Action still inherited the compact 20px rounded
  rectangle and Windows Support retained the default light FAB colors. The
  corrective branch makes the 64px Quick Action circular and gives the Windows
  Support FAB the approved primary surface/foreground while preserving the
  compact bottom-navigation shape and non-Windows Support styling.
- Pre-corrective proof for merged PR #134 / staging SHA `6de35c2a`:
  `flutter analyze --no-pub` pass; full Flutter suite `768` pass with `3`
  skips; Web release build pass; Windows release build pass; independent code
  review reported no blocker.
- The corrective candidate must rerun analyzer, the focused shared-shell/Quick/
  Support tests, the full Flutter suite, Web release build, Windows release
  build, Material-icon guard/scan, and independent review on one unchanged
  fingerprint before publication. Staging Chrome proof is rerun only after the
  corrective merge is deployed at its exact SHA.
- Android release proof is signing-blocked because the local keystore variables
  are absent. Android debug Gradle produced both production and staging APKs,
  although Flutter's wrapper returned non-zero because it did not recognize
  the flavor-specific output names.
- Remaining: Linear implementation/proof note and readback, commit/push/PR,
  staging CI/deploy, authenticated Chrome matrix, and lifecycle cleanup.

## Recovery

Keep changes on the task branch. If the Figma contract changes, re-read the
exact nodes and rerun the downstream geometry and visual proof from the new
node map; do not reuse stale screenshots or test fingerprints.
