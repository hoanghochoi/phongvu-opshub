# OPS-53 Home responsive fixes

## Status

Active — the original Figma node-map approval and R2 candidate are superseded
by the Foundation-backed R3 shell revision. Đại Ca explicitly directed that
the Foundation app bars are authoritative; implementation and proof are now
in progress on the task branch.

## Checkpoint

- Canonical `staging` and task branch start at `a8cda2637355d715a1671d4cfd3ce74d0a5d035d`.
- Task worktree: `phongvu-opshub-ops-53`.
- Branch: `codex/ops-53-home-responsive-fixes`.
- Worktree was clean before this plan file was added.

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
materially changed the shell source. The Foundation-backed R3 node map is the
approved visual authority for this task. Do not implement from the pre-R3
frames.

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
- Verified: affected shell tests `28` pass, Home tests `36` pass, full Flutter
  suite `782` pass with `3` pre-existing skips, full analyzer pass, and
  `flutter build web --release --no-pub` pass.
- Remaining: commit/push/PR, staging deploy, authenticated Chrome matrix, and
  Linear proof readback.

## Recovery

Keep changes on the task branch. If the Figma contract changes, re-read the
exact nodes and rerun the downstream geometry and visual proof from the new
node map; do not reuse stale screenshots or test fingerprints.
