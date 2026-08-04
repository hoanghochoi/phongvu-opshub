# Execution Plan: OPS-44 Redesign Foundation Runtime And UI Retirement

Date: 2026-08-03
Last updated: 2026-08-04 (Đại Ca approved proposals; Support Chat Figma gap revision + composer proof)

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
      `73c3a77376a3ce3e71fc3a58b83d3c4b9e2bef9f` (runtime checkpoint
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
- [x] Dark remediation node map captured before runtime edits (Figma file
      `mFzSmQzlapSe3RSmUhvzll`, approved board `1874:35444`):
      AppShell/logo/navigation `1874:123525` → `AppShell`, `AppLogo`,
      `AppNav` using shell `227:8`, navigation content `8:158`, navigation
      muted `8:159`, text primary `8:79`; Operations section/action surfaces
      `1874:123525` → `AppFeatureSection`/`AppFeatureTile` using surface/card
      `8:154`, info/input `8:148`, primary/muted `8:79`/`8:81`, and the
      existing Phosphor route icons; Home dashboard `1874:123632` →
      `HomeSummaryPage` shared cards/section headings using canvas/surface/card
      semantics and dark text tokens; Bank Statement `1874:129947` →
      `BankStatementScreen` rows/action labels using `8:154` + `8:79`;
      Organization edit dialog `1874:125723` → shared dialog/form surfaces.
      Required Chrome matrix is compact `375×812`, medium `834×1112`,
      expanded `1024×768`, and wide `1440×900`; states are loaded, loading,
      empty, retryable error, permission/unsupported and dialog where exposed.
- [x] Dark runtime semantic remediation local gate: shared `AppColors`, dark
      `AppTheme`/`DialogTheme`, `AppLogo`, feature tiles, AppCombobox/ListTile,
      state/chip/card/button primitives, AppShell dialogs, Home KPI/speaker,
      Operations, Bank Statement, Help, Admin Users/Organization and auth
      feedback now resolve dark surfaces/text from context helpers; no business,
      route, permission or platform contract changed. Figma bindings for
      `229:844`, `677:17777` and Bank Statement action titles were read back to
      `8:158`, `8:159` and `8:79`.
- [x] Dark local proof: theme/geometry and affected Admin Users, Organization,
      Help, Operations, Bank Statement and shared widget tests pass; fresh
      `flutter analyze --no-pub`, `git diff --check`, and
      `flutter build web --release --no-pub --no-wasm-dry-run` pass. Full
      regression is rerun after the Home speaker chip/icon and dark surface
      remediation: `flutter test --no-pub --reporter json` is `875/875`
      successful with zero failures. Authenticated staging Chrome comparison
      remains downstream.

### Phase 2 — shared foundation cleanup

- [x] Remove unused `AppTheme` legacy color accessors and the unused
      `legacyDesktopBreakpoint` alias after repository consumer search found no
      runtime consumers.
- [x] Remove the unused light-only `AppStateTone.color` compatibility getter
      after repository consumer search; all state/chip consumers use the
      context-aware semantic mapping.
- [x] Converge remaining shared primitive aliases after affected-consumer proof:
      removed unused `AppColors.danger`/`gradientMid`, replaced the 1:1
      `card`, `teal600`, `violet600` and `darkNeutral50` aliases with canonical
      surface/secondary/accent/dark-input tokens, and kept the semantic
      `focus`/speaker tokens because they remain distinct component contracts.
      Button, navigation, admin-role, Settings and Warranty affected-consumer
      proof passes `37/37`; analyzer and diff checks pass with no color-value
      change.
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

#### Figma proposal approval checkpoint — 2026-08-04

Đại Ca đã xác nhận tất cả proposal/revision đang được ghi trong issue và
ledger là đã duyệt. Các node proposal có metadata, screenshot và
`get_design_context` readback trước đó được coi là authority visual; các wave
runtime tương ứng được phép implement theo đúng node map, không còn chặn bởi
approval. Việc hoàn tất vẫn cần geometry proof, exact-SHA build, staging/Chrome
audit và production deployment theo các gate bên dưới.

Figma authority metadata was synchronized after approval: proposal sections
`1881:59087`, `1883:59093`, `1884:59093`, `1888:59111`, `1891:59111`,
`1895:59111` and `1898:107163` no longer carry “Pending approval” labels; each
now has an approved-authority note. Home speaker adds state icons `1909:2` and
`1909:4`, read back with `get_metadata`, `get_screenshot` and
`get_design_context`. API lifecycle proposal `1917:59111` was also synchronized
to `Proposal note · Approved authority`; its exact populated-card nodes were
read back with metadata, screenshot and `get_design_context` before runtime
editing.

#### Approved modal/state node map readback — 2026-08-04

The approved Admin Users and Admin Features modal/state nodes were re-read
through `get_metadata` followed by `get_design_context` before runtime work:

- Import result: `1874:131679` (520×584) → shared Dialog shell with result
  body `810:2940` and actions `810:2941`.
- Organization picker: `1874:131712` (560×632) → shared Dialog shell with
  search/filter/list body `810:2956`–`810:2976` and shared actions.
- Admin Features “Theo đơn vị”: `1874:131499`; “Quy tắc cũ”:
  `1874:131524` → existing feature-assignment state paths.
- Admin Users save confirmation: frame `1874:131713`, backdrop
  `1874:131744`, exact dialog `1874:131745` (480×312), body
  `810:2995`–`810:3004`, actions `810:3011` and `810:3013`.

Readback confirms shared dialog geometry (24px inset, 12px shell gap, 40px
small actions) and Vietnamese title/body/action copy. Dark runtime must resolve
the same surfaces/text through `AppColors`/`DialogTheme`; it must not rebuild
raw white dialogs or rely on inconsistent title defaults.

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
- [x] Notifications runtime parity gap is represented by the approved proposal
      section `1881:59087` on Desktop + Web, built from the
      approved notification instances and covering transaction/request times,
      requester, reason and content lines. Metadata readback and screenshot
      pass; the proposal is now a production visual authority.
- [x] Notifications exact node map was read back with `get_metadata` and
      `get_design_context` before implementation: pending dynamic card
      `1881:59112` (880×300) → top `1881:59113`, icon tile/icon
      `1881:59114`/`1881:59115`, unread/title/meta `1881:59117`–`1881:59120`,
      status/time `1881:59121`–`1881:59123`, detail `1881:59124`, runtime
      metadata `1881:59129`–`1881:59132`, actions `1881:59125` with reject
      `1881:59126` (96×48) and confirm `1881:59128`; rejected card
      `1881:59152` (880×240) with metadata `1881:59169`–`1881:59172`; offset
      rejected card `1881:59192` (880×176) with metadata
      `1881:59209`–`1881:59210`. Vietnamese copy, status badges, icon tile,
      action geometry and responsive adaptation are governed by these exact
      nodes; notification provider/read/approve/reject/navigation behavior is
      protected.
- [x] Notifications runtime implementation gate (local proof): full-page
      Desktop/Web uses the approved 880px card lane and 16px surface padding;
      pending cards map the 40px ArrowsLeftRight tile, unread/title/meta,
      status/time block, detail, four runtime metadata lines and 96/115×48
      actions; rejected and offset-rejected cards preserve reason/action
      guidance with the same semantic status surfaces. Compact Web remains
      overflow-safe. Shared `AppSurfaceCard`, `AppRadius`, Phosphor icon and
      context-aware Light/Dark colors are reused; provider load/read,
      approve/reject confirmation, offset navigation and AppLogger behavior
      remain unchanged. Geometry/state tests pass pending 880×300 and
      rejected 375×812; Notifications provider suite passes 16/16, shell route
      notifications proofs pass, `flutter analyze --no-pub` and format pass.
      Staging/Chrome/platform proof remains downstream before legacy retirement.
- [x] Home speaker-status runtime gap is isolated in approved Figma proposal
      `1888:59111` (`PROPOSAL — Home speaker status`). The
      approved Home chain `326:2698` → `326:2731` → `326:2732` has no speaker
      node in the base header, so the approved proposal supplies the missing
      state chip and icon nodes. The protected Windows runtime contract still
      requires `Loa đang bật/tắt` plus the existing toggle/provider/AppLogger
      behavior. Proposal metadata, screenshot and `get_design_context`
      readback pass; Home visual implementation is now unblocked.
- [x] Support Chat runtime-state gap is isolated in approved Figma proposal
      `1898:107163` (`PROPOSAL — Support Chat runtime states`).
      The proposal covers inbox/thread loading, empty, retryable error,
      permission, selected-thread and responsive desktop, tablet portrait,
      tablet landscape and mobile states. Metadata, screenshot and
      `get_design_context` readback pass; production visual implementation is
      now unblocked.
- [x] Support Chat exact loaded node map was read back with `get_metadata` and
      `get_design_context` before implementation: Desktop/Windows workspace
      `1711:134979` → inbox `1711:134980` (380×780), conversation
      `1711:134981` (746×780), filters `1712:34729`, selected/pending cards
      `1713:34726`/`1713:34731`, assignment actions `1713:134930`/
      `1713:134932`, composer `1714:34735`; Desktop/Web workspace
      `1724:17253` → inbox `1724:17254`, conversation `1724:17255`, filters
      `1725:17193`, selected/pending cards `1725:17204`/`1725:17209`;
      Android Tablet detail `1720:134943` (714×992) and Android Mobile detail
      `1720:23234` (343×640), including exact compact headers, timelines,
      bubbles and composers. State/permission/loading/error behavior remains
      governed by proposal `1898:107163`; auth/session, selection, realtime,
      assignment/resolve, composer/media and AppLogger behavior are protected.
- [x] Support Chat Figma gap revision was required by the runtime attachment
      control: the approved base composer `1714:34735` contains only input and
      send, while runtime preserves image picking. A separate revision section
      `1923:59111` adds composer `1923:59112` (714×56), attachment action
      `1923:59119` (40×40), Camera icon `1923:59120` (20×20), input
      `1923:59113` (546×40) and send `1923:59116` (96×40), all using existing
      semantic variables. Metadata, screenshot and `get_design_context`
      readback pass; runtime implementation uses the same shared 40px action
      contract without changing media/composer behavior.

#### Figma gap/action ledger — 2026-08-04

All rows below have a named approved proposal node, metadata readback,
screenshot readback and `get_design_context` evidence. Runtime may implement
the protected behavior from these exact nodes; it must not invent a different
visual element/state.

| Runtime gap | Figma proposal | Protected runtime behavior | Next gate |
| --- | --- | --- | --- |
| Notifications content parity | `1881:59087` | unread/read, requester/reason/content, action feedback | Local Desktop/Web + compact implementation proof passed; staging/Chrome/platform audit pending |
| API Connections dynamic clients/keys | `1883:59093` | repository mutations, confirmation, secret/key handling, logger | Local implementation/proof passed; staging/Chrome/platform audit pending |
| API Connections supported Web compact/medium | `1895:59111` | Web capability remains supported; Android unsupported guard unchanged | Local responsive implementation/proof passed; staging/Chrome/platform audit pending |
| Settings speaker voice card | `1884:59093` | speaker preference provider, combobox selection, startup/theme behavior | Local Desktop/mobile/tablet implementation/proof passed; staging/Chrome/platform audit pending |
| Home speaker ON/OFF status | `1888:59111` | existing toggle/provider/AppLogger contract; Windows-only visibility | Local icon/state implementation/proof passed; staging/Chrome/platform audit pending |
| Sales Reports managed filter | `1891:59111` | existing `Lọc` trigger, advanced sheet, provider scope/filter behavior | Local compact/medium implementation/proof passed; staging/Chrome/platform audit pending |
| Support Chat inbox/thread states | `1898:107163` + `1923:59111` | auth/session, thread selection, retry/permission, composer/media/realtime behavior | Local responsive implementation/proof passed; staging/Chrome/platform audit pending |

The destructive archive-page action is tracked separately: page `1174:4`
(`ARCHIVE — Web Responsive (empty · pending deletion)`) can be deleted only
after explicit unified-revision approval and a final seven-page inventory
readback.
- [x] Home speaker-status implementation gate: approved proposal
      `1888:59111` was read back at exact ON/OFF nodes `1888:59118` and
      `1888:59120` (152×40, radius 20) with state-specific icons
      `1909:2` (Volume Up) and `1909:4` (Volume Off). `HomeSummaryHeader` now
      places the Windows-only chip beside the desktop scope/date trigger,
      preserves `home-speaker-status-toggle`, provider mutation and AppLogger
      behavior, and maps ON/OFF surfaces through light/dark semantic tokens.
      Compact
      mobile remains without this visual because the approved matrix starts at
      medium `600–899`; Android/iOS/Web capability gates remain unchanged.
      Focused Home speaker geometry/regression proof passes; broader
      Home/AppShell proof remains the next gate.
- [x] Super Admin delivery-metrics consumer proof now sets the test viewport to
      the approved wide Desktop/Web contract (`1440×900`); the compact shell
      intentionally omits the metrics pill. Focused run confirms this test
      passes; the Windows speaker test now has the approved ON/OFF icons and
      focused Home regression proof passes.
- [x] Support Chat implementation gate (local proof): the approved Windows/Web,
      tablet and mobile state map is implemented as one responsive visual path;
      the runtime attachment control follows Figma revision `1923:59111` with
      shared `AppIconAction(dimension: 40)`, so compact composer geometry is
      `343×56` and the send action remains `88×40`. Auth/session, thread
      selection, loading/empty/retry/permission, assignment/resolve, realtime,
      image picking, composer keyboard behavior and AppLogger behavior remain
      unchanged. `support_chat_surface_test.dart` passes `6/6`,
      `design_system_migration_guard_test.dart` passes `21/21`,
      `flutter analyze --no-pub` reports no issues and `git diff --check`
      passes; exact-SHA build, staging/Chrome and platform proof remain
      downstream.
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
- [x] API Connections populated lifecycle node map captured before code edit:
      OAuth populated card `1917:59114` → header `1918:59111`, identity
      `1918:59112`, lifecycle actions `1918:59115`, runtime detail panel
      `1918:146625`; OpenPGP populated card `1917:59115` → header
      `1918:146628`, lifecycle actions `1918:146632`, runtime detail panel
      `1918:146641`. Action widths, 40 px height, 12 px radius, detail panel
      padding and Vietnamese copy are read back from the approved proposal.
      Supported Web compact/medium lanes remain governed by approved
      responsive proposal `1895:59111` (343 px / 714 px content lanes); code
      must stack action rows without changing repository behavior.
- [x] API Connections implementation gate (local proof): supported loaded
      clients/keys now use the approved lifecycle card composition, while the
      empty path uses the approved BIDV/OpenPGP base cards; operations controls
      use the exact 48px row/switch anatomy. Shared action buttons gained an
      optional Figma labelSmallSubtle text style; no raw feature-local buttons
      remain. Geometry proof passes wide 1440×900 (1142px lane; populated
      client 260px, key 292px, controls 210px), empty base card geometry and
      Web compact 375×812 / medium 834×1112 lanes without overflow. API screen
      proof passes 8/8; design-system guard plus API proof passes 28/28;
      `flutter analyze --no-pub`, format and `git diff --check` pass. Staging,
      authenticated Chrome and platform proof remain downstream and are
      required before retiring the old visual consumers.
- [x] API Connections dynamic-state gap is isolated in approved proposal
      `1883:59093` (`PROPOSAL — API Connections dynamic states`). It reuses
      the approved BIDV/OpenPGP cards and covers a
      non-empty OAuth client plus active OpenPGP key. Metadata and screenshot
      readback pass; supported client/key visual code is now unblocked.
- [x] API Connections Web responsive authority gap is isolated in approved
      proposal `1895:59111` (`PROPOSAL — API Connections supported Web
      responsive`). The proposal covers Web compact
      `375×812` (343px lane) and Web medium `834×1112` (714px lane), reuses
      the approved Desktop/Web BIDV/controls/OpenPGP anatomy, and explicitly
      distinguishes Web-supported behavior from Android unsupported nodes
      `1704:134781` / `1704:134853`. Metadata and screenshot readback pass;
      responsive Web visual edit is now unblocked.
- [x] API Connections Android unsupported state now uses the approved shared
      card/state path with exact Vietnamese copy and 236 px card geometry;
      focused API/admin/router/shell/guard proof passes `65/65`, and
      `flutter analyze --no-pub` plus format/diff checks pass. The supported
      Windows/Web dynamic path is now unblocked by the approved proposal above.
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
- [x] Sales Reports compact/medium managed-scope advanced filter implementation
      gate: runtime behavior keeps the existing `Lọc` trigger and
      `_AdvancedFilterSheet`; the approved compact/portrait loaded nodes did
      not contain that visible element, so the approved Figma proposal
      `1891:59111` (`PROPOSAL — Sales Reports managed filter`)
      records the compact `375×812` and medium `834×1112` state matrix,
      closed/active trigger states, preserved sheet/provider behavior, and the
      exact loaded node chain. Metadata and screenshot readback passed. The
      exact trigger nodes are `1891:59118` (closed, 152×40, success surface)
      and `1891:59120` (active, 152×40, neutral surface); `get_design_context`
      confirms Vietnamese copy `Lọc` / `Đang lọc • N`, 14/20 semibold text,
      20px radius and no icon. The 152×40 closed/active
      trigger now follows the approved `Lọc` / `Đang lọc • N` states with no
      icon; sheet/provider behavior remains unchanged. Geometry/state proof
      covers medium `834×1112`; the managed-filter test plus the full affected
      Sales Reports suite passes `29/29`, and analyzer, format and
      `git diff --check` pass. Staging/Chrome/platform proof remains downstream
      before visual retirement.
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
- [x] Settings speaker-voice authority gap is isolated in approved Figma
      proposal `1884:59093` (`PROPOSAL — Settings speaker voice card`). It
      reuses the approved Settings card geometry and canonical
      Combobox instance, covering runtime label/value/helper copy for Desktop
      (`1884:59096`, 555×230), Mobile (`1885:59099`, 343×188) and Tablet
      (`1885:59109`, 343×188). Metadata, screenshot and `get_design_context`
      readback pass; Settings implementation for this surface is unblocked.
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
- [x] Full Flutter regression residuals after the Settings wave (fresh exact
      checkpoint run): `flutter test --no-pub --reporter json` records `868`
      testDone events = `867` success + `1` error. The direct redesign/route
      suite on checkpoint `1224a8ad` passes `107/107`, and the Sales Reports
      suite passes `28/28`; Bank Statement, AppStatePanel and Not Purchased
      regressions are clean. The only residual recorded at that checkpoint was
      Windows Home speaker status against proposal `1888:59111`; the approved
      chip/icon implementation and focused test now pass, so the full exact
      regression rerun on the current worktree is now green: `875/875`
      successful, zero failures. Keep the historical checkpoint text above for
      traceability; the release gate still requires staging/Chrome proof.
- [x] Exact HEAD rerun on 2026-08-04 (`88112a73`) confirms the same bounded
      residual: `flutter test --no-pub --reporter json` emits `868` testDone
      events with `867` `success` and `1` `error`; the error is the Windows Home
      speaker assertion for the Windows capability fixture (`Loa đang bật`).
      No new Dark regression appeared after the approval checkpoint.
- [x] Migrate remaining route groups in bounded waves (shell/auth/system,
      operations, FIFO, sales/finance, warranty, admin and long-tail) with one
      Figma-backed visual path per migrated surface; the local affected suites,
      migration guard and full regression cover the migrated consumers. Legacy
      visual fallback retirement remains a downstream staging/Chrome gate.
- [x] Keep business logic, API/data contracts, permissions, platform behavior,
      security, Vietnamese-first copy and existing route aliases unchanged;
      full regression and route/migration guards pass after the final local
      wave.

### Phase 5 — release and safe cleanup gates

- [x] Run focused widget/golden geometry proof, `flutter analyze`, affected
      consumer tests, full Flutter regression, web release/Wasm build and
      `git diff --check` on exact SHA `3f1b46b384b1ba266623fcc1f5b5856da86f948f`:
      Support Chat `6/6`, migration guard `21/21`, full Flutter `875/875`,
      analyzer clean, web release build pass and clean worktree.
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
  has a clean runtime source commit `3f1b46b384b1ba266623fcc1f5b5856da86f948f`
  followed only by the exact-SHA proof note commit (the current worktree is
  clean); the runtime source includes the committed Support Chat Figma gap
  revision and token convergence, and it is not yet
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
      readback is `childCount = 191` including the Dark coverage board, new
      FIFO state authorities and approved Notifications parity proposal
      `1881:59087`, API dynamic proposal `1883:59093`, Settings speaker
      proposal `1884:59093`, Home speaker proposal `1888:59111`, and Sales
      managed-filter proposal `1891:59111`, Support Chat runtime-state
      proposal `1898:107163`, and composer attachment revision `1923:59111`.
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
