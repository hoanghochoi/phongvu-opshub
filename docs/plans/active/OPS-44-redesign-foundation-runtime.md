# Execution Plan: OPS-44 Redesign Foundation Runtime And UI Retirement

Date: 2026-08-03
Last updated: 2026-08-05 (Execution plan v2 continuation contract + Order Command correction)

## Status

Active

## Outcome

Đưa visual/interaction foundation hiện hành của Figma OpsHub vào shared Flutter
layers và migrate toàn bộ declared route surfaces theo các wave có thể rollback.
UI legacy chỉ được retire sau khi không còn consumer và có affected-consumer
proof; business, API, permission, platform và data behavior giữ nguyên.

## Context

- Linear: OPS-44, related OPS-25 and OPS-34.
- Git baseline: PR #104 merged the native speaker phase at
      `3ee28f91e1ff6a46b61cda27693a0d230a63aab1`; docs/proof PRs #105–#108
      are merged. The current `staging` and `origin/staging` SHA is
      `424eaacce1a3b4d5b27eddf05af1e7c2cbe6bf7d`; the current continuation
      checkpoint is the intentionally dirty local branch
      `codex/ops-44-home-wide-header-parity` in the guarded worktree. All prior
      merged OPS-44 phase branches have been cleaned; this checkpoint must be
      committed/verified before its own lifecycle cleanup.
- Figma file:
  `mFzSmQzlapSe3RSmUhvzll`; target pages Cover `0:1`, Foundation `13:5`,
  Desktop + Web `693:17492`, Android mobile `693:17493`, Android tablet `698:2`,
  iOS mobile `1174:2`, and iPadOS tablet `1174:3`. Former Web page `1174:4`
  was explicitly deleted after the unified revision approval and final
  seven-page inventory readback.
- Figma audit before migration: 8 pages, 393 variables, 21 text styles, 4
  effect styles, 906 reusable foundation sources, no missing fonts; 43
  canonical visual route surfaces plus `/reports` redirect and
  `/fifo/inventory-import` alias. Post-migration target is 7 canonical pages.
- Runtime authority: `AGENTS.md`, `docs/WORKFLOW.md`, product UI contract,
  redesign workflow, `AppRouter` and existing tests.

## Continuation audit — 2026-08-04

- Repository checkpoint: canonical `staging` is clean and equals
  `origin/staging` at `13d2b2d00ce1b503fbdc2ea2b606c42d66bf2089`. The only
  preserved unrelated worktree is `OPS-27`; the next OPS-44 continuation uses
  a guarded task worktree from this SHA.
- Live Figma root readback is exactly seven pages: Cover `0:1`, Foundation
  `13:5`, Desktop + Web `693:17492`, Android mobile `693:17493`, Android
  tablet `698:2`, iOS mobile `1174:2`, iPadOS tablet `1174:3`. The deleted
  page `1174:4` is absent from the root inventory.
- Figma route-owner audit found no new runtime-visible gap: Desktop/Web has
  44 visible owners including `/shell-topbar`; Android mobile, iOS and iPadOS
  each have all 43 canonical owners; Android tablet has all 43 owners across
  nested Portrait/Landscape rail frames. `/reports` and
  `/fifo/inventory-import` remain behavior aliases without duplicate owners.
- No Figma write is authorized by this audit because every inspected runtime
  surface already has an approved node/proposal. If Chrome or platform proof
  exposes a new visible element/state, add it to the Figma gap ledger first,
  run metadata/screenshot/design-context readback, obtain approval, then edit
  runtime.

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
      pending deletion)` before the explicitly approved destructive delete;
      final page inventory readback passes.
- [x] Approve the unified Figma revision and delete the empty Web page `1174:4`
      after explicit destructive-action approval; final inventory readback
      confirms seven remaining top-level pages.
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

The earlier Windows-only Home speaker authority did not cover the requested
Android/iOS behavior. The product clarification explicitly keeps Web list-only
with no speaker control. A new Figma revision `1928:59113` (`PROPOSAL — Home
speaker Android/iOS coverage`) now records the exact Android/iOS/iPadOS
viewport/node map and reuses the approved 152×40 ON/OFF pills with 16px Volume
Up/Off icons (`1928:59120`, `1928:59124`, `1928:59122`, `1928:59126`). Metadata,
screenshot and `get_design_context` readback passed. Đại Ca approved this
revision on 2026-08-04; its Figma note now says `Approved authority`. Compact
Android/iOS place the chip in the Home header's second control row after the
112×40 update chip; iPadOS keeps it as the trailing header action. Web remains
explicitly excluded.

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
- [x] Runtime/Figma gap audit found one uncovered visible element—the Support
      Chat attachment action—so code work paused while revision `1923:59111`
      was created through the atomic `figma-use` workflow. Metadata, screenshot
      and `get_design_context` readback were recorded in this plan and Linear;
      the subsequent Home speaker platform gap is separately recorded below.
      Staging/Chrome still remains the authority for discovering deployment-only
      drift.
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
- [x] Home speaker platform expansion gap is isolated in Figma revision
      `1928:59113` (`PROPOSAL — Home speaker Android/iOS coverage`). The exact
      map covers Android `331:3160` + `1443:21701`, iOS `1274:4386`, iPadOS
      `1274:87069`, and the existing Windows chain; Web is explicitly excluded
      by product contract. The revision reuses the 152×40 ON/OFF pills and 16px
      Volume Up/Off icons; metadata, screenshot and `get_design_context`
      readback pass.
- [x] Approval gate for revision `1928:59113` is satisfied: Đại Ca approved the
      Android/iOS/iPadOS scope on 2026-08-04; Figma metadata, screenshot and
      `get_design_context` were re-read after the note changed to approved
      authority. Web remains list-only.
- [x] Implement native speaker expansion from the approved map: support Android,
      iOS and iPadOS in capability/bootstrap, use authenticated server audio on
      mobile/tablet while retaining the Windows local-preset path, place the
      approved 152×40 chip in the compact Home second control row beside the
      approved 112×40 update chip, and update affected tests/product copy
      without changing provider/API/realtime/ack behavior. Local proof passes
      Android and iOS/iPadOS realtime server-audio provider cases, Home compact
      geometry/state, capability/bootstrap/unsupported/speaker IO suites,
      analyzer, full Flutter regression (`877` testDone events, exit `0`), web
      release/Wasm build, and Android staging debug APK build.
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
| Home speaker ON/OFF status | `1888:59111` + `1928:59113` | existing toggle/provider/AppLogger contract; Windows local preset and Android/iOS/iPadOS authenticated server audio; Web remains list-only | Figma approval/readback passed; local Android/iOS provider, Home geometry, web build and Android staging debug proof passed; staging/Chrome and physical-platform audit pending |
| Sales Reports managed filter | `1891:59111` | existing `Lọc` trigger, advanced sheet, provider scope/filter behavior | Local compact/medium implementation/proof passed; staging/Chrome/platform audit pending |
| Support Chat inbox/thread states | `1898:107163` + `1923:59111` | auth/session, thread selection, retry/permission, composer/media/realtime behavior | Local responsive implementation/proof passed; staging/Chrome/platform audit pending |

- [x] Destructive archive-page action: page `1174:4`
      (`ARCHIVE — Web Responsive (empty · pending deletion)`) was deleted after
      explicit unified-revision approval. `get_metadata` now rejects `1174:4`,
      and the live Figma root inventory contains seven pages.
- [x] Home speaker-status implementation gate: approved proposal
      `1888:59111` was read back at exact ON/OFF nodes `1888:59118` and
      `1888:59120` (152×40, radius 20) with state-specific icons
      `1909:2` (Volume Up) and `1909:4` (Volume Off). `HomeSummaryHeader` now
      places the approved chip beside the desktop scope/date trigger,
      preserves `home-speaker-status-toggle`, provider mutation and AppLogger
      behavior, and maps ON/OFF surfaces through light/dark semantic tokens.
      Android/iOS/iPadOS placement is recorded in the approved revision
      `1928:59113`; Web remains list-only by explicit product clarification.
      Focused Home speaker geometry/regression proof passes for Windows and
      compact Android; broader staging/Chrome and physical-platform proof
      remains the next gate.
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
      consumer tests, full Flutter regression, web release/Wasm build,
      Android staging debug build and `git diff --check` on native speaker
      phase SHA `f2af57b8bca65ea5101df6ca3dcddcbe1a7ed5bc`: provider `48/48`,
      Home `5/5`, capability/bootstrap/unsupported/speaker IO suites pass,
      full Flutter `877` testDone events with exit `0`, analyzer clean, web
      release build and `app-staging-debug.apk` pass.
- [x] Deploy the current exact SHA to staging; deploy workflow `30914208733`
      and health checks pass. Published version is `2026.08.04.325`, build
      `200325`.
- [x] Run authenticated Chrome geometry/route smoke at the exact matrix:
      Home loaded Light and Dark screenshots were captured at `375×812`,
      `834×1112`, `1024×768` and `1440×900`; the static authenticated route
      set passes `39/39` at each viewport (`156/156` total), with `/reports`
      resolving to `/sales-reports`, no real horizontal overflow and no
      console error/warn. Home authority maps to Figma `331:3160` (compact),
      `713:18943` (medium), `713:19435` (expanded) and `326:2698` (wide).
- [ ] Run authenticated Chrome comparison at the complete exact viewport
      matrix for every affected loaded/loading/empty/error/dialog state against
      the approved Figma screenshots, and capture Windows/Android
      primary-platform plus iOS/iPadOS regression evidence. The loaded Home
      and route geometry smoke above passes, but state-by-state visual
      screenshot comparison and physical platform evidence remain open.
- [ ] Record implementation/proof note in Linear before every forward status
      transition; leave OPS-44 In Progress until production deployment passes.
- [x] After PR #104 merged, run the guarded lifecycle cleanup; staging is
      synchronized and the OPS-44 implementation branch/ref is gone. The
      unrelated OPS-27 worktree/branch was preserved.
- [x] Delete `ARCHIVE — Web Responsive (empty · pending deletion)` after
      explicit Figma revision approval; read back the final seven-page inventory
      and confirm node `1174:4` no longer exists.

#### Branch cleanup audit — 2026-08-04

- PR #104 (`codex/ops-44-execution-plan-v2` → `staging`) is merged; Release
  Guard run `30903440654` passed and deploy run `30903488800` passed for
  `3ee28f91e1ff6a46b61cda27693a0d230a63aab1`.
- Lifecycle `finish` dry-run passed after reviewing only generated ignored
  artifacts (`.dart_tool`, Flutter/Gradle outputs and platform ephemerals).
  `finish --execute` fast-forwarded local staging and removed the registered
  worktree metadata; Windows then rejected removal of the already-empty
  directory. The local branch and remote ref were subsequently deleted only
  after the merge/SHA checks, and `git fetch origin --prune` confirms no
  `codex/ops-44-execution-plan-v2` ref remains.
- Verified post-cleanup: `staging == origin/staging ==
  f7d90a7a0a56ed7be485d1c7e951690f426ab775`; only the unrelated OPS-27
  worktree/branch remains. A zero-file directory at
  `..\opshub-ops-44-phase0` is an OS cleanup residue and has no Git/worktree
  registration or branch association.

#### Staging deployment and Chrome audit — 2026-08-04

- Staging health and deploy workflow are green for the current exact SHA:
  workflow `30912522423`, published version `2026.08.04.324` / build
  `200324`; Android SHA-256 is
  `dd0c94746a87e4c228a566a2dce3ab6aa1bf6ed0acf2851dd9bc1c2af8c139af`, and
  Windows installer SHA-256 is
  `c04d11cdedfd905b9ca1269fb83a712a4ba9482d45abd192af9d713365f08ff1`.
- Authenticated Chrome opened the staging Home route at
  `https://opshub-staging.hoanghochoi.com/#/home`. The wide runtime view
  loaded without console errors; the header/shell, Home cards, dark navigation
  rail and Vietnamese copy are visible, and Web correctly has no speaker
  control (Web remains list-only per product contract). This is a smoke
  observation only: the extension viewport override did not change Chrome's
  actual `1534×937` viewport, so it is not accepted as the required
  `1440×900` evidence.
- Required Chrome matrix remains open and must be re-run at exact
  `375×812`, `834×1112`, `1024×768`, and `1440×900`, with runtime screenshot,
  approved Figma node/revision, deployed SHA and a per-viewport verdict.
  No new Figma gap was discovered in the observed Web Home state; if any
  missing element/state appears at the exact matrix, stop and create a new
  approved revision before changing runtime.

#### Current staging release proof — 2026-08-04

- Exact source/deploy: workflow `30914208733` completed successfully for
  `f7d90a7a0a56ed7be485d1c7e951690f426ab775`; `/health` is `200 ok`,
  `/api/health` is `200` with backend `ok`, and
  `/downloads/latest.json` publishes version `2026.08.04.325` / build
  `200325` with the same commit.
- Figma live readback: `use_figma` enumerates exactly seven pages — Cover,
  Foundation, Desktop + Web, Android mobile/tablet, iOS mobile/tablet — and
  `get_metadata(1174:4)` rejects the deleted page. The approved Home speaker
  revision `1928:59113` contains the ON/OFF 152×40 states and Volume Up/Off
  16×16 icon nodes `1928:59120`/`1928:59124` and `1928:59122`/`1928:59126`.
- Home loaded comparison node map is explicit per width: compact `331:3160`,
  medium Tablet Android `713:18943`, expanded Tablet Android landscape
  `713:19435`, and wide Desktop/Web `326:2698`. Dark coverage remains governed
  by board `1874:35444`; no new runtime-visible Figma gap was found in these
  loaded states, and Web speaker omission is intentional.
- Authenticated Chrome exact matrix proof is now available for loaded Home and
  static route geometry: each of `375×812`, `834×1112`, `1024×768` and
  `1440×900` reports viewport/Flutter width equality, no real overflow and no
  console error/warn; Home Light/Dark screenshots were captured and Web has no
  speaker control by explicit product contract. This does not close the
  per-state Figma screenshot comparison gate for every route.
- Remaining release blockers are physical Windows/Android audio plus
  iOS/iPadOS evidence, state-by-state visual comparison, legacy retirement
  sign-off and production deployment. If any state exposes a missing visible
  element, stop and create/revise Figma before editing runtime.

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
      former Web page was then deleted after its `childCount = 0` readback, and
      the consolidated page
      readback is `childCount = 192` including the Dark coverage board, new
      FIFO state authorities and approved Notifications parity proposal
      `1881:59087`, API dynamic proposal `1883:59093`, Settings speaker
      proposal `1884:59093`, Home speaker proposal `1888:59111`, and Sales
      managed-filter proposal `1891:59111`, Support Chat runtime-state
      proposal `1898:107163`, lifecycle proposal `1917:59111`, and composer
      attachment revision `1923:59111`.
- [x] Current branch local proof: `flutter analyze --no-pub`, focused guard /
      theme suite `25/25`, Home bootstrap `1/1`, loaded Home KPI consumer `1/1`,
      `dart analyze`, format check, `git diff --check`, and
      `flutter build web --release --no-pub` (Wasm dry run) pass.
- [x] Fresh local regression refresh on the current branch (2026-08-04):
      `flutter test --no-pub --reporter json` completed with `875/875`
      successful testDone events, `0` failures and `3` intentional skips. The
      compact reporter pipe timeout was avoided by capturing JSON to a temp file;
      the command itself exited `0`.
- [x] Native speaker phase verification on SHA
      `f2af57b8bca65ea5101df6ca3dcddcbe1a7ed5bc`: focused provider suite
      `48/48` includes Android and iOS/iPadOS authenticated server-audio
      realtime cases; Home compact geometry/state `5/5`; capabilities,
      media_kit bootstrap, unsupported copy and speaker IO suites pass;
      full Flutter regression emits `877` testDone events and exits `0`;
      `flutter analyze --no-pub`, `git diff --check`, web release/Wasm and
      `flutter build apk --debug --flavor staging --no-pub` pass. Physical
      Android/iOS/iPadOS audio output and authenticated staging Chrome remain
      downstream release gates.
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

#### Continuation Chrome handoff — 2026-08-04

- Authenticated Chrome was connected to the protected staging tab and left on
  `/#/home` for the next QA pass. Direct dark-mode observations covered
  Settings, the application-info dialog, Organization edit dialog, FIFO Check,
  Feedback, Notifications and API Connections; no raw white dialog or dark
  title drift was observed inside those app surfaces.
- The extension screenshot output showed a `1024×588` bitmap while the page's
  Flutter view and document measured `1024×768` with no horizontal overflow.
  The apparent white right/bottom margin is therefore treated as a browser
  capture/device-scale mismatch, not as accepted runtime visual evidence. The
  exact matrix must be re-captured after the viewport control is corrected.
- One non-fatal startup warning was observed (`prepareServiceWorker` exceeded
  4000 ms); no application console error was observed. This remains a release
  residual until a clean exact-matrix run proves it absent or classifies it as
  infrastructure-only.

#### Corrected Chrome viewport capture — 2026-08-04

- Reconnected to the authenticated staging tab and applied the temporary
  explicit `1024 × 768` viewport override. The screenshot now fills the full
  canvas; the earlier roughly two-thirds app image with white right/bottom
  margins was caused by the default extension capture scale, not a runtime
  layout defect. The override is temporary and is reset after capture.
- The expanded route smoke was rerun against staging at that exact viewport:
  all 39 authenticated routes resolved (`39/39`), `/reports` resolved to
  `/sales-reports`, Flutter view and document width/height matched
  `1024 × 768`, and the visible-overflow audit was empty. `body.scrollWidth`
  still reports `1112` on several data-heavy routes, but the authoritative
  `documentElement.scrollWidth` remains `1024`; the only negative-coordinate
  nodes are hidden Flutter announcement semantics and are excluded by the
  reviewed smoke rule.
- Fresh route pass recorded zero Chrome console errors and zero warnings. A
  corrected authenticated Home screenshot was captured at `1024 × 768`.
  Existing Figma Desktop/Web and Dark owners remain authoritative; this
  capture correction exposed no new visible element or state, so no Figma
  revision is required.

#### Exact-SHA staging deploy and bootstrap residual — 2026-08-04

- Staging deploy workflow `30923869386` completed successfully for merge SHA
  `c213f62c3886daf8fa9b504816eababd0a6e2bd6`. Android APK and Windows
  installer/zip/checksum artifacts built, signed, scanned and uploaded; the
  staging web/backend verification steps also passed.
- Public readback is exact: `/health` returns `ok`, `/api/health` returns
  `status=ok` for `backend-nest`, and `/downloads/latest.json` publishes
  version `2026.08.04.328`, build `200328`, commit `c213f62c`.
- The post-deploy authenticated Chrome route smoke at explicit `1024 × 768`
  remains `39/39`: all hashes resolve, `/reports` redirects to
  `/sales-reports`, Flutter view is `1024 × 768`, root width is `1024`, and
  the visible-overflow audit is empty. No application console error appeared.
- A fresh page reload still emits the non-fatal Flutter bootstrap warning
  `prepareServiceWorker took more than 4000ms`; after roughly 15 seconds the
  Flutter view renders again, but the extension screenshot can temporarily
  show a blank or two-thirds-scaled canvas with white margins even while DOM
  dimensions remain `1024 × 768`. This is not accepted as visual evidence and
  is currently classified as an unresolved bootstrap/capture residual, not a
  Figma gap or a reason to patch layout from the screenshot alone.
- Next step: reproduce the reload behavior in a clean authenticated Chrome
  session at the full matrix and inspect/bootstrap-fix only if the defect is
  observable after Flutter has settled. If a stable runtime state exposes a
  missing visual element, stop and create/read back an approved Figma node
  before any UI edit. Keep OPS-44 `Ready for QA`.

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
- 2026-08-04: After the approved `1928:59113` readback, Home speaker support is
  native on Android/iOS/iPadOS plus Windows; Windows keeps the local preset
  pack, mobile/tablet use authenticated server audio, and Web remains
  list-only. The provider/realtime/ack contract is unchanged.

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

Not complete. Local regression/build, staging deploy, Figma seven-page
inventory, merged-phase cleanup, authenticated Home Light/Dark screenshots and
the `39 × 4 = 156` static route/viewport geometry smoke are verified. The
state-by-state screenshot comparison, physical Android/Windows audio evidence,
iOS/iPadOS runtime evidence, legacy visual retirement sign-off and production
deployment remain pending. Record each verified/unverified surface, residual
risk and next step before moving this plan to `docs/plans/completed/`.

## Home wide parity correction — 2026-08-04

Authenticated staging was rechecked in Light mode at the approved Home route
after the user reported a visible mismatch. The stable runtime state is a real
visual drift, not a theme/capture-only issue:

- Figma `326:2698` (`/home · App Shell Desktop · Loaded · Runtime scroll`) maps
  `326:2732` → `HomeSummaryHeader`, `326:2821`/`326:2868`/`326:2749` → section
  headers, `326:2867` → `ReportProgressPanel`, `326:2818` → sales metric grid,
  `326:3025` → KPI metric grid, `326:3119` → behavior grid and `326:3181` →
  finance grid.
- Wide header target is `1126×166`, with 48px avatar, 18/26 greeting,
  14/20 subtitle and 26px scope/date/update chips. The current runtime wide
  header is 64px and renders a duplicate page title instead.
- Sales target uses six 174.33×182 cards with 16px padding, 36px info icon
  tile, 14/20 semibold title, 18/26 value, status pill and 13/18 helper copy.
  Current runtime uses iconless 104px cards, so this is an implementation gap.
- KPI target is 5/5/4 cards at 164/136/136px; behavior is 4/4 at 136px and
  finance is 5 cards at 164px. Existing provider/API/detail interactions and
  Vietnamese copy remain protected.
- Product authority still requires both `Tổng quan cá nhân` and
  `Tổng quan Miền/Vùng/Cửa hàng` goal cards. The approved Figma frame exposes
  one reusable `Goal Progress` instance, so implementation may reuse that
  approved component for both cards; no business state is removed or merged.

Required Chrome comparison matrix for this wave: Light and Dark at
`1440×900` wide plus regression checks at `1024×768`, `834×1112` and
`375×812`; loaded, loading, empty, permission/unavailable and retryable error
states remain downstream proof gates.

### Figma route-inventory cleanup — 2026-08-04

After the route-owner audit, the unified Desktop/Web page retained one Home
loaded owner (`326:2698`) plus the four Windows state owners
(`1277:117203`, `1277:117334`, `1277:117458`, `1277:117594`). The following
mistaken duplicates were removed from Figma and read back absent:

- Desktop Home responsive proof frames `1444:32260`, `1444:131815`.
- Duplicate Web Home runtime frame `1204:354`.
- 54 `Archived / Web Responsive / …` route/state frames that remained on the
  unified page after the old Web page was consolidated.
- Android Home 412×915 responsive proof `1443:21701`; compact Home authority
  remains `331:3160`.
- Obsolete Web Responsive guide/runtime references `1174:31544`, `1204:2`,
  `1204:158`, `1204:492` and the stale dark runtime reference `1796:16408`.

This is a Figma-only cleanup; runtime routes and platform behavior are
unchanged. Desktop/Web now has a single Home loaded source, while platform
states remain explicit and are not inferred from another viewport.

## Execution plan v2 addendum — shared App Logo and Windows state composition — 2026-08-05

This addendum is part of the active OPS-44 execution plan. It records the
previously approved logo contract and the newly verified Figma/runtime gaps;
the logo foundation readback is now complete, while Windows state composition
and full cross-viewport visual closure remain open.

### Foundation logo contract (must be completed before shell/state closure)

- [x] Keep exactly one reusable Figma `App Logo` component set on `Foundation`
      (`1590:139700`) with the approved platform size lanes:
      `Size=Small` `1590:139697` = 32×32, `Size=Medium` `1590:139698` =
      44×44, and `Size=Large` `1590:139699` = 56×56.
- [x] Preserve the approved logo rule on every variant: 1px visible stroke
      aligned `INSIDE`; do not recreate the outline in a shell instance or
      add a second border layer.
- [x] Revise/read back the stroke semantic for the navigation surface. The
      three masters now bind to `component/color/navigation/content` (`8:158`)
      for both Light/Dark navigation surfaces; the prior Large binding to
      `color/semantic/text/primary` (`8:79`) was removed. If the logo is also
      required on a non-navigation surface, add an explicit Foundation surface
      variant rather than inferring a context-dependent stroke in screen code.
- [x] Audit every Figma consumer after the master revision: Desktop/Web
      `Breakpoint=Desktop` shell/state owners use 56px, Tablet/rail and
      iPadOS/Web rail owners use 44px, and compact/mobile consumers use the
      approved 32px lane where a logo is visible. Read back metadata and
      screenshots for Light and Dark; no consumer may keep an old override.
- [ ] Mirror the same single-component contract in Flutter. `AppLogo` must
      receive the surface-aware stroke token, Desktop/Tablet/Mobile shell
      consumers must use the approved size lane, and the temporary Desktop
      `DecoratedBox` overlay in `AppShell` must be removed. The current mobile
      drawer `42px` call is not one of the approved Figma lanes and must be
      resolved through the exact revised node before editing.
- [ ] Add widget/golden proof for stroke alignment/visibility and geometry at
      56/44/32px in Light and Dark, plus affected `AppShell`, auth-brand and
      route-state consumers. Existing size-only assertions are insufficient.

Figma readback proof completed 2026-08-05: masters `1590:139697`,
`1590:139698`, `1590:139699` report sizes 32/44/56, `strokeAlign=INSIDE`,
`strokeWeight=1`, visible stroke and `VariableID:8:158`; shell instances
`229:841`/`229:60` report Large=56 and Medium=44. Runtime/widget proof passed
for AppLogo, AppShell route replacement, auth shell and Home (57 tests total).
Remaining logo gate is Light/Dark golden/Chrome evidence at every affected
viewport, including compact/mobile lane confirmation.

### Windows route-state composition gap (Figma-first, before runtime edit)

- [ ] Keep the shared `platform-shell` main component `229:841`, but revise
      the route-state composition so route title/description are not duplicated
      as raw siblings below the shell topbar. The current 20 simple Windows
      states (`/home`, Payment Monitor, Sao ke, Feedback and Help) all use raw
      `runtime-state-panel` frames instead of the Foundation `State Panel`
      component set `115:258` or `Status Banner` set `120:364`; loading states
      also omit the required shared `Phosphor / SpinnerGap` instance.
- [ ] Create/revise exact Foundation-backed state nodes for every affected
      state and viewport, including semantic icon, title/body, action geometry,
      offline/unsupported and long Vietnamese copy. Reuse existing Foundation
      primitives; do not invent a route, permission or business state.
- [ ] Read back each revised node with `get_metadata`, `get_screenshot` and
      `get_design_context`, record the node map here/Linear, obtain approval,
      then migrate the 20 state owners. The 14 Sales Report modal owners remain
      on their existing fixed-header/scroll-body pattern unless a separate
      approved gap is found.

### Windows state proposal readback — 2026-08-05

The exact missing composition was created as a Figma proposal before any
runtime edit. It reuses the existing `platform-shell` main component and
Foundation `State Panel` variants; it does not add routes, permissions, API
states or business behavior. Đại Ca approved the centered revision on
2026-08-05; the Figma section now carries the `APPROVED` authority name and
runtime migration is unblocked for this exact node map.

- [x] Existing owners were read back from `Screens — Desktop · Windows + Web`:
      Home `1277:117203/117334/117458/117594`, Payment Monitor
      `1277:117732/117863/117987/118123`, Sao ke
      `1277:118261/118392/118516/118652`, Feedback
      `1277:118776/118902/119026/119150`, and Help content
      `1277:119286/119417/119543/119679`. Each had the shared shell plus raw
      route title/description and raw `runtime-state-panel`; Loading had no
      Foundation `SpinnerGap` composition.
- [x] Created proposal section `1967:57694` at the unified Desktop/Web page,
      with 20 exact 1440×900 Windows owners. Every owner contains shared
      `platform-shell` `229:841`, a `route_viewport / Foundation State Panel
      slot` at `250,72` sized `1190×828`, and one Foundation state instance
      centered inside that slot; route title/description are overridden in the
      shell topbar and are not duplicated below it.
- [x] Readback passed through `get_metadata`, `get_screenshot` and
      `get_design_context`. Section metadata reports 20 composition frames;
      Home Loading screenshot is `f4e1a405-e9f7-4cd1-9aaa-a9d5621160c7.png`,
      full proposal screenshot is
      `548b0d60-063f-4bd9-8a15-f9d8a33522b7.png` (6000×5080 source).
- [x] Centering correction read back on 2026-08-05: all 20 Foundation State
      Panel instances use `x=355` inside the `1190px` route viewport, which
      centers the `480px` panel horizontally. Vertical centering is explicit
      per variant height: `y=342` for 144px panels, `y=332` for 164px panels,
      and `y=304` for 220px panels. Metadata confirms every instance remains
      inside its route viewport; the full-section render shows the same visual
      center across Home, Payment Monitor, Sao kê, Feedback and Help states.
- [x] Obtain explicit proposal/revision approval for `1967:57694`; Figma
      section `1967:57694` is now named
      `APPROVED — Windows route-state composition · Foundation State Panel`,
      and approval/readback was recorded in Linear on 2026-08-05.

Approval readback on 2026-08-05 confirms the revised section name, centered
coordinates and unchanged 20-frame hierarchy. This approval applies only to
the exact Windows route-state composition; it does not approve unrelated
visual drift or a new Figma state.

#### Exact route/state node map

| Route | State | Composition frame | Foundation instance | Variant/source |
| --- | --- | --- | --- | --- |
| `/home` | Loading | `1967:57695` | `1967:57815` | Loading `115:50` |
| `/home` | Empty | `1967:57822` | `1967:57942` | Neutral `114:2`, action hidden |
| `/home` | Error | `1967:57952` | `1967:58072` | Error `115:38` |
| `/home` | PartialOffline | `1967:58082` | `1967:58202` | Offline `1277:121515`, action hidden |
| `/payment-monitor` | Loading | `1967:58212` | `1967:58332` | Loading `115:50` |
| `/payment-monitor` | Empty | `1967:58339` | `1967:58459` | Filtered Empty `1277:121503`, action hidden |
| `/payment-monitor` | Error | `1967:58469` | `1967:58589` | Error `115:38` |
| `/payment-monitor` | Unsupported | `1967:58599` | `1967:58719` | Unsupported `1277:121551` |
| `/bank-statement` | Loading | `1967:58727` | `1967:58847` | Loading `115:50` |
| `/bank-statement` | Empty | `1967:58854` | `1967:58974` | Neutral `114:2`, action hidden |
| `/bank-statement` | Error | `1967:58984` | `1967:59104` | Error `115:38` |
| `/bank-statement` | AutoSearch | `1967:59114` | `1967:59234` | Loading `115:50` |
| `/feedback` | Ready | `1967:59241` | `1967:59361` | Info `115:2` |
| `/feedback` | Uploading | `1967:59371` | `1967:59491` | Loading `115:50` |
| `/feedback` | Success | `1967:59498` | `1967:59618` | Success `115:14`, action hidden |
| `/feedback` | Error | `1967:59628` | `1967:59748` | Error `115:38` |
| `/admin/help-content` | Loading | `1967:59758` | `1967:59878` | Loading `115:50` |
| `/admin/help-content` | Empty | `1967:59885` | `1967:60005` | Neutral `114:2` |
| `/admin/help-content` | Error | `1967:60015` | `1967:60135` | Error `115:38` |
| `/admin/help-content` | DirtyClose | `1967:60145` | `1967:60265` | Warning `115:26` |

The title, message and action copy in the proposal were copied from the
existing owner readback. The only structural change is replacing the raw
panel with the shared Foundation instance and moving route context into the
shared shell slot. The 14 Sales Report modal owners remain outside this wave.

### Phase execution and safe cleanup

- [x] Start the logo/state wave on `codex/ops-44-full-chrome-audit` from the
      exact live `origin/staging` SHA `eb9e940a7e1528346f7efa105c43059b0dddf79b`;
      the prior merged overflow wave was cleaned through the guarded lifecycle
      before this worktree was created.
- [ ] Before every visual edit: capture branch/SHA/worktree/diff checkpoint,
      verify exact Figma node/revision and node map, then run focused geometry
      proof before any downstream build or staging audit.
- [ ] After the wave is merged and staging proof is recorded, run guarded
      `scripts/task-lifecycle.mjs finish --execute`, verify the merged PR/SHA,
      remove only the registered OPS-44 task worktree/local branch, and run
      `git fetch origin --prune`. Never delete the preserved OPS-27 worktree or
      a dirty/unmerged branch, and never force-push or bypass the lifecycle gate.

#### Full audit continuation — 2026-08-06

- Figma proposal `1995:57158` is now explicitly approved by Đại Ca. The two
  authority text nodes (`1995:57160`, `1995:57189`) read back as `Approved
  authority`; geometry and the two approved card instances are unchanged.
- The compact shell logo consumer now uses the approved `32×32` lane and has a
  stable `mobile-drawer-logo` key; the tablet rail remains `44×44` and the
  desktop sidebar remains `56×56`. Focused AppShell/AppLogo proof passes
  `29/29`, analyzer is clean, and `git diff --check` passes.
- Route/modal inventory confirms 45 router declarations, 40 authenticated
  smoke routes, and the shared/feature overlay call sites are catalogued in
  the route audit. The loaded-state staging smoke is not sufficient to close
  the per-state gate: loading, empty, retryable error, permission/unsupported,
  dialogs and modal interactions still need authenticated Chrome evidence.
- Chrome extension is currently unavailable in this session; the only
  connected surface is In-app Browser, which cannot substitute for the
  explicitly requested Chrome audit. No Chrome pass is claimed until the
  extension is connected.

## Logo audit correction — Đại Ca confirmation — 2026-08-05

This section is an explicit implementation-plan correction from the latest
shell audit. It is a blocker for visual closure, not a license to infer a new
logo treatment in runtime code.

### Observed mismatch and root cause

- Figma already has one shared `App Logo` component set `1590:139700` with
  `Small=32`, `Medium=44` and `Large=56`; every master is intended to keep a
  1px `strokeAlign=INSIDE` outline.
- The Large master was previously bound to `color/semantic/text/primary`
  (`8:79`). On the Light navigation surface `#111827`, that stroke was nearly
  the same color as the sidebar and visually disappeared.
- Flutter `AppLogo` previously resolved `textPrimary` for every surface. The
  Desktop shell then added a separate `DecoratedBox` white outline as a
  workaround, violating the decision that one shared logo component owns the
  stroke.
- The mobile drawer used `42px`, which is not one of the approved Figma size
  lanes. The current checkpoint has moved that call to `44px`, but compact
  `<600` still needs an explicit `32px` consumer map; it must not be treated as
  complete until the exact compact node and responsive rule are proven.
- Existing tests asserted only widget dimensions; they did not prove stroke
  visibility/contrast, Light/Dark surface semantics, or all shell/auth
  consumers.

### Authority decision and ordered work

1. Keep exactly one Figma master set (`1590:139700`) and bind all three
   variants to `component/color/navigation/content` (`8:158`) for navigation
   surfaces in both Light and Dark. If a non-navigation surface needs a
   different stroke, add an explicit Foundation surface variant first; do not
   branch stroke colors in a route screen.
2. Mirror that contract in Flutter through the shared `AppLogo` API with a
   surface-aware stroke token. Remove the Desktop `DecoratedBox` overlay and
   map consumers by the approved lane: Desktop/Web sidebar `56px`, Tablet/rail
   `44px`, compact/mobile drawer `32px` (unless an exact approved node records
   a different platform surface). Preserve auth/logo behavior and all
   business, route, permission, platform and data contracts.
3. Add geometry and contrast proof for `56/44/32px` in Light and Dark, covering
   the shared component plus Desktop sidebar, Tablet rail, compact drawer,
   auth brand and route-state shell consumers. Size-only assertions are not
   sufficient; proof must show the 1px inside stroke is visible on the actual
   navigation surface.
4. Re-run the strict downstream gate after any visual change: exact Figma
   node/revision and node map → widget/golden proof → exact-SHA build →
   staging deploy → authenticated Chrome comparison at
   `375×812`, `834×1112`, `1024×768` and `1440×900`, in Light and Dark. A
   failed or stale proof keeps OPS-44 open and blocks legacy-UI retirement.

### Current checkpoint and residual risk

- Figma master repair and readback are complete: `1590:139697`/`98`/`99`
  report `32/44/56`, `strokeAlign=INSIDE`, `strokeWeight=1`, visible stroke and
  `VariableID:8:158`; shell consumers `229:841` and `229:60` report
  `Large=56` and `Medium=44`.
- The current OPS-44 working tree removes the Desktop overlay, passes the
  navigation stroke explicitly to `AppLogo`, and uses `56px` Desktop plus
  `44px` Tablet/rail. Prior focused AppLogo/AppShell/auth/Home proof is
  `57/57`; full analyzer/regression proof is recorded in the checkpoint.
- Compact/mobile responsive logo mapping, Light/Dark golden contrast and the
  authenticated Chrome matrix remain open. Do not mark the logo foundation or
  OPS-44 visually complete until those proofs are captured and read back.

## Execution continuation — Dark mode remediation and Home goal parity — 2026-08-05

This continuation reopens the visual audit after Đại Ca's authenticated/runtime
captures showed that the earlier local Dark semantic proof was incomplete. The
captures are treated as failed visual evidence, not as a product change. The
Figma file remains the visual source of truth; business, API, permission,
route, platform and data behavior remain protected.

### Exact authority and node map before runtime edit

| Surface/state | Figma authority | Flutter scope | Required visual mapping |
| --- | --- | --- | --- |
| Home Light loaded | `326:2698` → shell `326:2699`, content `326:2731`, header `326:2732` | `AppShell`, `HomeScreen`, `HomeSummaryPage` | 1190×828 viewport; 1126×166 header; progress overview `326:2867`; sales/KPI/behavior/finance rows `326:2818`, `326:3025`, `326:3119`, `326:3181`; shared `Home Metric Card`/`Progress Ring`/`Goal Progress` instances |
| Home Dark loaded | `1874:123632` → shell `1874:123633`, content `1874:123634`, header `1874:123635` | same consumers, Dark semantic mode | same geometry as Light; canvas/card/text/border/icon values resolve through Dark tokens, with no raw Light surface or dark-on-dark text |
| Sao kê Dark loaded | `1874:129947` → content `1874:129949`, filters `1874:129952`, list `1874:129964`, pagination `1874:129968` | `BankStatementScreen`, shared fields/cards/pagination | `1190×828` content, 1126px filter/list lane, Dark input/card/border/text semantics, actions remain visible |
| Organization Dark edit | `1874:125723` → content `1874:125725`, modal `1874:125758` | `OrganizationTreeAdminScreen`, shared dialog/form primitives | Dark scrim, `960×760` editor, shared field/button surfaces, readable labels and fixed dialog actions |
| Admin modal/state states | `1874:131679`, `1874:131712`, `1874:131499`, `1874:131524`, `1874:131745` | Admin Users/Features/Organization dialog consumers | shared dialog shell/body/actions; no raw white list rows or inconsistent black/white titles |
| Approved Windows route states | `1967:57694` → 20 centered owners | shared state/shell consumers | Foundation State Panel centered at `x=355`, `y=342/332/304`; route context remains in shared shell |

### Findings from the user captures

- Dark admin dialogs still render Light surfaces in list/checkbox/result rows;
  the white blocks are not approved Dark card/input tokens.
- Several dialog titles and helper labels resolve through mixed defaults, so
  some text is dark on Dark surfaces while other titles are light.
- Organization and feedback/media overlays need the shared Dark dialog/scrim
  and placeholder surface; no feature-local white dialog or image fallback may
  remain.
- Home runtime does not match `326:2698`/`1874:123632`: header/card hierarchy,
  card icon tiles, progress/goal composition and section geometry drift from the
  approved source. The existing provider, realtime, speaker, refresh and detail
  behavior stays unchanged.

### Ordered implementation phases

1. **Dark foundation sweep** — audit `AppColors`, `AppTheme`, `AppShell`,
   `AppCombobox`, state/dialog/card/button/input primitives and every affected
   consumer for raw Light tokens. Replace them with context-aware shared tokens;
   add regression coverage for Dark surfaces, title/body contrast, scrim,
   checkbox/list rows, focus and action states. Do not add feature-local theme
   variants.
2. **Dark route-state closure** — migrate the approved 20 Windows state owners
   to `1967:57694` after the foundation sweep, preserving state/business
   behavior and the centered `route_viewport` composition.
3. **Home runtime parity** — replace the old Home visual path with the exact
   `326:2698`/`1874:123632` structure: header, progress rings, both Goal
   Progress cards (personal + region/area/store), sales/KPI/behavior/finance
   metric grids, section headers, icons and responsive rows. Reuse shared
   components/tokens and keep all Home provider/API/permission/realtime/detail
   contracts intact.
4. **Goal proof and follow-up** — verify personal/scope goal selection, empty
   target, loading/error and permission variants against the approved Goal
   Progress source; then rerun full Home and affected-consumer proof.

### Verification matrix and stop conditions

- Before each visual edit: exact Figma metadata + screenshot + design-context
  readback, node map update, dirty-worktree checkpoint.
- Local proof: focused Dark primitive/dialog/admin/Sao kê/Home tests, geometry
  assertions at `375×812`, `834×1112`, `1024×768`, `1440×900`, migration guard,
  `flutter analyze --no-pub`, `flutter test --no-pub`, `flutter build web
  --release --no-pub --no-wasm-dry-run`, `dart format` and `git diff --check`.
- Downstream proof: exact tested SHA → staging deploy → authenticated Chrome
  Light/Dark screenshot comparison at all four viewports; repeat every
  downstream gate after a visual fix.
- Stop if any visible element lacks an approved node, if a raw white/light
  surface remains in Dark, if text/icon contrast is insufficient, or if Home
  behavior changes. OPS-44 stays open until the runtime evidence passes.

## Dark Figma legacy-route audit — 2026-08-05

The Dark coverage board `1874:35444` was read back with 121 top-level owners
and compared against the canonical unified page `693:17492` and the approved
Dark Home source `1874:123632`. The audit separates canonical Desktop/Windows
owners from Web/runtime clones so the file cannot present a retired Web layout
as an implementation target.

### Confirmed canonical owners to keep

- `1874:123632` — Dark Home Desktop loaded source. It uses the shared
  `App Shell / Home / Full Content` (`1874:123633`), the 1126×166 header,
  progress rings, Goal Progress, metric-card/icon rows and the approved
  responsive content spec. Its `Runtime scroll` suffix describes scrolling
  behavior; it is not the old Web clone and must not be deleted.
- The remaining Dark Desktop/App Shell route owners for Operations, Sao kê,
  admin, dialogs and the Windows responsive proofs remain in place until each
  has exact node/context proof or an approved replacement. The obsolete
  Windows state instances are tracked in the cleanup section below and are no
  longer part of the visual authority set.

### Confirmed legacy/duplicate owners removed

The following Dark nodes were Web-specific or explicitly runtime-only clones.
They had no authority once Web adopted the unified Desktop/Windows source and
were removed so they cannot be used as visual references:

| Node | Reason | Action |
| --- | --- | --- |
| `1874:146023` | `/home · Web 1440 · Loaded · Runtime`; old `OpsHub Web` shell and flat metric cards; screenshot/context differs from `1874:123632` | removed |
| `1874:146119` | `/operations · Web 1024 · Loaded`; Web-only responsive duplicate | removed |
| `1874:148062` | `/operations · Web 1280 · Loaded`; Web-only responsive duplicate | removed |
| `1874:148096` | `/operations · Web 1920 · Loaded`; Web-only responsive duplicate | removed |
| `1874:148130` | `/shell-topbar · Web · 1440 · Runtime actions`; runtime-only shell reference | removed |
| `1874:148142` | `/fifo-check · Web · 1024 · Loaded · R1`; Web-only FIFO clone | removed |
| `1874:148163` | `/fifo-check · Web · 1024 · Serial result · R1`; Web-only FIFO state clone | removed |

Deletion was limited to these exact top-level Dark nodes. No runtime route,
business logic, permissions or Web behavior is changed. Figma version-history
and `commitUndo` APIs are unsupported in MCP; the delete script was guarded by
exact parent/name checks and returned all removed IDs. Post-delete proof is
board metadata (`114` children, all seven IDs absent, no remaining top-level
Web/Runtime clone) plus the board screenshot recorded in Linear comment
`3f5cf40c-7fc2-4285-9e51-d3b01b642bec`. Unique Desktop routes without an
approved Dark target are not silently deleted; they remain a design/revision
gate for a later Figma proposal.

### Dark Windows state clone cleanup — completed

The same board also contained 20 old Dark Windows state instances with a raw
runtime composition and failed contrast (for example, Home Loading
`1874:142635` rendered a dark-on-dark state title inside a light-border
panel). The approved replacement composition is `1967:57694` (20 centered
Foundation-backed owners). These exact old state owners were removed after
parent/name checks and read back absent:

- Home: `1874:142635`, `1874:142759`, `1874:142883`, `1874:143009`.
- Payment Monitor: `1874:143133`, `1874:143257`, `1874:143381`, `1874:143507`.
- Sao kê: `1874:143631`, `1874:143755`, `1874:143879`, `1874:144005`.
- Feedback: `1874:144129`, `1874:144255`, `1874:144379`, `1874:144503`.
- Help content: `1874:144629`, `1874:144753`, `1874:144879`, `1874:145005`.

Readback: Dark board top-level count is now `94`; all 20 IDs are absent;
approved proposal `1967:57694` and canonical Home `1874:123632` remain. The
two Home Windows responsive proofs (`1874:145607`, `1874:145695`) are retained
as explicit viewport evidence, not state owners. This cleanup retires only
obsolete Figma references. The approved section is a composition authority;
Dark semantic styling still needs its own exact readback before runtime
migration. Unique Dark routes with raw light surfaces (admin dialogs, support
chats, API connections and similar) remain blocked for target revision rather
than being inferred from these deleted states.

### Follow-up gate — Sales Report Order Command

After Dark foundation/state closure, repair the approved Sales Report Order
Command alignment. The Android Tablet Ready/PendingPayment variants still have
708px content inside a 720px slot and need the verified `+6px` offset; the
previous direct `x` mutation was overwritten by auto-layout. Inspect and fix
the parent `layoutMode`/axis alignment, then read back metadata and screenshot
for Android Tablet (`1242:35190` family) and iPadOS (`1246:35945` family)
before runtime/UI completion. This follow-up does not change order workflow or
business behavior.

## Execution continuation — 2026-08-05 current checkpoint

The continuation is running on the existing dirty task worktree so the prior
Home/logo checkpoint is preserved:

- Branch/worktree: `codex/ops-44-home-wide-header-parity` at
  `C:\Users\ASUS1\Documents\flutter_projects\opshub-ops-44-home-wide-header`.
- HEAD and `origin/staging`: `424eaacce1a3b4d5b27eddf05af1e7c2cbe6bf7d`.
- Dirty scope is limited to the Home wide-parity, shared AppLogo/shell/auth
  checkpoint, tests and this plan; the unrelated OPS-27 worktree remains
  untouched. Do not delete this branch/worktree until its PR has merged and
  the guarded lifecycle `finish --execute` gate passes.
- Local proof at this checkpoint: `flutter analyze --no-pub` passes; focused
  AppLogo/AppShell/auth/Home proof passes `57/57`; `git diff --check` passes.

Figma cleanup proof completed before runtime edits:

- Dark board `1874:35444` now has `94` top-level owners after removing seven
  Web/runtime clones and twenty obsolete Dark Windows state owners. Canonical
  Home `1874:123632` and approved composition proposal `1967:57694` remain.
- The remaining raw-light Dark dialog/route owners are explicit Figma
  revision gates, not visual references. If they lack exact approved nodes,
  create a proposal from Foundation components, read back metadata + screenshot
  + design context, record the complete node map and obtain approval before
  touching the corresponding Flutter surface.

Next ordered work:

1. Create/read back the missing Dark dialog/media/admin target proposal and
   update Linear/this plan; do not infer from the old runtime surfaces.
2. Finish the approved Home/logo runtime checkpoint and add Light/Dark
   56/44/32px golden/contrast proof.
3. Migrate the approved centered Windows state consumers only after the exact
   Dark semantic target is available.
4. Fix Sales Report Order Command through parent auto-layout alignment and
   verify both platform families.
5. Run exact-SHA build/staging/Chrome/platform gates, record Linear proof, then
   clean only the merged OPS-44 branch/worktree with the guarded lifecycle
   command. The active plan stays open until production deployment and legacy
   retirement are proven.

## Execution continuation — Dark semantic sweep + Sales Report Order Command — 2026-08-05

### Implemented scope

- Shared Dark foundation now exposes context-aware neutral scale helpers and a
  base-token adapter for shared chips, status pills, feature tiles, notification
  badges, skeletons, toasts and state panels. Light values remain unchanged;
  QR/image/camera foregrounds that intentionally require white/black contrast
  remain explicit and are not remapped.
- Runtime Dark consumers were swept across FIFO/FIFO Check, Admin
  policy/role/feature/import/personnel, Contract Appendix, Sales Report
  admin/import/not-purchased, Payment Monitor/history, Help admin, Notifications,
  Home trend, Offset, Sort, VietQR, Warranty, Settings and Quick Actions.
  Changes are semantic-token substitutions only; provider/API/permission/route,
  workflow and Vietnamese copy contracts are untouched.
- Sales Report Order Command remains the single approved visual path. Runtime
  keeps input + QR scan + primary action on one row at compact/medium/desktop,
  uses the approved 222px action for NeedsCheck/Checking and 202px action for
  Ready/PendingPayment with the Wide/Tablet parent padding (`4px`/`6px`).
  Android compact keeps status as input supporting text; iOS/iPadOS uses the
  approved 44pt scan control and status text below the command row. Geometry
  proof covers `375×812` and `1024×768` plus checked-state action sizing.

### Authority / node map

- Figma file `mFzSmQzlapSe3RSmUhvzll`; Dark route board `1874:35444` was read
  back as the canonical Dark coverage board. The unified page remains
  `Screens — Desktop · Windows + Web`; no route/frame was invented or added.
- Sales Report Order Command Foundation masters read back as component sets:
  Wide `1237:32820` (Ready `1237:32775`, pending `1237:32801`), Android Tablet
  `1242:35190` (Ready `1242:35199`, pending `1242:35205`), Android Mobile
  `1242:34112`, iOS `1244:35494`, iPadOS `1246:35945`. Parent auto-layout
  padding is the authority (`4px` Wide, `6px` Tablet); direct child x-offsets
  are not used.
- Figma metadata/design-context readback confirms input, scan, status and
  action geometry; all five platform families remain present. This pass did
  not alter business states or create duplicate route owners.

### Local verification

- `flutter analyze --no-pub`: pass.
- Focused theme/state/Sales Report suite: pass; Sales Report hub is `42/42`,
  shared Dark/state tests pass, and the new Dark Order Command control test
  passes.
- Full `flutter test --no-pub --reporter compact`: exit code `0`, `747` passed,
  `3` existing skips, zero failures. The earlier expanded-reporter timeout was
  an output-pipe timeout and was superseded by this successful compact run.
- After the Order Command width/state correction, the focused Sales Report
  suite passes `32/32` including iOS/iPadOS geometry; the combined
  Dark/theme/logo/Sales proof passes `41/41`.
- `flutter build web --release --no-pub`: pass; Wasm dry run also succeeded.
- `dart format` and `git diff --check`: rerun after the final patch; no known
  formatting or whitespace errors.

### Remaining gate / risk

- Worktree is intentionally dirty and has not been committed, pushed, merged,
  deployed or promoted. Staging and authenticated Chrome comparison remain
  required at `375×812`, `834×1112`, `1024×768`, `1440×900` in Light/Dark, plus
  Windows/Android primary evidence and iOS/iPadOS regression evidence.
- The semantic sweep is locally verified but has no staging screenshot proof;
  any unapproved Chrome drift remains a blocker. OPS-44 stays open and must not
  move to Done until production deployment and legacy visual retirement pass.

### Next step

Create the exact-SHA PR to `staging`, deploy that SHA, then run the authenticated
Chrome matrix and record per-viewport Figma/runtime verdicts before any cleanup
or status transition.

## Execution plan v2 continuation contract — 2026-08-05

The remaining phases are executed as bounded waves and may be marked complete
only with the evidence below. A phase is not considered complete merely because
local tests pass.

### Figma gap protocol (mandatory for every remaining wave)

If a stable runtime audit exposes a visible element, state, platform variant or
responsive constraint that has no exact approved Figma node, stop that visual
edit. Inspect the existing Foundation component/library first, create or revise
the target in the canonical Figma page using shared components/tokens, then run
`get_metadata` → `get_screenshot` → `get_design_context` readback. Record the
complete node map (viewport/state, geometry, tokens, typography, copy, icon,
behavior and responsive rule) in this plan and Linear, obtain explicit approval,
and only then mirror the node in Flutter. Never infer from legacy runtime,
screenshots alone or a guessed spacing/token value. Re-run geometry tests, build,
staging deploy and Chrome comparison after every approved revision.

### Bounded phase and cleanup gate

1. Phase A — finish current Dark/Sales/Home/logo implementation proof and create
   the exact-SHA PR; keep the dirty checkpoint until the PR source is verified.
2. Phase B — deploy the merged SHA to staging and audit authenticated Chrome at
   `375×812`, `834×1112`, `1024×768`, `1440×900` in Light/Dark, covering every
   affected loaded/loading/empty/error/dialog/permission state.
3. Phase C — capture Windows/Android primary evidence and iOS/iPadOS regression
   evidence; classify every drift as a code fix or the Figma-gap protocol above.
4. Phase D — prove no migrated route can render a legacy visual path, record the
   final Linear implementation/proof note, promote to production, and only then
   move OPS-44 to Done.

After each merged wave, run the guarded lifecycle `finish --execute` from the
clean canonical `staging` worktree with the exact PR/branch/worktree arguments.
The gate must verify merged SHA, clean task worktree and branch ownership before
removing anything. Remote branches are deleted only as a separate reviewed
publication action; never remove the preserved OPS-27 worktree or a dirty,
unmerged task branch.

## Figma gap readback — Home finance compatibility cards — 2026-08-05

Runtime audit found two visible compatibility metrics with no exact node in the
approved Finance source `326:3181`: `HomeSummary.totalStatementsTracked`
(`Sao kê đang theo dõi`) and `HomeSummary.totalStatementsUnfollowed`
(`Sao kê đã bỏ theo dõi`). Per the gap protocol, the target was added to the
canonical pages before any runtime visual cutover:

- Foundation icon masters were added to `FOUNDATION / Icons — Phosphor`
  (`683:20`): `1994:55498` `__Icon / Phosphor / Eye` and `1994:55501`
  `__Icon / Phosphor / EyeSlash`, both 20×20 official Phosphor Core Regular
  vectors in the existing #2563EB icon treatment.
- Desktop/Web proposal section `1995:57158` (`1180×420`,
  `PROPOSAL — Home finance compatibility cards`) reuses the approved
  `_Screen / Home Metric Card` component `275:1050` and maps:
  `1995:57161` → `Sao kê đang theo dõi`, value `48`, Eye Regular, delta and
  supporting copy `Dùng để tính tỷ lệ`; `1995:57175` → `Sao kê đã bỏ theo dõi`,
  value `12`, EyeSlash Regular, delta and supporting copy `Không tính đối
  chiếu đơn`. Proposal footer records the runtime fields and the fact that
  `326:3181` remains a five-card approved source.
- Readback passed: page `693:17492` inspection, Foundation metadata, proposal
  metadata, screenshots and `get_design_context` for both proposal card nodes.
  The Figma Plugin runtime does not support `saveVersionHistoryAsync`, so a
  version-history checkpoint must be created by the Figma UI/owner as part of
  explicit proposal approval; the node proposal is present and reviewable.

Approval recorded 2026-08-06: Đại Ca approved proposal `1995:57158` and its
current revision. The proposal note and authority footer now explicitly say
`Approved authority`, preserve the two protected runtime metrics, and state
that no route, permission, or business behavior is introduced. The approval
readback re-ran `get_design_context`, `get_metadata`, and `get_screenshot`; the
section geometry and component instances remain unchanged. The two-card gap
ledger may now be closed only after the downstream runtime geometry, exact-SHA
staging, and authenticated Chrome comparison pass.

## Branch cleanup continuation — 2026-08-05

- PR #111 was read back as `MERGED`, base `staging`, merge SHA
  `cbafa85aca7e86b188de34040271bfb765d38997`; no open PR referenced
  `codex/ops-44-home-wide-header-parity`, so its remote branch was deleted and
  `git fetch origin --prune` confirms no `origin/codex/ops-44*` refs remain.
- Canonical `staging` remains clean and equal to `origin/staging` at the same
  SHA. The active dirty branch `codex/ops-44-home-parity-dark-sales` is kept
  because it contains the uncommitted Home icon/proof wave; it must not be
  deleted before PR/merge and the guarded lifecycle finish gate. OPS-27's
  worktree/branch remains untouched.
- Several old OPS-44 directory names were inspected and contain zero files,
  zero subdirectories and no `.git`/worktree registration. They are OS-level
  empty-directory residue only; no branch or Git state is associated with
  them.

## Execution continuation — Home wide composition parity + final Dark/Sales audit — 2026-08-05

This wave starts from exact `origin/staging` SHA `cbafa85aca7e86b188de34040271bfb765d38997`
on task branch `codex/ops-44-home-parity-dark-sales`.

### Approved node map before the first production UI edit

- Desktop/Web Home `326:2698` → `HomeScreen`/`HomeSummaryPage` and shared
  `AppShell`; wide content lane `1126×828` inside the `1440×900` shell.
- Home header `326:2732` → `HomeSummaryHeader`; `1126×166`, 48px avatar,
  greeting/subtitle and scope/date/update controls. Existing provider refresh,
  scope/date selection, speaker action and warning behavior are protected.
- Overview `326:2821` + progress row `326:2867` → shared section heading,
  two `Progress Ring` cards and one desktop `Goal Progress` card. Wide cards
  are `364.67×248`, `364.67×248`, and `364.67×208`; expanded `713:19442`
  uses three `285.33px` columns; medium `713:18949`/`713:18951` stacks rings
  and both goal states; compact `331:3219`/`331:3235`/`331:3249`/
  `331:3263` stacks both goal cards.
- Sales metric row `326:2818` → `SummaryCardGrid`: six `174.33×182` wide
  cards with the approved 36px icon tile and 24px semantic icon. The same
  metric family maps to expanded `713:19452` (3 columns × 146px), medium
  `713:18962` (single column × 136px) and compact `331:3335` (2 columns ×
  184px). KPI, behavior and finance groups use the corresponding approved
  row maps in `326:3025`, `326:3119`, `326:3181` and the tablet/mobile
  descendants; no legacy 104px iconless card path is allowed.
- Dark Home `1874:123632` is the exact Dark semantic counterpart for the wide
  loaded state. Dark canvas/surface/card/border/text mappings remain shared
  tokens; no Light frame is edited.
- Icon authority readback for every Home metric group confirmed the runtime
  Material/icon-semantic drift. Figma `326:2818` maps the sales row to
  `CurrencyCircleDollar`, `Receipt`, `ArrowsLeftRight`, `CheckCircle`,
  `ClockCounterClockwise`, and `SortAscending`; `326:3025` maps KPI cards to
  `Buildings`, `UserCircle`, `Gift`, `GraduationCap`, `HandCoins`,
  `CheckCircle`, `ShieldCheck`, `Laptop`, `DesktopTower`, `Cpu`, `AppleLogo`,
  `Monitor`, `Printer`, and `Package`; `326:3119` maps behavior cards to
  `MagnifyingGlass`, `ClockCounterClockwise`, `Receipt`, `ShieldCheck`,
  `SquaresFour`, `Info`, `Bell`, and `DownloadSimple`; `326:3181` maps
  finance cards to `CurrencyCircleDollar`, `Receipt`, `Notepad`,
  `WarningCircle`, and `ArrowsLeftRight`. All Figma-covered runtime consumers
  now use the approved Phosphor Regular vectors; the two compatibility-only
  statement tracking cards remain outside the approved finance node and are
  tracked as a Figma authority gap. No business or navigation behavior
  changes.
- Sales Report Order Command remains governed by Foundation component sets
  `1237:32820`, `1242:35190`, `1242:34112`, `1244:35494`, `1246:35945`.
  This wave re-runs the exact wide/tablet/mobile/iOS/iPadOS geometry proof
  after Home changes; command input, scan, status, action width, and same-row
  behavior remain unchanged.

### Implementation boundaries

- Remove only the legacy Home composition drift: extra wide `Tiến độ hoạt động`
  heading, two simultaneous desktop goal cards, 104px iconless metric cards,
  and unapproved grouping/column behavior. Preserve all provider/API,
  permission, route, detail-dialog, refresh, realtime, speaker and logging
  behavior.
- Use one shared metric-card implementation with the Figma icon tile and
  responsive row rules; do not add feature-local tokens or a fallback visual
  path. Compact/medium/expanded/wide use the approved breakpoint matrix.
- If Chrome exposes a visible state not covered by the node map, stop that
  visual edit and apply the Figma gap protocol above before changing runtime.

### Proof target

Focused Home geometry/state tests, Sales Report Order Command suite, full
Flutter regression, analyzer, format/diff checks and web release build must
pass before PR. After merge/deploy, authenticated Chrome must compare Light and
Dark at `375×812`, `834×1112`, `1024×768`, `1440×900`, then record Windows/
Android primary and iOS/iPadOS regression evidence. OPS-44 remains `Ready for
QA`; no Done transition is allowed before production deployment and legacy
visual-retirement proof.

### Current local proof — 2026-08-05

- Home geometry/state focused proof passes `33/33`; the desktop composition now
  keeps the approved two ring cards plus one `Doanh số cá nhân` goal card,
  removes the legacy wide progress heading/duplicate goal slot, and uses the
  approved icon-tile metric cards across wide/expanded/medium/compact lanes.
  Provider/API/permission/route/realtime/detail-dialog/speaker/AppLogger
  behavior remains covered by the existing Home suite.
- Sales Report Order Command focused proof passes `32/32`; the same-row input,
  scan and primary action geometry remains intact after the Home wave, including
  compact, tablet, desktop and iOS/iPadOS cases.
- Dark/theme/logo/shell/Sales affected proof remains `83/83`; full Flutter
  regression passes `748` tests with `3` existing skips and zero failures after
  the exact icon correction.
  `flutter analyze --no-pub` reports no issues, `dart format` completed, and
  `git diff --check` passes the content diff.
- `flutter build web --release` passes for this exact worktree; the build's
  Wasm dry run also succeeds. A direct `flutter build web --release --wasm`
  invocation exceeded the local four-minute command limit and is therefore not
  claimed as a standalone Wasm build pass.

### Remaining visual/release risk

- The approved desktop Home node shows the staff-state goal card without the
  manager-only sales-assignee picker. The picker is retained because existing
  manager behavior/tests require selecting an SA and changing only sales KPIs;
  its manager role/state authority still needs an exact Figma state readback
  before the visual wave can be called complete.
- No staging deploy or authenticated Chrome comparison has been run for this
  uncommitted wave. Required Light/Dark matrix remains `375×812`, `834×1112`,
  `1024×768`, and `1440×900`, followed by platform evidence, legacy-retirement
  proof, production deployment, and only then a possible OPS-44 Done transition.

## Approved Home proposal addendum — 2026-08-05

Đại Ca approved the current Home proposal as the visual authority for this
implementation wave. The exact Figma frames are Light `2003:144150` and Dark
`2003:144247`; no legacy runtime composition may be used as a visual fallback.

### Exact node map and protected states

- Shared shell: `229:851`; desktop notification `2091:55501`, compact
  notification `2091:146729`, avatar `229:855`.
- Home header: Light `2009:58479`, Dark `2010:58453`; scope/date/update chips
  use HUG width and the loading icon replaces the info icon in-place.
- Overview: Light `2003:144157`, Dark `2003:144254`; 2 columns × 2 rows with
  progress bars, preserving day/week/month, personal/store, empty/loading,
  unavailable and retryable-error behavior.
- Notification badge set: `2100:56208`; variants `2100:56202` (7),
  `2100:56204` (99), and `2100:56206` (99+). Runtime contract remains hidden
  at zero and capped at `99+` above 99.
- Dark selected navigation content is the semantic action-primary token; it
  must resolve to the approved blue counterpart in dark mode just as Light
  selected content resolves to brand blue.
- Fresh Figma readback on 2026-08-05 reran `get_design_context` and
  `get_screenshot` for Light `2003:144150` and Dark `2003:144247`; both frames
  resolve to the approved Home shell/header and 2×2 progress-bar overview,
  with HUG scope/date/update chips, in-place loading icon variant, notification
  badge preview and the shared avatar/FAB stack. No new Figma gap was found;
  the readback is authority confirmation only and does not authorize a runtime
  fallback to the deployed baseline.

### Required Chrome proof matrix

Authenticated Chrome comparison must cover `375×812`, `834×1112`, `1024×768`,
and `1440×900` in both Light and Dark for loaded, loading, empty,
unavailable/permission, and retryable-error states where the route exposes
them. Capture the exact viewport dimensions, screenshot, console result, and
selected-nav/header/shell state for each run. Re-run widget/golden geometry,
focused tests, `flutter analyze --no-pub`, `git diff --check`, and
`flutter build web --release` after every visual fix.

### Local proof for Dark selected-navigation fix — 2026-08-05

- `AppColors.darkPrimary` now resolves to the approved `#8EA0FF` token;
  Dark hover/pressed values are aligned to `#AAB6FF`/`#6F83F7`.
- Focused theme and shell proof passes `29/29`, including a Dark desktop
  assertion that selected `Trang chủ` text uses `AppColors.darkPrimary`.
- `flutter analyze --no-pub` reports no issues; `git diff --check` passes;
  `flutter build web --release` succeeds (including the Wasm dry run).
- Authenticated staging/Chrome proof remains open because staging still needs
  the branch/deployed SHA; these local results do not claim the full OPS-44
  visual matrix complete.

### Local follow-up proof — selected navigation and responsive header — 2026-08-05

- Dark selected navigation now uses one explicit `selectedNavigationOf` token
  across desktop sidebar, tablet rail, mobile drawer and mobile bottom nav;
  Light/Dark shell assertions both pass, including the Dark `#8EA0FF` label.
- Header controls now measure their rendered content lane before sizing chips;
  compact Android controls and the optional speaker action stay in-bounds,
  while medium widths cap long chips so the action remains on the same row.
- Full `flutter test --no-pub --reporter json` completed with
  `{"success":true,"type":"done"}`; `flutter analyze --no-pub`,
  `git diff --check`, and `flutter build web --release` also pass.
- Staging deploy and authenticated Chrome matrix remain open; no commit,
  push, or release claim is made from this local worktree.

### Chrome audit checkpoint — 2026-08-05

- Connected Chrome to `https://opshub-staging.hoanghochoi.com/#/home` and
  confirmed the deployed bootstrap query is SHA `b0a0b0a3d274d0cd2a929cda1199a1c390169865`,
  equal to `HEAD`/`origin/staging` but not to the dirty worktree contents.
- The authenticated staging screenshot at the compact `375×812` viewport is
  baseline UI (donut overview, Support topbar action and text account action),
  so it is explicitly invalid as proof for the current uncommitted proposal
  wave. The browser reported no runtime console errors beyond Flutter service
  worker bootstrap debug messages.
- Served the current release artifact at `http://127.0.0.1:5174`; protected
  `/home` correctly redirects to `/login` because this local origin has no
  authenticated session. No cookie, storage or credential bypass was used.
- Chrome local tab is retained at the login screen for an explicit user sign-in;
  the four-viewport Light/Dark/state matrix remains unverified until that
  authentication gate is satisfied or the exact worktree SHA is deployed by
  an explicitly authorized staging action.

### Exact staging Chrome audit and Profile remediation — 2026-08-06

- Canonical `staging` was clean at
  `4aa9589fc1fa504e44d3aed9ec5c9429bb865d4e`; workflow
  [Deploy OpsHub Staging #31047971355](https://github.com/hoanghochoi/phongvu-opshub/actions/runs/31047971355)
  completed successfully for that exact SHA. Staging health returned `200`,
  web metadata returned `2026.08.05.340 / 200340`, and the bootstrap query
  contained the exact SHA.
- Authenticated Chrome Home proof covered Light/Dark at `375×812`,
  `834×1112`, `1024×768` and `1440×900`; shell selected state, responsive
  overview progress bars, header chips, scope dropdown, anchored shared date
  picker, settings theme selection, and read-aloud history modal were exercised.
  At each viewport `document.body.scrollWidth` equaled the viewport width.
- Chrome exposed a real Profile defect on both Light and Dark desktop states:
  the fixed 138px/116px action lanes rendered `Đổi mật ...` and `Đăng...`.
  Exact Figma readback of `306:3227` and `306:3219` confirms 48px actions,
  12px `labelSmall` copy, 18px/20px icons and the fixed widths.
- Remediation in `ProfileScreen` uses the approved Phosphor `LockKey` and
  `SignOut` icons, `AppTextStyles.labelS`, and fixed-width-safe shared
  `AppSecondaryButton` icon/padding overrides with a fitted content row. The
  shared button keeps existing defaults for all other consumers.
- Fresh local proof after remediation: Profile suite `4/4`, shared button
  suite `3/3`, `flutter analyze --no-pub` pass, and `git diff --check` pass.
  Staging deploy/Chrome rerun for this remediation remains downstream.
- The shell navigation no longer contains an `Hỗ trợ` item; an independent
  support FAB remains visible and is recorded as a product-scope question,
  not silently removed without authority.

### Exact staging deploy and Chrome QA — 2026-08-06

- Canonical `staging` is clean and equals `origin/staging` at
  `eb1f75519574feb8f55399d9a311db348918f31f`. Deploy workflow [Deploy OpsHub
  Staging #31055169680](https://github.com/hoanghochoi/phongvu-opshub/actions/runs/31055169680)
  completed successfully with that exact `headSha`. Staging `/health` returns
  `200 / ok`, `/api/app-version` returns build `200343` version
  `2026.08.05.343`, and the served bootstrap HTML contains the exact 40-byte
  SHA; release notes identify `Staging GitHub eb1f755`.
- Authenticated Chrome route smoke on the deployed SHA covered all 40
  authenticated routes at `375×812`, `834×1112`, `1024×768` and `1440×900` in
  Dark (160 route/viewport runs); all navigations completed and `/reports`
  redirected to `/sales-reports`. The earlier same-deploy Light run covered
  the same 40-route × 4-viewport matrix. No console errors or warnings were
  observed in either theme batch.
- Compact/medium/expanded/wide screenshots confirmed the shared shell, dark
  selected `Trang chủ` state, circular avatar, full-stroke logo, notification
  action, independent support FAB and responsive Home/header composition. The
  Home scope/date/update controls remained in-bounds; the deployed settings
  screen keeps `Hệ thống` readable at compact/medium widths.
- A browser DOM width probe reported a Flutter Web shell artifact on data-heavy
  expanded/wide routes (`body.scrollWidth` `1112` at `1024` and `1690` at
  `1440` while `documentElement.scrollWidth` stayed at the viewport width).
  `body`/`html` remained `overflow:hidden` and screenshots showed no visible
  horizontal clipping; retain this as a follow-up observation, not a shared
  layout change, until a visual failure is reproduced.
- This deploy/route smoke does not close the full OPS-44 visual gate: loading,
  empty, retryable-error, permission/unsupported and the complete dialog/modal
  inventory still require explicit state setup and Figma-node evidence before
  production promotion or `Done`.
