# Execution Plan: OPS-44 Redesign Foundation Runtime And UI Retirement

Date: 2026-08-03
Last updated: 2026-08-04 (Support Chat state authority proposal + Figma inventory readback)

## Status

Active

## Outcome

Đưa visual/interaction foundation hiện hành của Figma OpsHub vào shared Flutter
layers và migrate toàn bộ declared route surfaces theo các wave có thể rollback.
UI legacy chỉ được retire sau khi không còn consumer và có affected-consumer
proof; business, API, permission, platform và data behavior giữ nguyên.

## Context

- Linear: OPS-44, related OPS-25 and OPS-34.
- Git baseline: `origin/staging` at
      `5f935de9b2417e1b7ba138026b875bf6329bfbbe`; the guarded execution branch
      `codex/ops-44-execution-plan-v2` is clean at head
      `9674a83bbb61238bbd709f0a9a88696a205583cf` (runtime checkpoint
      `1224a8ad228d04c63bac55e502fca2ba26971050`).
- Figma file:
  `mFzSmQzlapSe3RSmUhvzll`; target pages Cover `0:1`, Foundation `13:5`,
  Desktop + Web `693:17492`, Android mobile `693:17493`, Android tablet `698:2`,
  iOS mobile `1174:2`, and iPadOS tablet `1174:3`. Former Web page `1174:4`
  is now named `ARCHIVE — Web Responsive (empty · pending deletion)` after the
  Phase 1 migration and remains pending destructive delete.
- Figma audit before migration: 8 pages, 393 variables, 21 text styles, 4
  effect styles, 906 reusable foundation sources, no missing fonts; 43
  canonical visual route surfaces plus `/reports` redirect and
  `/fifo/inventory-import` alias. Post-migration target is 7 canonical pages.
- Runtime authority: `AGENTS.md`, `docs/WORKFLOW.md`, product UI contract,
  redesign workflow, `AppRouter` and existing tests.

## Scope

In scope:

- Reconcile foundation docs, 45 current router declarations, compatibility
  aliases, Figma page inventory and visual-smoke route coverage.
- Map Figma primitives/semantics/components into existing `AppColors`,
  `AppTextStyles`, `AppRadius`, `AppLayoutTokens`, `AppTheme` and shared widgets.
- Migrate shared primitives, shell/auth/system, pilot, operational, admin and
  long-tail surfaces in dependency order.
- Add/update focused tests, affected-consumer proof, staging build evidence,
  Chrome audit and platform evidence.
- Record Figma revisions and Linear decisions whenever a technical constraint
  changes the approved visual target.

Out of scope:

- Big-bang rewrite or deletion of legacy runtime/API compatibility layers.
- Business/API/data/permission/platform/security behavior changes.
- Be Vietnam Pro runtime cutover before local assets, license/provenance,
  fallback and Android/Windows/web proof are complete.
- Direct push, merge, production promotion or marking OPS-44 Done without the
  required release gates.

## Approach

1. Reconcile current docs and smoke guards with the live Figma target pages and
   current router; preserve redirect/alias semantics.
2. Capture affected consumers for shared theme, shell, inputs, DateRangePicker,
   command bar, state panels, dialogs and pagination.
3. Implement shared foundation in bounded batches, running focused proof after
   each batch; keep compatibility aliases until consumer migration is proven.
4. Migrate shell/auth, pilot, operational, admin and long-tail route groups.
5. After each merged wave reaches staging, run staging smoke and Chrome audit;
   classify findings as code defects or Figma revision/re-approval work.
6. Remove legacy visual consumers only after route/consumer proof and a
   rollback-ready checkpoint; update Linear with exact evidence before status
   transitions.

## Risks And Recovery

- Shared theme/shell changes have a large blast radius; use existing token APIs,
  focused consumer tests and revertable task branches.
- Figma/code drift: stop the affected batch, create a Figma revision, record
  the blocker and wait for re-approval before continuing that visual change.
- Font assets may remain unavailable; preserve current SF Pro Display on
  unmigrated surfaces and do not silently mix font families.
- Staging/Chrome credentials and Cloudflare Access are protected inputs; never
  place them in commands, issue text, logs or screenshots.

Recovery: use the task branch/PR revert path through `staging`; do not reset,
rebase or force-push protected branches. Retain prior shared component behavior
until the replacement has affected-consumer proof.

## Progress

### Phase 0 — baseline guard

- [x] Confirm canonical `staging` and `origin/staging` at
      `5f935de9b2417e1b7ba138026b875bf6329bfbbe`.
- [x] Start guarded worktree (now carrying the single ongoing branch
      `codex/ops-44-execution-plan-v2`) from the
      exact live staging SHA.
- [x] Replace Home transparent Material surfaces with `AppColors.transparent`
      and update the reviewed inline-progress allowlist to cover the existing
      toolbar refresh and header chip action states.
- [x] Phase 0 focused proof: migration guard, theme tokens and AppShell route /
      viewport tests pass 46/46; `flutter analyze --no-pub` reports no issues;
      `git diff --check` passes on the content diff.
- [x] Record the Phase 0 implementation/proof note on Linear OPS-44; issue
      readback confirms the new Execution plan v2, Phase 0 checkmark and
      `In Progress` status.

### Phase 1 — Figma authority and first visual retirement batch

- [x] Confirm live Home authority: Desktop Windows `326:2698`,
      `/home · App Shell Desktop · Loaded · Runtime scroll`; the historical
      `485:2` node is deleted and is not an implementation source.
- [x] Record the Home node map in Linear before the production UI edit:
      `326:2698` → `HomeScreen`/`HomeSummaryPage` → shared `AppShell`,
      `AppStatePanel`, `AppLayoutTokens`, `AppTextStyles`, `AppColors`; the
      protected provider/API/permission/refresh/detail behavior remains in the
      existing Home provider and summary widgets.
- [x] Replace the unreachable Home provider-missing legacy visual branch with
      the Foundation loading state while retaining the approved Home header.
- [x] Consolidate the live Web page structure into Desktop + Web: all Web-only
      nodes were moved/deduped into `693:17492`; the former Web page is empty.
- [x] Rename live Figma page `693:17492` to `Screens — Desktop · Windows + Web`
      and rename empty page `1174:4` to `ARCHIVE — Web Responsive (empty ·
      pending deletion)`; page inventory readback passes.
- [ ] Approve the unified Figma revision and delete the empty Web page `1174:4`
      (destructive action still requires explicit revision approval).
- [x] Confirm Android Tablet route ownership: current page `698:2` has 46
      top-level nodes and 43 route owners covering the full canonical route
      inventory; the pre-coverage audit found no Dark-named route/state frame.
- [x] Add approved Dark route/state coverage on the unified Desktop + Web page:
      board `1874:35444` contains 121 cloned route/state owners, all named
      `DARK / ...`, with `OpsHub Semantics=Dark` (`4:2`) and
      `OpsHub Components=Dark` (`6:0`) explicit modes. The board stays on the
      existing seven-page target and does not alter Light sources.

### Phase 2 — shared foundation cleanup

- [x] Remove unused `AppTheme` legacy color accessors and the unused
      `legacyDesktopBreakpoint` alias after repository consumer search found no
      runtime consumers.
- [x] Remove the unused light-only `AppStateTone.color` compatibility getter
      after repository consumer search; all state/chip consumers use the
      context-aware semantic mapping.
- [ ] Converge remaining shared primitive aliases after affected-consumer proof.
- [x] Align shared responsive page padding with the approved Figma breakpoint
      contract: compact `<600` = 16 px, medium/expanded `600–1199` = 24 px,
      wide `>=1200` = 32 px. The wrapper now classifies from viewport width,
      not the shell's already-bounded content width; focused layout/Operations/
      AppShell proof passes 28/28.

### Phase 3 — Operations route visual migration wave

- [x] Node map is recorded before the edit for every affected viewport/state:
      Desktop/Web Loaded `283:1319` (content `283:1358`, 1190 × 828,
      route padding 32), Android Mobile Loaded `283:1359` (content `283:1386`,
      375 × 664, padding 16), Android Tablet Portrait `698:17660`
      (content `698:17661`, 746 × 1040, padding 24), Android Tablet Landscape
      `698:18412` (content `698:18413`, 936 × 696, padding 24), and the
      medium 600 × 960 authority `1419:24532` (content `1419:24533`, padding
      24). Section/action geometry is fixed by the approved nodes: section
      header 24 px, header-to-row gap 12 px, action height 96 px, action gap
      12 px on one-column views and 16 px on the wide three-column row.
- [x] Adapt `AppResponsiveScrollView` and `OperationsScreen` to that node map
      using shared `AppLayoutTokens`; preserve `AppNavModel` visibility,
      route taps, refresh and `AppLogger` behavior unchanged.
- [x] Add geometry/token proof for compact, medium, expanded and wide widths
      and run the affected Operations/AppShell consumer suite before any
      downstream build/audit gate (28/28 pass).
- [x] Map the shared State Panel foundation node `1793:16377` to
      `AppStatePanel`/`AppStatusBanner`; tone colors and the VietQR status chip
      now resolve the approved Light/Dark semantic mode through `AppColors`,
      with state/theme/VietQR focused proof passing.

### Phase 4 — Remaining route/state consumer retirement

- [x] Reconcile every declared route against the seven-page Figma authority:
      router has 45 `path:` declarations; Desktop/Web exposes 44 route owners
      including `/shell-topbar`, Mobile exposes 43, and Tablet exposes all 43
      canonical routes through its nested portrait/landscape rail sections;
      iOS and iPadOS each expose the same 43 canonical routes.
      `/reports` remains a redirect and `/fifo/inventory-import` remains an
      alias of the canonical Inventory Import screen, so neither creates a
      duplicate Figma owner.
- [ ] Complete the per-state/viewport matrix for every route, including
      loading, empty, permission, retryable error, dialogs and platform
      unsupported states; any missing runtime node must follow the proposal,
      readback and approval gate below before code changes.
- [ ] If runtime exposes a state or visible element without an approved node,
      stop code work, add/revise that node in the correct Figma page using the
      `figma-use` atomic workflow, read back metadata and screenshot, retrieve
      `get_design_context`, record the new node/revision in this plan and Linear,
      then wait for explicit approval before implementation.
- [x] Notifications runtime parity gap is now represented by the explicitly
      pending proposal section `1881:59087` on Desktop + Web, built from the
      approved notification instances and covering transaction/request times,
      requester, reason and content lines. Metadata readback and screenshot
      pass; this proposal is not a production authority until approved.
- [x] Home speaker-status runtime gap is now isolated in pending Figma proposal
      `1888:59111` (`PROPOSAL — Home speaker status · Pending approval`). The
      approved Home chain `326:2698` → `326:2731` → `326:2732` has no speaker
      node, while the protected Windows runtime contract requires `Loa đang
      bật/tắt` plus the existing toggle/provider/AppLogger behavior. Proposal
      metadata, screenshot and `get_design_context` readback pass; no Home
      visual edit is authorized until explicit approval.
- [x] Support Chat runtime-state gap is now isolated in pending Figma proposal
      `1898:107163` (`PROPOSAL — Support Chat runtime states · Pending approval`).
      The proposal covers inbox/thread loading, empty, retryable error,
      permission, selected-thread and responsive desktop, tablet portrait,
      tablet landscape and mobile states. Metadata, screenshot and
      `get_design_context` readback pass; no production visual edit is
      authorized until explicit Figma approval.

#### Figma gap/action ledger — 2026-08-04

All rows below have a named proposal node, metadata readback, screenshot
readback and `get_design_context` evidence. “Pending approval” is an explicit
visual gate: runtime code must keep the protected behavior but must not invent
the missing visual element/state.

| Runtime gap | Figma proposal | Protected runtime behavior | Next gate |
| --- | --- | --- | --- |
| Notifications content parity | `1881:59087` | unread/read, requester/reason/content, action feedback | Approve proposal, then implement Desktop/Web + mobile parity |
| API Connections dynamic clients/keys | `1883:59093` | repository mutations, confirmation, secret/key handling, logger | Approve proposal, then implement populated cards |
| API Connections supported Web compact/medium | `1895:59111` | Web capability remains supported; Android unsupported guard unchanged | Approve proposal, then implement Web responsive geometry |
| Settings speaker voice card | `1884:59093` | speaker preference provider, combobox selection, startup/theme behavior | Approve proposal, then implement Desktop/mobile/tablet card |
| Home speaker ON/OFF status | `1888:59111` | existing toggle/provider/AppLogger contract; Windows-only visibility | Approve proposal, then make Home regression green |
| Sales Reports managed filter | `1891:59111` | existing `Lọc` trigger, advanced sheet, provider scope/filter behavior | Approve proposal, then implement compact/medium trigger states |
| Support Chat inbox/thread states | `1898:107163` | auth/session, thread selection, retry/permission, composer/realtime behavior | Approve proposal, then implement responsive state matrix |

The destructive archive-page action is tracked separately: page `1174:4`
(`ARCHIVE — Web Responsive (empty · pending deletion)`) can be deleted only
after explicit unified-revision approval and a final seven-page inventory
readback.
- [ ] Home speaker-status implementation gate: after approval, map the exact
      ON/OFF node/revision into `HomeSummaryHeader`, add geometry proof for the
      approved Windows width matrix, and rerun Home/AppShell affected consumers.
- [x] Super Admin delivery-metrics consumer proof now sets the test viewport to
      the approved wide Desktop/Web contract (`1440×900`); the compact shell
      intentionally omits the metrics pill. Focused run confirms this test
      passes, while the Windows speaker test remains blocked by the missing
      approved Figma node above.
- [x] API Connections bounded wave — node map captured before code edit:
      Windows/Web loaded `1704:134596` → route shell instance `1704:134597`,
      header `1730:34726`, content `1730:34729`, BIDV connection card
      `1730:34730`, operations controls `1730:34739`, and OpenPGP management
      `1730:34754`; Android Mobile unsupported `1704:134781` → header
      `1729:121823`, state card `1729:121826`; Android Tablet unsupported
      `1704:134853` → header `1729:134625`, state card `1729:134628`.
      `get_design_context` and metadata readback were completed for all three
      exact authority nodes. Map to `ApiConnectionAdminScreen` and existing
      `AppResponsiveContent`/`AppResponsiveScrollView`, `AppSurfaceCard`,
      shared buttons, switches and state panels; preserve repository actions,
      platform capability guard, API contract, mutation confirmation and
      `AppLogger` branches. No mobile/tablet supported state is invented.
- [ ] API Connections implementation gate: replace the generic legacy visual
      branch with the one Figma path above, add compact/medium/wide geometry
      proof plus affected API-connection/admin/router tests, then rerun
      analyzer/format/diff checks. Staging/Chrome/platform proof remains
      downstream and is required before retiring the old visual consumers.
- [x] API Connections dynamic-state gap is now isolated in pending proposal
      `1883:59093` (`PROPOSAL — API Connections dynamic states · Pending
      approval`). It reuses the approved BIDV/OpenPGP cards and covers a
      non-empty OAuth client plus active OpenPGP key. Metadata and screenshot
      readback pass; this proposal is not production authority until explicit
      Figma revision approval, so supported client/key visual code remains
      unchanged for now.
- [x] API Connections Web responsive authority gap is now isolated in pending
      proposal `1895:59111` (`PROPOSAL — API Connections supported Web
      responsive · Pending approval`). The proposal covers Web compact
      `375×812` (343px lane) and Web medium `834×1112` (714px lane), reuses
      the approved Desktop/Web BIDV/controls/OpenPGP anatomy, and explicitly
      distinguishes Web-supported behavior from Android unsupported nodes
      `1704:134781` / `1704:134853`. Metadata and screenshot readback pass;
      no responsive Web visual edit is authorized until approval.
- [x] API Connections Android unsupported state now uses the approved shared
      card/state path with exact Vietnamese copy and 236 px card geometry;
      focused API/admin/router/shell/guard proof passes `65/65`, and
      `flutter analyze --no-pub` plus format/diff checks pass. The supported
      Windows/Web dynamic path remains open pending the proposal above.
- [x] Sales Reports bounded wave — node map captured before the production UI
      edit for the complete loaded viewport matrix:
      - Desktop/Web `380:7944` (shell) → `380:7977` (content,
        1126 px inner lane) → `380:7980` (cockpit controls, 1126×132) →
        `380:8008` (Chưa báo cáo column) + `380:8011` (Đã báo cáo column),
        with order lookup `380:8144`.
      - Android Mobile `380:8036` (shell) → `380:8059` (content, 343 px) →
        `380:8062` (cockpit controls, 343×228) → `380:8076` and `380:8079`
        stacked columns, with order lookup `380:8197`.
      - Android Tablet Portrait / medium 834 `842:30719` (shell) →
        `842:30784` (content, 714 px lane) → `842:30785` (cockpit controls) →
        `842:30790` and `842:30803` stacked columns, with order lookup
        `842:31014`.
      - Android Tablet Landscape / expanded 1024 `842:30814` (shell) →
        `842:30917` (content, 936 px lane) → `842:30918` (cockpit controls,
        904×228) → `842:30923` and `842:30936` side-by-side 444×360
        columns, with order lookup `842:31135`.
      Visible map: shared shell/topbar and responsive rail, page title/subtitle,
      date/showroom/filter/reload cockpit controls, manual purchased and
      not-purchased actions, status column headings with count (`Chưa báo cáo •
      N`, `Đã báo cáo • N`), order/report cards, status badges, pagination and
      order-lookup dialog. Loading/empty/retryable error remain the approved
      Foundation State Panel authority. Map to `SalesReportScreen`,
      `_SalesReportCockpit`, `_QuickFilterBar`, `_OrdersColumn`, shared
      `AppSurfaceCard`/buttons/combobox/date-range/pagination/state widgets;
      preserve provider/API/permission/realtime/dialog/AppLogger behavior.
- [x] Sales Reports approved loaded path implementation gate (local proof):
      Desktop/Web now uses the exact wide control lane and 555×514 two-column
      cards; expanded tablet uses 904×228 controls and side-by-side 360px
      columns; medium portrait and mobile use 228px stacked controls and 360px
      stacked columns; mobile/tablet hide the desktop-only title. Count headers,
      order/report cards, Vietnamese badges and report action now follow the
      exact Figma composition. Geometry proof passes the full
      `1440×900`, `1024×768`, `834×1112`, `375×812` matrix; the Sales Reports
      affected suite passes `27/27`; provider/API/permission/realtime/dialog
      and AppLogger behavior remain covered.
- [ ] Sales Reports compact/medium managed-scope advanced filter remains an
      authority gate: runtime behavior still needs the existing `Lọc` trigger
      and `_AdvancedFilterSheet`, but the approved compact/portrait nodes do
      not contain that visible element. Pending Figma proposal
      `1891:59111` (`PROPOSAL — Sales Reports managed filter · Pending approval`)
      records the compact `375×812` and medium `834×1112` state matrix,
      closed/active trigger states, preserved sheet/provider behavior, and the
      exact loaded node chain. Metadata and screenshot readback passed. Do not
      retire the compatibility trigger or call the full Sales Reports visual
      wave complete until the proposal gets an approved node/revision.
- [x] Settings bounded wave — node map captured before code edit:
      Desktop/Web Loaded `385:9054` → content `385:9087`, theme card
      `385:9094`, Windows card `385:9102`; Android Mobile Unsupported
      `385:9113` → content `385:9136`, theme `385:9143`, Windows
      `1261:86671`; Android Tablet Portrait Unsupported `842:31755` →
      content `842:31820`, theme `842:31823`, Windows `842:31831`; Android
      Tablet Landscape Unsupported `842:31835` → content `842:31938`, theme
      `842:31941`, Windows `842:31949`. Runtime startup states have exact
      authority nodes for loading `1261:86677`, saving `1261:86702` and error
      `1261:86727`. `get_design_context` + metadata readback passed for all
      affected nodes. Map to `SettingsScreen`, `ThemeProvider`, shared cards,
      combobox/theme controls and startup service; preserve theme, Windows
      startup, speaker configuration, refresh and `AppLogger` behavior.
- [x] Settings implementation gate (local proof): `SettingsScreen` now has one
      Figma-backed visual path: Desktop/Web uses two 555×230 cards, while
      compact/medium/expanded uses one 343 px column with the approved 188 px
      theme card and 166/188 px Windows state card. Supported loaded startup
      uses the shared 40×24 switch/hit-area contract; loading, saving, error and
      unsupported states use the approved Vietnamese state badges and do not
      render a switch. `settings_screen_redesign_test.dart` passes 4/4,
      including desktop/tablet geometry and loading/saving/error proof;
      relevant migration-guard checks, targeted analyzer, format and
      `git diff --check` pass; a fresh repository-wide `flutter analyze --no-pub`
      also passes with no issues. Staging/Chrome/platform proof remains
      downstream and is required before retiring the old visual consumers.
- [x] Settings speaker-voice authority gap is isolated in pending Figma
      proposal `1884:59093` (`PROPOSAL — Settings speaker voice card · Pending
      approval`). It reuses the approved Settings card geometry and canonical
      Combobox instance, covering runtime label/value/helper copy for Desktop
      (`1884:59096`, 555×230), Mobile (`1885:59099`, 343×188) and Tablet
      (`1885:59109`, 343×188). Metadata, screenshot and `get_design_context`
      readback pass; this proposal is not production authority until explicit
      Figma approval, so Settings code was not changed for this missing
      surface.
- [x] Profile bounded wave — node map captured before code edit:
      Desktop/Web Loaded `305:3111` → content `305:3147`, header `306:3204`,
      session `306:3219`, details `306:3226`, edit `306:3227`, info `306:3245`;
      Android Mobile Loaded `305:3148` → content `305:3175`, header `306:3271`,
      session `306:3286`, edit `306:3293`, info `306:3311`; Android Tablet
      Portrait `839:2666` → content `839:2731`, header `839:2732`, session
      `839:2733`, edit `839:2734`, info `839:2735`; Android Tablet Landscape
      `839:2854` → content `839:2957`, header `839:2958`, session `839:2959`,
      edit `839:2960`, info `839:2961`. `get_design_context` + metadata
      readback passed for all four viewport nodes. Map to `ProfileScreen`,
      shared form/input/card/dialog/avatar components and existing auth
      provider/media/logger behavior; preserve profile save, avatar upload,
      password dialog, logout confirmation and permission data.
- [x] Profile implementation gate (local proof): converged responsive content
      gutters, card geometry and status/session surfaces to the exact nodes;
      compact `375×812`, tablet `768×1024` and wide `1280×900` geometry tests
      pass with no overflow. Affected Profile/AuthProvider/session/avatar,
      router, AppShell viewport and migration-guard suite passes `82/82`;
      `flutter analyze --no-pub`, format check and `git diff --check` pass;
      `flutter build web --release --no-pub` passes with the Wasm dry run
      succeeding on the current worktree.
      Staging deploy, authenticated Chrome comparison and primary-platform
      proof remain downstream gates before visual completion/legacy retirement.
- [x] Help bounded wave implementation gate (local proof): `HelpScreen` now
      uses the approved public/shell top bar, header, navigation and article
      geometry with Phosphor actions, semantic Light/Dark surfaces, fixed
      responsive card minima and shell-tablet side-by-side composition; loader,
      retry, empty, page selection, Markdown asset/link handling, back flow and
      AppLogger behavior remain unchanged. Exact node map was recorded in
      Linear before the edit for public Desktop/Mobile/Tablet, authenticated
      Desktop/Mobile/Tablet and loading/empty/error state authorities. Geometry
      proof passes public 1440×1024 + 1024×768 and shell 375×812 + 834×1112;
      affected Help/router/AppShell/admin/navigation/guard/theme suite passes
      86/86; `flutter analyze --no-pub`, format and `git diff --check` pass.
      `flutter build web --release --no-pub --no-wasm-dry-run` also passes on
      the exact worktree.
      The Figma sample's fixed support-link URL is not invented; runtime keeps
      its existing Markdown-driven external-link behavior. Exact-SHA build,
      staging deploy, authenticated Chrome comparison and primary-platform
      proof remain downstream gates.
- [x] Feedback bounded wave implementation gate (local proof): `FeedbackScreen`
      now follows the approved Desktop/Web wide lane (`385:8932` → `385:8974`)
      and Android mobile/tablet lanes (`385:8998`, `842:30519`, `842:30600`)
      with exact form, textarea, attachment surface and 48px action geometry.
      The node map and state authority (`1277:118776`, `1277:118902`,
      `1277:119026`, `1277:119150`, tablet/mobile equivalents) were recorded in
      Linear before code. Existing FEEDBACK permission/route, 120/5000 field
      limits, max-20 multipart attachments, picker/camera, AppLogger,
      Vietnamese validation, success clear-and-pop and recoverable error
      preservation remain unchanged. Geometry proof passes compact 375×812,
      tablet portrait 834×1112, expanded 1024×768 and wide 1440×900; the
      affected Feedback/AppShell/router/admin suite passes 30/30 and
      `flutter analyze --no-pub`, format and `git diff --check` pass locally.
      Exact-SHA build, staging deploy, authenticated Chrome comparison and
      primary-platform proof remain downstream gates.
- [x] Feedback shared-input guard remediation: `_FeedbackField` and
      `_FeedbackTextArea` now reuse `AppFormTextInput` with the shared
      selection/paste policy; `AppFormTextInput` supports hidden external labels
      and explicit text alignment without changing the approved field geometry.
      `design_system_migration_guard_test.dart` + `feedback_screen_test.dart`
      pass; analyzer, format and diff checks pass.
- [ ] Full Flutter regression residuals after the Settings wave (fresh exact
      checkpoint run): `flutter test --no-pub --reporter json` records `868`
      testDone events = `867` success + `1` error. The direct redesign/route
      suite on checkpoint `1224a8ad` passes `107/107`, and the Sales Reports
      suite passes `28/28`; Bank Statement, AppStatePanel and Not Purchased
      regressions are clean. The only residual is Windows Home speaker status
      (pending Figma proposal `1888:59111`). Full regression is still
      release-red until the approved Home node is implemented and the exact run
      is green.
- [ ] Migrate remaining route groups in bounded waves (shell/auth/system,
      operations, FIFO, sales/finance, warranty, admin and long-tail) with one
      production visual path per migrated surface; remove legacy visual
      fallback branches only after affected-consumer proof.
- [ ] Keep business logic, API/data contracts, permissions, platform behavior,
      security, Vietnamese-first copy and existing route aliases unchanged.

### Phase 5 — release and safe cleanup gates

- [ ] Run focused widget/golden geometry proof, `flutter analyze`, affected
      consumer tests, full Flutter regression, web release/Wasm build and
      `git diff --check` on the exact tested SHA.
- [ ] Deploy that exact SHA to staging, run authenticated Chrome comparison at
      the complete viewport matrix against the exact Figma nodes, and capture
      Windows/Android primary-platform plus iOS/iPadOS regression evidence.
- [ ] Record implementation/proof note in Linear before every forward status
      transition; leave OPS-44 In Progress until production deployment passes.
- [ ] After a phase is merged and its worktree is clean, run the guarded
      lifecycle cleanup; never delete the active dirty worktree or the unrelated
      OPS-27 branch.
- [ ] Delete `ARCHIVE — Web Responsive (empty · pending deletion)` only after
      explicit Figma revision approval; read back the final seven-page inventory.

#### Branch cleanup audit — 2026-08-04

- The active implementation branch/worktree is `codex/ops-44-execution-plan-v2`
  at clean head `9674a83bbb61238bbd709f0a9a88696a205583cf` (runtime checkpoint
  `1224a8ad228d04c63bac55e502fca2ba26971050`); it is not yet
  published/merged into `staging`.
- Local `staging` is clean at the same base SHA. The separate `OPS-27`
  worktree/branch is unrelated and is preserved.
- Remote stale cleanup completed on 2026-08-04: the 11 remaining
  `codex/ops-44-*` refs were verified against merged PRs (`#89`, `#90`,
  `#92`–`#98`, `#101`–`#103`), each remote tip matched its merged PR
  `headRefOid`, and no open PR or post-merge branch commit was present. The
  refs were deleted with `git push origin --delete ...`, then removed from
  local tracking refs with `git fetch origin --prune`; a fresh readback shows
  no remote `codex/ops-44-*` branches. Active OPS-44, `staging`, `main` and
  unrelated OPS-27 were not touched.
- After the next approved phase is committed, PR-merged into `staging`, and
  the task worktree is clean, run `scripts/task-lifecycle.mjs finish --execute`
  from canonical `staging` before starting another task.

- [x] Create OPS-44 Linear issue and record implementation start proof.
- [x] Create guarded OPS-44 task worktree from live `origin/staging`.
- [x] Reconcile the pre-migration eight-page Figma audit, post-migration seven
      canonical pages, 45 router declarations and route aliases in docs, ledger
      and visual-smoke guard.
- [x] Implement shared foundation/theme/component batch used by migrated
      surfaces; font cutover remains intentionally gated on asset/provenance and
      Android/Windows/web proof.
- [x] Migrate shell/auth/system and pilot routes in the approved frame scope;
      remaining platform proof is a release gate.
- [x] Migrate operational, admin and long-tail Loaded surfaces, including all
      13 admin frames plus Support Chat and API Connections. Shared loading,
      filtered-empty, retryable-error and permission evidence is composed from
      existing Foundation State Panels in Web frame `1793:16377`; this creates
      no new route-level state authority.
- [x] Run local staging web release build and full Flutter regression
      checkpoint; remote staging deploy, Chrome audit and platform proof remain
      pending protected release gates.
- [x] Harden the redesign workflow into a strict, evidenced Figma-first gate:
      exact node/revision → complete node map → geometry proof → exact-SHA
      build → staging deploy → authenticated Chrome comparison. Legacy UI is
      behavior-only and cannot supply a visual decision or fallback.
- [x] FIFO Check node map: mobile Loaded `373:6159` (375 content 343,
      command 343×200, result 343×340); web Loaded `1381:129739` (1440
      content 1190, command 1126×200, result 1126×340); web 1024 Loaded R1
      `1807:16494` (rail 88, content 936, command/result 872×200/340).
- [x] FIFO Check command/result geometry and serial-correct state use the
      approved Phosphor command actions plus serial nodes `1811:33734`,
      `1812:48120`, and `1812:130354`; loading/empty remain shared Foundation
      state panels.
- [x] FIFO Check serial-wrong node map captured before the next UI edit:
      Desktop + Web unified frame `1814:33866` (1440×900) → content
      `1814:33868` (1190×828), command bar `1814:33869` (1126×200), result
      `1814:33873` (1126×340). Result state maps `1814:33887` / label
      `1814:33888` (`Sai thứ tự FIFO`), item `1814:33875`, badge `1814:33878`,
      metadata `1814:33889`, copy actions `1814:33890`/`1814:33892` with labels
      `1814:33891`/`1814:33893`, and export control `1814:33894`–`1814:33896`
      to `_SerialWrongOrderResult` in `FifoCheckScreen`. Reuse existing shared
      command/result widgets and preserve provider/API/export/copy behavior.
- [x] FIFO Check missing runtime result states were designed in the unified
      Desktop + Web page from the approved R1 geometry and Foundation state
      panel instances: exported `1872:34872`, display-reserved `1872:122546`,
      serial not-found `1872:122717`, and retryable error `1872:122901`.
      Each node has metadata/screenshot readback and an exact
      `get_design_context` proof before code implementation.
- [x] Figma Desktop + Web consolidation: moved all 68 Web top-level nodes from
      `1174:4` into `693:17492` in atomic batches; 14 Web-only authority nodes
      remain visible, 54 duplicate nodes are hidden rollback evidence, the
      former Web page now has `childCount = 0`, and the consolidated page
      readback is `childCount = 189` including the Dark coverage board, new
      FIFO state authorities and pending Notifications parity proposal
      `1881:59087`, API dynamic proposal `1883:59093`, Settings speaker
      proposal `1884:59093`, Home speaker proposal `1888:59111`, and Sales
      managed-filter proposal `1891:59111`, and Support Chat runtime-state
      proposal `1898:107163`.
- [x] Current branch local proof: `flutter analyze --no-pub`, focused guard /
      theme suite `25/25`, Home bootstrap `1/1`, loaded Home KPI consumer `1/1`,
      `dart analyze`, format check, `git diff --check`, and
      `flutter build web --release --no-pub` (Wasm dry run) pass.
- [x] Post-Dark/status regression checkpoint: `flutter analyze --no-pub`
      passes; affected FIFO/migration/theme/AppShell suite passes `58/58`;
      `flutter build web --release --no-pub`, format and diff checks pass.
      Broad Flutter suite still has six failures; three Home/not-purchased
      failures reproduce on clean staging at the same SHA, while three Sales
      Report failures occur only in the broad mixed run and pass in direct
      affected-file execution. No failure is in the changed FIFO/theme suite.
- [x] FIFO serial-wrong result implementation uses the approved `1814:33866`
      geometry/state map, reuses the serial-correct shared layout, and keeps
      provider/API/export/copy behavior unchanged. Focused FIFO redesign proof
      passes `12/12`; targeted analyzer and format checks pass.
- [x] FIFO status surfaces now resolve Light/Dark semantic colors through shared
      `AppColors` helpers; the Dark coverage screenshot/readback shows the
      approved dark shell and auth contrast without changing route behavior.
- [x] FIFO Check exported/display-reserved/not-found runtime states now have
      approved node authority and code paths; retryable error remains a
      Foundation state-panel authority for the existing provider error path.
- [ ] Retire remaining legacy visual consumers after remote staging/Chrome and
      primary-platform proof confirms no active consumer needs the compatibility
      layer.
- [ ] Record final Linear implementation/proof note and move plan to completed.

## Decisions

- 2026-08-03: The live Figma file has eight official pages, including iOS,
  iPadOS and Web; older repository docs that list five pages are stale.
- 2026-08-03: `/reports` remains a redirect to `/sales-reports`, and
  `/fifo/inventory-import` remains an alias of the canonical inventory-import
  screen; neither receives a duplicate visual design.
- 2026-08-03: Legacy visual retirement is end-state work performed after
  incremental consumer migration, not a single destructive rewrite.
- 2026-08-03: The Figma desktop specimen defines the visual target for the
  brand/logo/topbar; it does not authorize removal of existing Support,
  Notifications or account actions. The supplemental Foundation documentation
  frame `1785:55496` is R2: Support and Notifications remain direct desktop
  topbar actions, the account menu keeps only account actions, and the
  permission/provider-gated metrics chip creates no route, permission or
  business-behavior change. Web specimen `1792:16338` now shows these three
  retained desktop actions directly beside the route-specific topbar action.
- 2026-08-03: Every UI mutation, including a responsive or single-control fix,
  must use the strict Figma-first evidence chain. A visual remediation stales
  every downstream proof; no legacy layout, token, typography, icon, copy,
  screenshot or responsive behavior may fill an absent Figma node.

## Validation

- Focused proof: affected shared/widget tests plus route and migration guards.
- UI gates: `dart format --output=none --set-exit-if-changed`,
  `git diff --check`, `flutter analyze --no-pub`,
  `flutter test --no-pub --reporter expanded`.
- Runtime proof: staging workflow/SHA, staging smoke checklist, Chrome
  authenticated audit and visual-smoke at relevant viewports; Android/Windows
  proof for primary platform behavior.
- Evidence must record Figma page/frame/revision, viewport/platform and build
  SHA; no generic test-pass claim substitutes for affected-consumer proof.

## Result

Not complete. Local regression/build checkpoint is verified, but remote staging
deploy, Chrome audit, remaining surfaces and platform proof are still pending.
Record verified waves, unverified surfaces, residual risks and follow-up
decisions before moving this plan to `docs/plans/completed/`.
