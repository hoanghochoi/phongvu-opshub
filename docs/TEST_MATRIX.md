# Test Matrix

This file maps product behavior to proof. Existing flows are marked
`existing_unverified` until fresh validation evidence is attached.

## Status Values

| Status              | Meaning                                                                    |
| ------------------- | -------------------------------------------------------------------------- |
| planned             | Accepted but not implemented                                               |
| in_progress         | Actively being built                                                       |
| existing_unverified | Existing code/docs claim the behavior, but no fresh proof is attached here |
| implemented         | Implemented and proof exists                                               |
| changed             | Contract changed after earlier implementation                              |
| retired             | No longer part of the product contract                                     |

## Current Release Security Proof

- `WINDOWS-DIST-001`, 2026-06-27: added a separate manual Microsoft Store MSIX
  packaging workflow and build script. Runtime distribution remains unchanged:
  production/staging deploys still publish the Inno EXE, ZIP, checksum,
  `/download`, and Windows `/app-version` EXE update URL. Validation target:
  workflow syntax, PowerShell parser, `flutter pub get`, `git diff --check`,
  and a Store MSIX CI run with Partner Center identity secrets before upload.
- `WINDOWS-DIST-001`, 2026-06-24: production setup `v2026.06.23.88+100088`
  was reproduced as `Trojan:Win32/Wacatac.B!ml` while its checksum-matched
  portable ZIP, extracted app, and previous setup `100087` scanned clean.
  Removed the installer's self-trust path, added a fail-closed Defender gate to
  production and staging after signing and before checksums/upload, and logged
  definition version, file size, SHA256, duration, and result. Local validation:
  PowerShell parser passed, both workflow YAML files parsed, no self-trust
  references remain, `flutter analyze --no-pub` passed, full
  `flutter test --no-pub --reporter compact` passed (133 tests), Windows release
  build passed, Inno compile passed, temporary self-signed app/installer signing
  passed, and Defender definition `1.453.245.0` scanned the final local signed
  ZIP and installer with no threats. Pending: signed production CI gate and live
  download verification.
- 2026-06-25 staging follow-up: Defender signature update now retries transient
  Windows runner update/installer locks such as `0x80070652`, while preserving
  the fail-closed artifact scan gate. Validation: PowerShell parser passed and
  local Defender smoke scan passed with `-SkipSignatureUpdate` against a temp
  file.

## Matrix

Recent focused evidence:

- `UI-UX-001`, 2026-07-01: started the OpsHub Redesign System 2026 repo import
  with Batch 1 foundation work. Authenticated routes now render inside a shared
  responsive `AppShell`: desktop persistent sidebar, tablet rail, mobile app bar
  plus bottom navigation for `Trang chủ`, `Tác vụ`, and `Tài khoản`. Added the
  `/tasks` workspace index, a shared permission-aware nav model that hides
  unavailable destinations and logs visible/hidden counts through `AppLogger`,
  and Figma variable parity tokens for sidebar/status/primary surface plus
  contextual light/dark surface/text/border helpers. Home is now content-only
  inside the shell and keeps its command-center cards, SR header info, feedback
  placement, payment speaker quick toggle, support QR flow through AppShell,
  and delivery metrics dialog behavior. Route gaps from the Figma file are
  recorded in `docs/product/opshub-redesign-gap-map-2026-07-01.md` and harness
  tech debt instead of being scaffolded prematurely. Validation: changed-file
  `dart format --output=none --set-exit-if-changed`, `flutter analyze --no-pub`,
  focused
  `flutter test --no-pub --reporter expanded test\app_nav_model_test.dart test\home_feedback_action_test.dart test\app_router_test.dart`
  (10 tests), full `flutter test --no-pub --reporter expanded` (237 tests),
  AppShell light/dark widget screenshots for desktop/tablet/mobile under the
  ignored `.screenshot/figma_merge`, Android production debug APK
  build/install/runtime login smoke on `21081111RG`, and `git diff --check`.
  Follow-up Android smoke caught mobile shell/Home header clipping in dark mode;
  the mobile header now places the delivery metrics pill on the left, the
  active title in the center, and support plus the notification bell on the
  right.
  Authenticated Android smoke also caught duplicated account avatars on mobile
  Home; account/profile entry now belongs to the bottom `Tài khoản` destination,
  while the Home card keeps only the user identity block. 2026-07-02 follow-up:
  removed the standalone Home/Tasks/sidebar `Sắp xếp` destination because
  sorting is already exposed as `Sắp xếp FIFO` inside the FIFO workspace; route
  `/sort` remains guarded by `FIFO` and selected under FIFO for compatibility.
  Web Chrome fullscreen smoke with a seeded local session verified Home has 9
  workspace actions with no standalone `Sắp xếp`, FIFO still shows `Sắp xếp
  FIFO`, and `/sort` opens the FIFO sort screen with FIFO selected
  (`output/playwright/sortfix-home-full.png`,
  `output/playwright/sortfix-fifo-full.png`,
  `output/playwright/sortfix-sort-full.png`). Follow-up validation reran full
  `flutter test --no-pub --reporter expanded` (238 tests),
  `flutter analyze --no-pub`, `flutter build web --debug --no-pub`,
  `flutter build windows --debug --no-pub`, and `git diff --check`. Windows
  debug runtime smoke with a live saved session refreshed through
  `/auth/get-user` verified Home has no standalone `Sắp xếp`, FIFO still shows
  `Sắp xếp FIFO`, and the sort screen opens with FIFO selected after dismissing
  the optional update dialog with `Để sau`. 2026-07-03 Web live HTTP smoke then
  built local Web with `APP_ENV=smoke` and
  `API_BASE_URL=http://127.0.0.1:8765/api`, served `build/web` through a local
  same-origin proxy, and used headed Playwright Chromium with the admin test
  account to prove `POST /api/auth/login` 201 plus `/api/features/me`,
  `/api/policies/me`, payment delivery metrics, statement notifications, and
  offset adjustments API calls returning 200. Runtime UI proof covered Home
  without standalone `Sắp xếp`, FIFO hub with `Sắp xếp FIFO`, sort form
  input/scan/empty state, Organization Tree search/no-result on live
  `/api/admin/org-tree` data, Sales Report hub/admin live 200 APIs with one
  `Xuất file` dropdown for `HVTC`/`Doanh số`/`Trả góp`, and `/profile`
  showing `Đăng xuất`. 2026-07-03 follow-up added
  `scripts/opshub-web-smoke-proxy.mjs` so the same Web smoke proxy also tunnels
  `/ws`; Node WebSocket smoke proved `/ws/app-updates` opens, and headed
  Playwright login plus Admin Sales Report navigation finished with console
  0 errors and no `/api/app-logs` 400 after fixing Sales Report realtime close
  code and the client app-log upload payload. The same pass fixed the missing
  Web viewport meta/reset that made `flutter-view` render 2160px wide inside a
  1440px Chrome viewport; final smoke measured `flutterViewWidth=1440` and
  `bodyScrollWidth=1440`, with `/admin/sales-reports` selected under `Báo cáo`
  rather than `Quản trị`. A Go realtime follow-up added route-level proof that
  a public `/ws/app-updates` WebSocket client ignores non-update broadcasts and
  receives `APP_UPDATE` from the hub (`go test ./...` in `backend-go/`).
  Live staging smoke then published `APP_VERSION_UPDATED` through staging Redis:
  a raw public WebSocket client received `APP_UPDATE` with `web.latestBuild=200083`,
  and Chrome CDP confirmed the deployed Flutter web login page opened
  `/ws/app-updates`, received the smoke frame, and re-read
  `/api/app-version?platform=web` with console/runtime errors at 0. The live
  payload reused current metadata, so visible forced-prompt rendering remains
  covered by widget/local update-gate tests rather than a staff-disrupting
  staging force update. Admin Feature Management route
  gap was closed by exposing `/admin/features` in the Admin workspace with
  `ADMIN_FEATURES` route/menu guard proof. Follow-up validation:
  `flutter test --no-pub --reporter expanded test\app_router_test.dart
  test\admin_menu_screen_test.dart test\app_nav_model_test.dart` (6 tests),
  `dart format --output=none --set-exit-if-changed` on changed Dart files,
  `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded`
  (240 tests), and `git diff --check`. Route-gap decision follow-up opens
  Generic Report Workspace as `/reports`, exposes Personnel Catalog Admin as
  `/admin/personnel` behind `ADMIN_PERSONNEL`, and retires Data Workspace plus
  FIFO Conversation Check from the current plan. Figma sync follow-up added
  desktop/tablet/mobile runtime frames for `/reports` (`501:2`, `501:49`,
  `501:91`) and `/admin/personnel` (`502:2`, `502:67`, `502:127`); Figma QA
  confirmed required text missing `[]`, empty text `[]`, zero-size text `[]`,
  font mismatch `[]`, and no Personnel status/action overlap after the edit
  action was tightened to an icon glyph. Personnel focused proof then locked
  the `/admin/personnel` screen itself: content-only rendering, department/job
  role tabs, non-scrollable loading skeleton inside the responsive scroll view,
  and retryable shared error state all pass without layout exceptions. The
  follow-up data-heavy
  migration keeps the same `/admin/features` runtime contract but removes the
  nested feature `GradientHeader`; the screen now renders content-only under `AppShell`, with a
  shared surface header/action row and shared tab surface before the existing
  feature/node/rule lists. Validation rerun: `dart format
  --output=none --set-exit-if-changed`, focused route/menu/nav tests,
  `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded`
  (240 tests), `flutter build windows --debug --dart-define=APP_ENV=smoke
  --no-pub`, Windows debug runtime smoke opening Admin > `Quản lý tính năng`,
  and `git diff --check`. Runtime log proof in
  `%APPDATA%\com.example\OpsHub\logs\opshub.log` shows `/admin/features`
  shell navigation plus `Feature management load started/succeeded`. Sales
  Report hub `/sales-reports` was then migrated from a nested
  `GradientHeader` screen to content-only `AppShell` rendering; its cockpit
  keeps the same provider/API contract and adds a shared surface intro above
  the existing filter/action card and reported/unreported order columns.
  Validation rerun: `dart format --output=none --set-exit-if-changed`,
  `flutter test --no-pub --reporter expanded test\sales_report_hub_test.dart`
  (16 tests), `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter expanded` (240 tests),
  `flutter build windows --debug --dart-define=APP_ENV=smoke --no-pub`,
  Windows debug runtime smoke opening Home > `Báo cáo`, and `git diff --check`.
  Runtime log proof shows `/sales-reports` shell navigation plus
  `Sales report order cockpit load started/succeeded`.
- `UI-UX-001`/`HOME-REDESIGN`, 2026-07-03: restored the current Figma Home
  Workspace evidence for the already-migrated content-only Home route. The
  Figma file now has `Desktop v2 / Home Workspace` (`485:2`),
  `Tablet v2 / Home Workspace` (`485:86`), and
  `Mobile v2 / Home Workspace` (`485:160`) matching the runtime Home contract:
  command card, shell topbar/mobile app bar, 9-action high-permission Home
  state without standalone `Sắp xếp`, feedback last, and a limited staff
  mobile state with bottom nav `Trang chủ`/`Tác vụ`/`Tài khoản`. Figma QA
  confirmed required missing `[]`, zero-size text `0`, missing font `0`,
  out-of-parent `[]`, and screenshots were checked after fixing desktop/tablet
  account text overlap. Runtime validation for this docs/Figma slice:
  `flutter test --no-pub --reporter expanded
  test\home_feedback_action_test.dart test\home_avatar_test.dart
  test\design_system_migration_guard_test.dart test\app_router_test.dart
  test\app_nav_model_test.dart` (20 tests), `flutter analyze --no-pub`,
  `flutter build web --no-pub`, and `git diff --check`. Empty-state follow-up:
  Home now renders shared `AppStatePanel.empty` inside `home-empty-state` when
  the current account has no workspace action, with widget proof that no
  `AppFeatureTile` leaks into that state. Figma empty-state frames are desktop
  `487:2`, tablet `487:91`, and mobile `487:170`; Figma QA confirmed required
  missing `[]`, zero-size text `0`, missing font `0`, out-of-parent `[]`, and
  the fixed mobile screenshot has no collapsed copy.
- `UI-UX-001`/`VIETQR-001`, 2026-07-02: `/vietqr` now renders as a
  content-only workspace under `AppShell` instead of nesting a
  `Scaffold`/`GradientHeader`. The runtime header shows selected SR, QR state,
  and history count while preserving SR scope selection, order scan, QR
  creation, MAP confirmation, realtime payment matching, non-expired history
  reopen, 15-minute expiry, and QR image save. Figma was synced for
  `Desktop v2 / VietQR Workspace` (`398:14`),
  `Tablet v2 / VietQR Workspace` (`135:558`), and
  `Mobile v2 / VietQR Workspace` (`135:142`). Focused widget proof is covered
  by `test\vietqr_screen_test.dart`; physical camera scanning remains a manual
  device/browser acceptance item.
- `SALES-REPORT-001`/`UI-UX-001`, 2026-07-02: Sales Report form/admin polish
  now removes the remaining Sales Report `GradientHeader` shells, adds
  content header cards to the purchased/not-purchased forms, changes the admin
  report-type selector from checkbox tiles to the shared dropdown filter, and
  groups HVTC/revenue/installment exports behind one `Xuất file` menu in both
  hub and admin list. The Figma file `OpsHub Redesign System - 2026-06-30` was
  updated in the desktop/tablet/mobile Sales Report hub/admin/form frames to
  show the compact filter/action toolbar and export-menu options. Hub/admin
  frame ids are desktop `152:3577`/`152:2179`, tablet
  `152:938`/`152:470`, and mobile `151:698`/`151:350`. Validation:
  `dart format --output=none --set-exit-if-changed` on changed Dart/test files,
  focused
  `flutter test --no-pub --reporter expanded test\sales_report_hub_test.dart`
  (16 tests), focused design-system guard (2 tests), `flutter analyze --no-pub`,
  full `flutter test --no-pub --reporter expanded` (240 tests), and
  `flutter build windows --debug --dart-define=APP_ENV=smoke --no-pub`.
- `UI-UX-001`/`ADMIN-USERS`, 2026-07-02: `/admin/users` now renders as a
  content-only workspace under `AppShell` instead of nesting a
  `GradientHeader`. The screen uses shared header/filter cards, compact
  searchable dropdown filters, responsive account rows, and preserves the
  existing Super Admin import/create plus admin reset/edit/delete contract.
  `AuthRepository` can be injected only for widget proof; production still
  constructs the same repository and API client. Figma desktop/mobile Admin
  Users frames were updated to remove unsupported detail/export surfaces and
  show the runtime header, search, five filters, reset action, and account-row
  actions. Focused validation: `flutter test --no-pub --reporter expanded
  test\user_admin_redesign_test.dart` (2 tests); combined focused User Admin +
  design-system guard (4 tests); `flutter analyze --no-pub`; full
  `flutter test --no-pub --reporter expanded` (242 tests); and
  `flutter build windows --debug --dart-define=APP_ENV=smoke --no-pub`. Figma
  visual QA confirmed no remaining placeholders or zero-size text in either
  frame.
- `UI-UX-001`/`ADMIN-MENU`, 2026-07-02: `/admin` now renders as a
  content-only admin hub under `AppShell` instead of nesting a
  `GradientHeader`. The hub uses a shared header card, `AppFeatureSection`/
  `AppFeatureGrid`, and a shared empty state while preserving the runtime
  feature-access menu contract for `ADMIN_USERS`, `ADMIN_ROLES`,
  `ADMIN_ORG_TREE`, `ADMIN_POLICIES`, `ADMIN_FEATURES`, plus the Super
  Admin-only feedback list action. Focused validation after the slice:
  `flutter test --no-pub --reporter expanded test\admin_menu_screen_test.dart
  test\design_system_migration_guard_test.dart test\app_router_test.dart
  test\app_nav_model_test.dart` (9 tests), `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter compact` (272 tests), and
  `flutter build web --no-pub`. Figma Admin
  Workspace frames `102:2`, `135:714`, and `135:258` were synced to remove
  unsupported metrics, tables, permission matrix, audit log, add-user CTA, and
  Sales Report action, with visual QA confirming the six runtime admin actions
  and no stale mock copy in all three frames.
- `UI-UX-001`/`SETTINGS-001`, 2026-07-02: `/settings` now renders as a
  content-only workspace under `AppShell` instead of nesting a
  `GradientHeader`. It uses a shared header card, responsive theme/startup
  cards, preserves the `ThemeProvider` segmented-control contract, preserves
  the Windows startup `StartupSettingsService` contract, and adds screen-level
  `AppLogger` proof around open/load/toggle success and failure. Focused
  validation:
  `flutter test --no-pub --reporter expanded
  test\settings_screen_redesign_test.dart test\design_system_migration_guard_test.dart
  test\app_router_test.dart test\app_nav_model_test.dart` (9 tests),
  `flutter analyze --no-pub`, full `flutter test --no-pub --reporter compact`
  (274 tests), and `flutter build web --no-pub`. Figma Settings Workspace
  frames `106:105`, `135:870`, and `135:374` were synced to remove unsupported
  search/save, ERP endpoint, bank webhook, SSO, security, and audit mock
  controls, with visual QA confirming runtime theme + Windows startup content
  and zero-size text count `0`.
- `UI-UX-001`/`PROFILE-ADMIN-001`, 2026-07-02: `/profile` now renders as a
  content-only workspace under `AppShell` instead of nesting a
  `Scaffold`/`GradientHeader`. It uses shared header/edit/info cards, preserves
  avatar update, change-password, profile-name save, organization-node and
  assigned-SR display, keeps legacy personnel fields hidden, and has a visible
  `Phiên đăng nhập` card directly under the header with a `Đăng xuất` action
  that calls `AuthProvider.logout()` before routing back to `/login`. The
  changed flow logs screen open, save, password change, and logout
  success/failure through `AppLogger`. Focused validation for the latest
  session-card follow-up:
  `dart format --output=none --set-exit-if-changed` on changed Dart/test files,
  `flutter test --no-pub --reporter expanded
  test\profile_screen_test.dart test\design_system_migration_guard_test.dart
  test\app_router_test.dart test\app_nav_model_test.dart` (9 tests),
  `flutter analyze --no-pub`, and `git diff --check`. The earlier Profile
  migration batch also passed full `flutter test --no-pub --reporter compact`
  (274 tests) and `flutter build web --no-pub`. Figma Profile frames
  `481:2`, `481:52`, and `481:99` were synced to remove unsupported `Họ tên`,
  `Phạm vi`, `Toàn hệ thống`, and `Lưu thay đổi` mock copy, with text/structure
  QA confirming the runtime header/session/edit/info/logout content, zero-size
  text count `0`, missing font count `0`, and a mobile screenshot where the
  session-card logout button is visible without overlap.
- `UI-UX-001`/`TASKS-INDEX`, 2026-07-03: `/tasks` now renders as a
  content-only workspace index under `AppShell` instead of nesting a
  `Scaffold`/`GradientHeader`. It uses a shared header card, permission-aware
  available/hidden chips, `AppFeatureSection` actions, shared empty state, and
  the same `AppNavModel.visibleTaskDestinations(user)` contract as Home/sidebar
  while logging visible/hidden counts through `AppLogger`. Focused validation:
  `flutter test --no-pub --reporter expanded test\tasks_screen_redesign_test.dart`
  (2 tests), focused Tasks + migration guard/router/nav
  `flutter test --no-pub --reporter expanded
  test\tasks_screen_redesign_test.dart test\design_system_migration_guard_test.dart
  test\app_router_test.dart test\app_nav_model_test.dart` (10 tests),
  `flutter analyze --no-pub`, full `flutter test --no-pub --reporter compact`
  (280 tests), `flutter build web --no-pub`, and `git diff --check`. Figma
  Tasks Workspace frames `482:2`, `482:75`, and `482:145` were created to show
  the full super-admin desktop/tablet state and limited staff mobile state,
  with text/structure QA confirming required missing `[]`, zero-size text `0`,
  missing font `0`, and the final mobile screenshot showing no hidden-chip
  overflow.
- `UI-UX-001`/`AUTH-002`, 2026-07-02: auth pre-shell routes `/login`,
  `/register`, `/forgot-password`, and `/assignment-pending` now render through
  shared `AuthScreenShell`/`AuthCard` surfaces instead of the legacy
  `GradientHeader.getGradient` background. The slice preserves login routing,
  missing-account registration handoff, registration email verification code,
  forgot-password email/code/new-password steps, assignment-pending refresh,
  and logout. Focused validation:
  `flutter test --no-pub --reporter expanded
  test\auth_pre_shell_redesign_test.dart test\widget_test.dart
  test\forgot_password_screen_test.dart test\design_system_migration_guard_test.dart`
  (6 tests), `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter compact` (275 tests), and
  `flutter build web --no-pub`. Figma auth frames were synced for Login
  `106:2`/`135:316`/`135:792`, Register `152:1161`/`151:31`/`152:41`,
  Forgot Password `152:1189`/`151:60`/`152:80`, and Assignment Pending
  `152:1217`/`151:89`/`152:119`; text/structure QA confirmed runtime copy,
  zero-size text count `0`, and no unsupported SSO/2FA or simplified
  register-copy mock remains.
- `UI-UX-001`/`ADMIN-ROLES`, 2026-07-02: `/admin/roles` now renders as a
  content-only workspace under `AppShell` instead of nesting a
  `GradientHeader`. The read-only role catalog uses shared header/state/list
  surfaces, logs load start/success/failure through `AppLogger`, exposes an
  injected repository only for widget proof, keeps the production
  `/admin/roles` repository contract, and maps missing role descriptions to
  Vietnamese user-facing copy instead of showing technical role codes. Figma
  desktop/mobile Admin Roles frames were updated to remove unsupported
  search/filter/export/detail surfaces and show the runtime header, refresh
  action, role-count/read-only chips, and role cards. Focused validation:
  `dart format --output=none --set-exit-if-changed` on the changed Dart/test
  files, `flutter test --no-pub --reporter expanded
  test\role_admin_redesign_test.dart test\design_system_migration_guard_test.dart`
  (4 tests), `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter expanded` (246 tests),
  `flutter build windows --debug --dart-define=APP_ENV=smoke --no-pub`, and
  Figma visual QA confirmed no placeholders, zero-size text, or unsupported
  runtime copy in either frame.
- `UI-UX-001`/`ADMIN-ORG-TREE`, 2026-07-02: `/admin/organization` now renders
  as a content-only workspace under `AppShell` instead of nesting a
  `GradientHeader`. The organization tree keeps the existing
  `/admin/org-tree` repository/API contract and node create/edit/delete/feature
  assignment flows, adds shared header cards, shared tree/detail surfaces,
  retryable error state, permission chips for structure and node-feature
  management, and a quick search inside the tree panel that matches business
  code, abbreviation, or node title, including accent-insensitive title input.
  `AuthRepository` can be injected only for widget proof; production still
  constructs the same repository and API client. Figma Organization Tree
  frames `152:1741`, `152:314`, and `151:234` were updated to remove
  unsupported filter/export/tab surfaces and show the runtime header,
  refresh/add actions, tree search, tree panel, and detail panel. Focused
  validation:
  `flutter test --no-pub --reporter expanded
  test\organization_tree_admin_redesign_test.dart test\admin_user_tree_scope_test.dart`
  (15 tests), `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter expanded` (246 tests),
  `flutter build windows --debug --dart-define=APP_ENV=smoke --no-pub`, and
  Figma visual QA confirmed no placeholders, zero-size text, or unsupported
  runtime copy in all three frames. Follow-up search proof:
  `flutter test --no-pub --reporter expanded
  test\organization_tree_admin_redesign_test.dart test\admin_user_tree_scope_test.dart`
  (15 tests), with `AppLogger` search applied/cleared logs carrying query
  length and result counts. The merged screen also keeps a persistent retry
  action after load failure. Follow-up broad validation also passed
  `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded`
  (249 tests), `flutter build windows --debug --dart-define=APP_ENV=smoke
  --no-pub`, and `git diff --check` with CRLF warnings only. 2026-07-03
  no-results follow-up: the detail panel now uses shared `AppStatePanel.empty`
  with key `organization-tree-detail-empty-state` while the query has no
  matching node, then returns to node detail when the query is cleared. Figma
  variants `494:11`, `494:151`, and `494:271` cover desktop/tablet/mobile tree
  and detail empty states. Figma QA found no missing required copy, zero-size
  text, out-of-parent state content, missing font, placeholder, or stale
  selected-node detail; the mobile screenshot was rechecked after moving the
  detail card above bottom navigation. The final copy pass removes the repeated
  no-result guidance, shortens the header to `Quản lý cây tổ chức và quyền theo
  node.`, shortens detail guidance to `Chọn node để xem chi tiết.`, and keeps
  the mobile status chip clear of header actions in both selected/no-results
  Figma states. Validation: focused Organization Tree + admin scope +
  design-system guard (18 tests), `flutter analyze --no-pub`,
  `flutter build web --no-pub` with successful wasm dry-run, and
  `git diff --check`.
- `UI-UX-001`/`STATE-INVENTORY`, 2026-07-03: audited all exposed feature
  loading/empty/error states and raw progress indicators. Full states remain on
  shared `AppStatePanel`; all feature dialog actions remain covered by the raw
  button design-system guard. The remaining progress indicators are reviewed
  inline contexts only: submit/log actions, image loaders, refresh bars,
  load-more, metric chips, and payment-waiting status. Their file/count and
  rationale are locked in `design_system_migration_guard_test.dart`, together
  with the single screen-level `Center` fallback used for the payment list when
  available height is below 130px. Validation: focused migration guard
  (5 tests), `flutter analyze --no-pub`, and `git diff --check`. No Figma frame
  changed because this slice only records and locks the already-rendered state
  inventory.
- `UI-UX-001`/`ADMIN-POLICIES`, 2026-07-02: `/admin/policies` now renders as a
  content-only workspace under `AppShell` instead of nesting a
  `GradientHeader`. It keeps the existing policy/rule/settings repository/API
  contract, adds shared header/tabs/list cards, retryable load error state,
  and focused widget injection only for proof. Production still constructs the
  same repository and API client. Focused validation:
  `flutter test --no-pub --reporter expanded
  test\organization_tree_admin_redesign_test.dart test\policy_admin_redesign_test.dart`
  (5 tests). Follow-up broad validation also passed `flutter analyze --no-pub`,
  full `flutter test --no-pub --reporter expanded` (249 tests),
  `flutter build windows --debug --dart-define=APP_ENV=smoke --no-pub`, and
  `git diff --check` with CRLF warnings only. Figma Policy Management
  desktop/tablet/mobile frames were synced to the runtime header/tabs/cards,
  with visual QA confirming no unsupported search/filter/export controls or raw
  policy codes such as `ADMIN_USERS`, `BANK_STATEMENT`, or `SALES_REPORT`.
- `UI-UX-001`, 2026-07-02: consolidated the pre-barcode redesign checkpoint
  with the later VietQR, Sales Report, and Organization Tree work on
  `staging`, while keeping the barcode/mobile-web scanner experiment outside
  the working tree. Validation passed changed-file formatting (42 Dart files),
  `flutter analyze --no-pub`, 69 focused tests across 18 changed test files,
  full `flutter test --no-pub --reporter compact` (262 tests), and
  `flutter build web --no-pub` with a successful wasm dry-run.
- `UI-UX-001`/`FEEDBACK-001`/`ADMIN-FEEDBACK`, 2026-07-02: `/admin/feedback`
  now renders as a content-only workspace under `AppShell` instead of nesting a
  `GradientHeader`. It keeps the existing `/feedback/admin` API contract,
  still relies on the backend/Super Admin visibility contract, adds shared
  metric header, refresh action, retryable load error state, AppLogger
  start/success/failure logs, and feedback cards with sender, content, module,
  rating, timestamp, email, image counts, and inline image thumbnails. The
  loader can be injected only for widget proof; production still constructs the
  same API client. Focused validation:
  `flutter test --no-pub test\feedback_admin_redesign_test.dart --reporter
  expanded` (2 tests). Follow-up broad validation also passed
  `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter expanded` (251 tests), and
  `flutter build windows --debug --dart-define=APP_ENV=smoke --no-pub`. Figma
  Admin Feedback List desktop/tablet/mobile frames were synced to remove
  unsupported search/filter/export/add/status controls and visual QA confirmed
  no clipped feedback body text after metric-chip layout repair.
- `UI-UX-001`/`FEEDBACK-001`, 2026-07-02: `/feedback` now renders as a
  content-only staff suggestion form under `AppShell` instead of nesting a
  `Scaffold`/`GradientHeader`. It keeps the existing feedback multipart submit
  contract, `FEEDBACK` route guard, 120-character function field,
  5000-character description field, and 20-image attachment limit while adding
  a shared runtime header, form card, attachment card, and submit action.
  Focused validation passed `flutter test --no-pub --reporter expanded
  test\feedback_screen_test.dart` (1 test). Figma Staff Feedback Workspace
  desktop/tablet/mobile frames `106:30`, `135:831`, and `135:345` were synced
  to remove stale inbox/detail/ticket admin mock surfaces and visual QA
  confirmed required runtime copy with no visible `FEEDBACK` code.
- `UI-UX-001`/`FIFO-001`/`INVENTORY-IMPORT`, 2026-07-02:
  `/fifo/inventory-import` now renders as a content-only workspace under
  `AppShell` instead of nesting a `GradientHeader`. It keeps the existing
  `/fifo/inventory/import` API contract, `FIFO_IMPORT` guard, and
  `/admin/inventory-import` backward-compatible alias, adds shared runtime
  header/upload/result/error surfaces, AppLogger picker/upload
  start/success/failure/cancel/blocked logs, and retryable upload errors. File
  picker and uploader can be injected only for widget proof; production still
  uses `FilePicker.pickFiles` and `InventoryImportRepository(ApiClient())`.
  Focused validation:
  `flutter test --no-pub test\inventory_import_redesign_test.dart --reporter
  expanded` (2 tests), and combined Inventory Import + Admin Feedback focused
  validation passed 4 tests. Follow-up broad validation also passed
  `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter expanded` (253 tests), and
  `flutter build windows --debug --dart-define=APP_ENV=smoke --no-pub`. Figma
  Inventory Import desktop/tablet/mobile frames were synced to remove
  unsupported history/search/filter/export/add controls, with visual QA
  confirming no zero-size text and the desktop/tablet shell active state now
  belongs to the FIFO workspace.
- `UI-UX-001`/`FIFO-001`, 2026-07-02: `/fifo-menu` now renders as a
  content-only FIFO hub under `AppShell`. It keeps the existing feature-gated
  navigation to `/fifo-check`, `/sort`, `/fifo/inventory-import`, and
  `/fifo-history`, while adding a shared runtime header with visible/hidden
  action chips, `AppFeatureSection` action grid, shared empty state, and
  `AppLogger` proof for hub resolution plus action open decisions. Focused
  validation passed `flutter test --no-pub --reporter expanded
  test\fifo_menu_redesign_test.dart` (2 tests), combined FIFO Menu + migration
  guard/router/nav validation passed 10 tests, `flutter analyze --no-pub`
  passed, full `flutter test --no-pub --reporter compact` passed 278 tests, and
  `flutter build web --no-pub` passed. Figma FIFO Menu desktop, tablet, and
  mobile frames (`476:2`, `476:48`, `476:92`) were created from the runtime
  action contract, with QA confirming required text missing `[]`, zero-size
  text `0`, and a follow-up mobile screenshot after fixing collapsed card
  heights/chip overlap.
- `UI-UX-001`/`FIFO-001`/`SORT-FIFO`, 2026-07-02: `/sort` now renders as a
  content-only workspace under `AppShell` instead of nesting a
  `GradientHeader`. It keeps the existing `SortProvider`/`SortRepository`,
  scanner route, FIFO route guard, and completion report contract, while adding
  a shared runtime header, SKU/BIN command card, loading/empty/error states, and
  result list surface. Focused validation passed in the combined Sort FIFO +
  Inventory Import + Admin Feedback batch:
  `flutter test --no-pub test\sort_screen_redesign_test.dart
  test\inventory_import_redesign_test.dart test\feedback_admin_redesign_test.dart
  --reporter expanded` (6 tests). Follow-up broad validation also passed
  `dart format --output=none --set-exit-if-changed`, `flutter analyze
  --no-pub`, full `flutter test --no-pub --reporter expanded` (255 tests), and
  `flutter build windows --debug --dart-define=APP_ENV=smoke --no-pub`. Figma
  Sort Workspace desktop/tablet/mobile frames were synced to remove the stale
  empty mock and unsupported fake controls, with visual QA confirming no
  zero-size text and required runtime values `250403171`, `SN001`, and
  `LK.04-A-03-a` in all three frames.
- `UI-UX-001`/`FIFO-001`/`FIFO-CHECK`, 2026-07-02: `/fifo-check` now renders
  as a content-only workspace under `AppShell` instead of nesting a
  `GradientHeader`. It keeps the existing `FifoProvider`/`FifoRepository`,
  scanner route, FIFO route guard, include-exported toggle, and
  export/unexport contract, while adding a shared runtime header, SKU/serial
  command card, loading/empty/error states, and serial/SKU result surface.
  Focused validation passed:
  `flutter test --no-pub test\fifo_check_redesign_test.dart --reporter
  expanded` (2 tests). Figma FIFO Check desktop/tablet/mobile frames were
  synced to remove stale SKU/BIN/copy mock controls, with visual QA confirming
  no overlap, no zero-size text, no unsupported copy such as `SKU hoặc BIN` or
  `Hiển thị đề xuất kho`, and required runtime values `250403171`, `SN001`,
  `LK.04-A-03-a`, `A1`, `2026-07-01`, and `Đúng FIFO. Lấy sản phẩm này.` in
  all three frames. Follow-up broad validation also passed `dart format
  --output=none --set-exit-if-changed`, `flutter analyze --no-pub`, focused
  FIFO Check + Sort FIFO + Inventory Import + Admin Feedback
  `flutter test --no-pub test\fifo_check_redesign_test.dart
  test\sort_screen_redesign_test.dart test\inventory_import_redesign_test.dart
  test\feedback_admin_redesign_test.dart --reporter expanded` (8 tests), full
  `flutter test --no-pub --reporter expanded` (257 tests),
  `flutter build windows --debug --dart-define=APP_ENV=smoke --no-pub`, and
  `git diff --check` with CRLF warnings only.
- `UI-UX-001`/`FIFO-001`/`FIFO-HISTORY`, 2026-07-02: `/fifo-history` now
  renders as a content-only workspace under `AppShell` instead of nesting a
  `GradientHeader`. It keeps the existing admin log runtime contract through
  `FifoLogRepository.getAdminLogs`, `FIFO_CHECK`/`FIFO_SORT`, search, user
  filter, pagination/load-more, expand item behavior, and adds `AppLogger`
  start/success/failure logs for the changed history flow. Focused validation
  passed `flutter test --no-pub --reporter expanded
  test\fifo_history_redesign_test.dart test\app_router_test.dart
  test\app_nav_model_test.dart` (8 tests), including desktop runtime
  filters/tabs, mobile loaded-state, and mobile retry after load failure.
  Figma FIFO History desktop/tablet/mobile frames (`152:2601`, `152:587`,
  `151:437`) were synced to remove stale add/mock/SKU copy and unsupported
  controls, with visual QA confirming no placeholder, no zero/blank text, no
  stale copy such as `Thêm mới`, `SKU check`, `Quét SKU`, `Query`, or `items`,
  and no clipped overflow. Parity note: the Figma file uses the current
  design-system `Inter` text styles while runtime Flutter remains on
  `SF Pro Display`. Follow-up broad validation also passed `dart format
  --output=none --set-exit-if-changed`, `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter compact` (265 tests), and
  `flutter build web --no-pub`.
- `UI-UX-001`/`PAYMENT-STATEMENT-001`, 2026-07-02: `/bank-statement` now
  renders as a content-only workspace under `AppShell` instead of nesting a
  `GradientHeader`. It keeps the existing `BankStatementProvider`,
  `BankStatementRepository`, scoped SR/default-date search, global statement
  number/order code/exact amount/transfer-content lookup, export, pagination,
  inline order correction/history, ACC review transfer notifications, and
  AppLogger runtime contract, while adding a shared statement header, compact
  runtime chips, toolbar surface, and responsive transaction list. Focused
  validation passed:
  `flutter test --no-pub test\bank_statement_screen_test.dart --reporter
  expanded` (3 tests). Figma Statement Workspace desktop/tablet/mobile frames
  were synced to the runtime layout, including a newly added desktop frame and
  visual QA confirming no stale `Sắp xếp FIFO` title, no overflowing filters,
  and no overlapping transaction metadata. Follow-up broad validation also
  passed `dart format --output=none --set-exit-if-changed`,
  `flutter analyze --no-pub`, focused Sao kê screen/provider/detail
  `flutter test --no-pub test\bank_statement_screen_test.dart
  test\bank_statement_provider_test.dart
  test\bank_statement_transaction_details_test.dart --reporter expanded` (27
  tests), full `flutter test --no-pub --reporter expanded` (258 tests), and
  `flutter build windows --debug --dart-define=APP_ENV=smoke --no-pub`.
- `UI-UX-001`/`PAYMENT-MONITOR-001`, 2026-07-02: `/payment-monitor` now
  renders as a content-only workspace under `AppShell` instead of nesting a
  `GradientHeader`. It keeps the existing `PaymentMonitorProvider`,
  `PaymentMonitorRepository`, realtime refresh, payment speaker/list-only
  platform gating, selected-store scope, date/page filters, transaction rows,
  order edit, transfer request/review, and history callbacks, while adding a
  shared runtime header with SR/sync/speaker/transaction chips above the
  existing speaker and transaction surfaces. Focused validation passed:
  `flutter test --no-pub test\payment_monitor_screen_redesign_test.dart
  --reporter expanded` (1 test). Figma Payment Monitor desktop/tablet/mobile
  frames were synced to remove fake metrics/timeline/actions and show the
  runtime header, speaker/list-only panel, filters, transaction row, and active
  `Tiền vào` nav/rail with visual QA confirming no overlap or stale controls.
  Follow-up broad validation also passed `dart format
  --output=none --set-exit-if-changed`, `flutter analyze --no-pub`, focused
  route + Payment Monitor regression `flutter test --no-pub
  test\app_router_test.dart test\payment_monitor_screen_redesign_test.dart
  test\payment_monitor_provider_test.dart test\payment_transaction_tile_test.dart
  test\payment_monitor_unsupported_screen_test.dart --reporter expanded` (34
  tests), full `flutter test --no-pub --reporter expanded` (259 tests), and
  `flutter build windows --debug --dart-define=APP_ENV=smoke --no-pub`.
- `UI-UX-001`/`PAYMENT-MONITOR-001`, 2026-07-02: `/payment-monitor`
  unsupported fallback now renders as content-only shell content instead of
  nesting a `Scaffold`/`GradientHeader`, while preserving
  `AppPlatformCapabilities` route fallback behavior, the `AppLogger` warning
  with platform/isWeb context, and the `/home` recovery action. The fallback
  now uses the shared header/state-card pattern with device and `Chưa hỗ trợ
  loa` chips, plus Vietnamese action-oriented copy for web/unsupported
  devices. Figma unsupported frames `152:3479`, `152:899`, and `151:669` were
  synced to remove fake transaction/speaker/history/manual-link actions; visual
  QA confirmed required runtime copy present, forbidden old mock text absent,
  and zero-size text count `0`. Validation passed focused
  `flutter test --no-pub --reporter expanded
  test\payment_monitor_unsupported_screen_test.dart
  test\design_system_migration_guard_test.dart` (3 tests), focused route +
  Payment Monitor regression `flutter test --no-pub --reporter expanded
  test\app_router_test.dart test\payment_monitor_screen_redesign_test.dart
  test\payment_monitor_provider_test.dart test\payment_transaction_tile_test.dart
  test\payment_monitor_unsupported_screen_test.dart` (34 tests),
  `flutter analyze --no-pub`, full `flutter test --no-pub --reporter compact`
  (275 tests), and `flutter build web --no-pub`.
- `UI-UX-001`, 2026-07-03: retired the legacy
  `lib/app/widgets/gradient_header.dart` artifact after the AppShell migration.
  The route migration guard now scans production `lib/` for any recreated
  `GradientHeader` file/import/constructor instead of only checking exposed
  feature screens, blocks nested feature `Scaffold` shells outside public auth
  and scanner modal, and limits ad-hoc `MaterialPageRoute` usage to the reviewed
  scanner/image-viewer modals. The guard keeps the retired
  `FifoCheckConversationScreen` out of `app_router.dart`, while
  `PersonnelCatalogAdminScreen` is now an approved runtime route at
  `/admin/personnel` guarded by `ADMIN_PERSONNEL`.
  Validation passed `dart format`, focused
  `flutter test --no-pub --reporter expanded
  test\design_system_migration_guard_test.dart` (12 tests),
  `flutter analyze --no-pub`, full `flutter test --no-pub --reporter compact`
  (316 tests), and `git diff --check`.
- `UI-UX-001`/`OFFSET-ADJUSTMENT-001`, 2026-07-02:
  `/offset-adjustments` now renders as a content-only workspace under
  `AppShell` instead of nesting a `GradientHeader`. It keeps the existing
  `OffsetAdjustmentProvider`, `OffsetAdjustmentRepository`, all-store reviewer
  query, create/edit dialogs, detail/review actions, export menu, realtime
  notification, and `OFFSET_ADJUSTMENTS` route guard while adding a shared
  header, compact action/filter/toolbar surfaces, and mobile collapsed filters.
  Figma Offset Workspace frames `107:100`, `135:948`, and `135:432` were
  synced to remove unsupported kanban/drawer/CTA/search/empty mocks and show
  the runtime header/action/filter/toolbar/result-card state. Focused
  validation passed `flutter test --no-pub --reporter expanded
  test\offset_adjustment_screen_redesign_test.dart` (2 tests), and Figma QA
  confirmed no stale `OFF-*` mock copy, zero-size text, or out-of-bounds nodes.
  Follow-up broad validation also passed `dart format
  --output=none --set-exit-if-changed`, `flutter analyze --no-pub`, focused
  Offset/route/nav regression `flutter test --no-pub --reporter expanded
  test\offset_adjustment_screen_redesign_test.dart
  test\offset_adjustment_provider_test.dart test\app_router_test.dart
  test\app_nav_model_test.dart` (13 tests), full `flutter test --no-pub
  --reporter compact` (267 tests), `flutter build web --no-pub`, and
  `git diff --check` with CRLF warnings only.
- `UI-UX-001`/`WARRANTY-001`, 2026-07-02: BH/SC hub `/warranty-main` and
  upload form `/warranty` now render as content-only screens under `AppShell`
  instead of nesting `Scaffold`/`GradientHeader`. The hub uses the shared
  header card plus `AppFeatureSection` for `Lưu hình ảnh` and `Xem lại hình
  ảnh`; the upload form uses a header card with receipt/image-count chips and
  a shared form card while preserving `WarrantyProvider`, `WarrantyRepository`,
  scanner route, image picker, upload API, and `WARRANTY` route guard behavior.
  Figma was synced for BH/SC hub frames `101:2`, `135:675`, `135:229` and
  Warranty Intake frames `152:2943`, `152:704`, `151:524`; visual QA confirmed
  no stale mock copy, zero-size text, or wrapped chips after screenshot fixes.
  Follow-up lookup/detail migration moves `/check-warranty` to content-only
  search/list surfaces and removes `GradientHeader` from receipt detail/image
  viewer while preserving `WarrantyProvider.showAllWarranty`, search,
  barcode scanner, base64/remote image rendering, zoom/pan viewer and download
  behavior. Follow-up route hardening promotes receipt detail to ShellRoute
  `/check-warranty/details/:receiptNumber`, keeps it guarded by `WARRANTY`,
  keeps BH/SC nav selected, and removes the remaining local `Scaffold` from
  detail and image viewer surfaces. Figma was also synced for Warranty Lookup frames `152:3051`,
  `152:743`, `151:553` and Warranty Detail frames `152:3159`, `152:782`,
  `151:582`; visual QA confirmed no stale mock copy (`26 kết quả`, `CP75`,
  `4 ảnh`, `Tải thêm hình ảnh`), no text overlap and no auto-stacked desktop
  detail columns. Focused validation passed `flutter test --no-pub --reporter
  expanded test\warranty_redesign_test.dart` (4 tests), focused BH/SC +
  route/nav/upload regression (22 tests), `dart format
  --output=none --set-exit-if-changed`, `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter compact` (271 tests), and
  `flutter build web --no-pub`. Gap: physical camera upload and WebSocket
  status smoke remain follow-up work.
- `WARRANTY-001`, 2026-07-03: BH/SC multi-image upload keeps original files
  without compression, rejects unreadable/over-10MiB images before sending, and
  scales the multipart timeout from 60s up to 8 minutes based on total selected
  bytes. Upload controller/service tests now lock multi-file `images` handling,
  same-receipt file writes, and semicolon-joined links.
- `UI-UX-001`, 2026-07-03: Figma mobile shell parity follow-up audited the
  live `OpsHub Redesign System - 2026-06-30` file and fixed active mobile
  shell frames so they match the runtime `AppShell` viewport: `Mobile v2 /
  FIFO Menu` now has bottom nav active on `Tác vụ`, `Mobile v2 / Profile` has
  bottom nav active on `Tài khoản`, and `Mobile v2 / Tasks Workspace` clips
  its content frame. Figma QA confirmed all active mobile frames have content
  y=`72`, height=`696`, bottom nav y=`768`, height=`76`; Profile/FIFO
  screenshots render at 390x844 after the fix. Follow-up screen-page inventory
  QA confirmed the cover page is only a curated subset; the handoff pages
  `05 Mobile Screens`, `06 Tablet Screens`, and `07 Desktop Screens` retain the
  runtime inventory. Mobile/tablet each expose 40 active runtime frames plus 2
  hidden retired frames; desktop now exposes 40 unique active runtime groups
  after archiving superseded duplicate desktop VietQR (`96:2`) and Sao kê
  (`107:2`) frames as hidden `Archived / ...` nodes. Duplicate groups and
  visible retired desktop frames both verify as empty.
- `UI-UX-001`, 2026-07-03: added repeatable web visual smoke automation in
  `scripts/opshub-web-visual-smoke.mjs`. The script checks public auth routes
  before login, then logs in through the live API using env-provided
  credentials, seeds the web session without committing secrets, captures
  ignored screenshots, and checks route hash, console/page errors, rendered
  Flutter viewport size, and visible horizontal overflow while ignoring Flutter
  semantics-only overflow nodes. The default live staging smoke now runs 72
  checks across desktop `1440x900` and mobile `390x844`: 3 public routes
  (`/login`, `/register`, `/forgot-password`), 1 pending auth route
  (`/assignment-pending`) rendered from a tokenless cached pending session, plus
  all 32 authenticated shell routes in `AppRouter`, including Admin, FIFO,
  BH/SC, VietQR, Payment Monitor web fallback, Sao kê, Cấn trừ, Góp ý,
  Report/Sales Report, Profile, Tasks, Home, and Settings. Follow-up guard coverage in
  `test\design_system_migration_guard_test.dart` now parses the smoke script
  and `AppRouter` so the default authenticated route list must stay aligned
  with every ShellRoute, while public and pending auth route lists are locked
  to their expected pre-shell coverage.
  Follow-up pixel sanity checks parse each PNG screenshot, verify viewport-size
  dimensions, and fail flat/blank captures through sampled-color and luminance
  range thresholds before marking a route pass.
  2026-07-03 staging rerun after deploy `2026.07.03.98+200098` fixed dynamic
  BH/SC detail route handling in the smoke script. The default inventory still
  carries `/check-warranty/details/:receiptNumber` so it stays aligned with
  `AppRouter`, but runtime smoke now resolves that route from
  `OPSHUB_VISUAL_SMOKE_WARRANTY_RECEIPT` or `GET /warranties`, and records
  `skippedRoutes` when the staging account has no readable receipt.
  Validation: `node --check scripts\opshub-web-visual-smoke.mjs`, live staging
  visual smoke pass 70/70 checked route/viewport captures with zero failure and
  one documented BH/SC detail skip, plus focused design-system guard. Gap:
  BH/SC detail visual smoke still needs a stable staging receipt fixture or
  real data.
- `UI-UX-001`/`WARRANTY-001`, 2026-07-03: route switching across shell
  workspaces now paints each route inside a full-size keyed `RepaintBoundary`
  and clipped canvas-colored viewport, and all authenticated shell routes use
  `NoTransitionPage` so Navigator does not retain the previous page during a
  short platform transition. This prevents stale previous-screen frames from
  flashing on web, Windows, and Android. BH/SC `/warranty-main` also now uses
  the same `AppResponsiveScrollView` contract as other hubs and keeps the
  optional "Về trang chủ" secondary button content-sized so desktop/tablet text
  cannot collapse into one-character columns. Validation passed focused
  warranty/router/Home regressions (19 tests), `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter compact` (299 tests),
  `flutter build windows --debug --no-pub`,
  `flutter build apk --debug --no-pub`, `flutter build web --release
  --no-pub --dart-define=API_BASE_URL=https://opshub-staging.hoanghochoi.com/api
  --dart-define=APP_ENV=staging`, and `git diff --check` with CRLF warnings
  only. Follow-up route viewport regression
  `test\app_shell_route_viewport_test.dart` locks that changing `AppShell`
  `location` replaces the keyed route viewport and that a real
  `AppRouter.go('/warranty-main')` frame removes the Home subtree immediately.
  Local Chrome click burst after the no-transition change recorded
  `afterHashHomeCount=0` for Home -> BH/SC.
- `SALES-REPORT-001`, 2026-07-01: `Báo cáo` now opens a 2-column order
  cockpit for same-day ERP orders: left unreported, right reported, 20
  orders/page/column with DB-backed totals and independent pagination. Backend
  runs a scheduled staff-bff order-list sync every 3 minutes and on service
  startup, upserts rows into `SalesReportErpOrderCache`, keeps user/admin
  visibility scoped by `data.orders.creator.email` with consultant/seller
  fallback or assigned organization subtree for `STORE_MANAGER` and other
  manager roles, maps the ERP creator to the internal user and assigned
  store/node during the scheduled upsert without erasing an existing mapping
  when a later payload is incomplete, and gives Super Admin the full saved
  cache/report scope. Purchased-order category auto-fill accepts only Listing
  `result.products[].categories[].code` values whose `level = 1`, so lower
  Laptop/PC labels on a Logitech B100 mouse cannot select extra groups. It
  reuses the existing purchased `check-order` flow when a user opens an
  unreported order dialog. Cockpit filters by date, SR, and user, with exports
  sharing the selected cockpit filters. Flutter reads the DB cache on open or
  manual reload, then refreshes from the same scoped API when the Go WebSocket
  forwards `SALES_REPORT_ORDERS_UPDATED` for a relevant user/SR/date; the
  event also fires when scheduled sync backfills missing store/node mapping for
  older cache rows. The admin export surface also includes `Trả góp`, which
  filters `installmentNeed = true` and exports Vietnamese installment columns
  plus the derived final payment method. Validation:
  `npx prisma validate`, `npx prisma generate`,
  `npm test -- --runInBand src/sales-reports`
  (37 tests), `npm run build`, Go realtime `go test ./...`,
  `flutter test --no-pub --reporter expanded test\sales_report_hub_test.dart`
  (16 tests), focused `dart analyze` on changed sales-report files, and
  `git diff --check` (CRLF warnings only).
- `AUTH-004`/`PAYMENT-MONITOR-001`, 2026-07-01: production diagnosis found
  payment monitor clients behind Caddy sharing the default IP throttling bucket,
  causing a newly opened client to receive HTTP 429 on its first request. The
  high-risk fix changes tracking to the verified JWT user id first, then
  request client identifiers such as `clientId`/`deviceId`, then a hashed public
  auth email, and uses client IP only as the last-resort bucket. It also trusts
  exactly one Caddy hop and returns Vietnamese action-oriented 429 copy.
  Validation: focused guard tests (8), full backend Jest (46 suites, 398 tests),
  NestJS build, focused ESLint on the new guard/spec and changed module wiring,
  and `git diff --check`. Gap: production smoke with more than 20 concurrent
  payment-monitor clients remains pending deployment.
- `UPDATE-001`/`UPDATE-003`/`PAYMENT-MONITOR-001`, 2026-06-30: web update
  prompts now reload the current page instead of opening a download URL, web
  users with `PAYMENT_MONITOR` can open the `Tiền vào` transaction list, and
  `Đọc loa` remains Windows-only. Staging builds pass `APP_ENV=staging`, the
  Flutter brand helper uses staging title/logo for staging API builds, and the
  staging web icon script also rewrites `index.html`/`manifest.json` before the
  web bundle is built. Follow-up: `/app-version?platform=web` now returns
  `platform=web`, empty `updateUrl`, `forceUpdate=false`, and
  `minSupportedBuild=1` so web does not inherit Android APK update metadata.
  Validation: focused Flutter tests for update gate,
  platform capabilities, router, brand asset, payment monitor provider, and
  Home (44 tests), focused NestJS app-version tests, NestJS build,
  `flutter analyze --no-pub`, PowerShell parser check for
  `scripts/apply-staging-icons.ps1`, workflow YAML parse for
  `deploy-opshub-staging.yml`, staging `flutter build web --release --no-pub`
  with `API_BASE_URL=https://opshub-staging.hoanghochoi.com/api` and
  `APP_ENV=staging`, built-bundle grep for `PhongVu OpsHub Staging` plus the
  staging logo asset, and `git diff --check` (CRLF warnings only).
- `UI-UX-001`, 2026-06-29: completed the Flutter feature-layer baseline for
  the Figma Design System 2026 migration. Auth/register/profile, Settings,
  Notifications, AppUpdate, Payment Monitor, FIFO/FIFO-check, Warranty/BH-SC,
  VietQR, Sao kê, Cấn trừ, Báo cáo, and all Admin surfaces now route feature UI
  through shared `AppColors`, `AppTextStyles`, `AppRadius`,
  `AppLayoutTokens`, `AppPrimaryButton`/`AppSecondaryButton`/`AppDialog*`,
  `AppTextInput`/`AppFormTextInput`/`AppReadOnlyField`/`AppSelectField`,
  `AppSurfaceCard`, `AppStatePanel`, `AppListSkeleton`, header-tab color
  tokens, and shared scanner/state patterns instead of local primitive widgets.
  The legacy FIFO helper namespace is retired from the old chat feature path
  and now lives under `features/fifo_check` with FIFO-check
  provider/repository/entity names. Added
  `test/design_system_migration_guard_test.dart` to keep feature
  UI free of raw `Colors.*`, `Color(0x...)`, `TextStyle`, `TextField`,
  `TextFormField`, `Card`, raw Flutter action buttons,
  `DropdownButtonFormField`, direct `InputDecoration`, raw numeric radius
  tokens, and legacy chat names. Validation: changed-file `dart format
  --output=none --set-exit-if-changed` (75 Dart files), global feature UI guard
  greps (0 raw primitive/TextStyle/dropdown/input-decoration/radius hits), FIFO
  namespace guard grep (0 hits), `flutter analyze --no-pub`, focused Flutter
  tests for shared form/theme guards, scanner, payment history states, Sales
  Report, Admin policy/feature/user scope, and personnel (50 tests), full
  `flutter test --no-pub --reporter compact` (214 tests), `flutter build
  windows --debug --no-pub`, and `flutter build apk --debug --no-pub`. Gap:
  authenticated Android/Windows screenshot smoke with real production-like data
  remains the next visual evidence pass, not a known code blocker.
- `UI-UX-001`/`VIETQR-001`, 2026-06-29: continued the Figma Design System
  2026 migration on the remaining VietQR form/result/payment-state pieces by
  moving the QR creation form, SR selector, generated-content preview, result
  QR card, waiting/confirmation/success panels, QR logo surface, and export PNG
  colors/typography onto `AppSelectField`, `AppFormTextInput`,
  `AppSurfaceCard`, `AppTextStyles`, `AppColors`, and shared radius/spacing
  tokens. Extended shared text inputs with `suffixText` and `readOnly` so
  tokenized forms can cover money suffixes and generated read-only fields.
  Validation: `dart format --output=none --set-exit-if-changed`,
  `flutter analyze --no-pub`, raw VietQR widget/color/typography guard grep,
  focused VietQR/shared-control Flutter tests (10 tests), and post-batch full
  `flutter test --no-pub --reporter expanded` (211 tests). An initial focused
  command included a non-existent repository test file and failed before being
  rerun with the correct file list.
- `UI-UX-001`, 2026-06-29: continued the Figma Design System 2026 migration on
  Home, Sort, and Feedback by moving Home support/app-info dialogs, drawer,
  compact header, payment-speaker quick toggle, Sort guidance/result/input/list
  cards, and Feedback suggestion fields/image card onto `AppDialog*`,
  `AppSurfaceCard`, `AppTextInput`, `AppFormTextInput`, `AppTextStyles`,
  `AppColors`, and shared radius/spacing tokens. Extended the shared form input
  with `helperText` so migrated forms keep their staff guidance copy without
  returning to raw `InputDecoration`. Validation: `dart format
  --output=none --set-exit-if-changed`, `flutter analyze --no-pub`, raw
  Home/Sort/Feedback widget/color guard grep, and focused Home/Feedback/Sort/
  shared-control Flutter tests (21 tests).
- `UI-UX-001`/`FIFO-001`, 2026-06-29: continued the Figma Design System 2026
  migration on the FIFO check surface by moving the active `/fifo-check` input,
  result status, and item cards onto `AppTextInput`, `AppSurfaceCard`,
  `AppTextStyles`, and shared color/radius tokens. Renamed the legacy
  FIFO-check helper module to `features/fifo_check`, with
  provider/repository/entity/widget names updated to FIFO check terminology so
  a future standalone messaging feature has a clean namespace. Validation:
  `dart format --output=none --set-exit-if-changed`, FIFO namespace guard grep,
  launch-guard greps from `docs/product/ui-ux.md`, focused scanner/validator/
  shared-control tests (17 tests), `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter expanded` (211 tests), and
  `git diff --check`.
- `UI-UX-001`, 2026-06-29: closed the shared-layer follow-up for the Figma
  Design System 2026 migration by moving shared buttons, header tabs,
  notification badges, chips, state banners, feature tiles, theme shadows, and
  payment delivery emphasis onto `AppColors`, `AppTextStyles`, `AppRadius`, and
  `AppLayoutTokens` instead of legacy aliases or one-off bold/color styles.
  Follow-up in the same migration slice added shared `AppTextInput`,
  `AppSelectField`, and `AppSurfaceCard`, then moved Sao kê filters, Sao kê
  order-update dialogs/cards, Cấn trừ filters/create dialogs/cards, and the
  Báo cáo sale admin filter/list tiles onto those shared patterns. Continuation
  moved the `Tiền vào` speaker/store panel, transaction filters/page-size
  select, speaker error panel, transaction cards, order-edit inputs, and order
  transfer/history dialog actions onto the same shared primitives. The shared
  QR/barcode scanner fallback input/button and camera overlay text/colors now
  use the same input/button/typography/color tokens while keeping the scan
  window and logging behavior intact. The Báo cáo nhập liệu screen now uses
  shared form input/select/card primitives for order checking, customer needs,
  installment, behavior, and not-purchased reason sections. Validation:
  `dart format --output=none --set-exit-if-changed`, launch-guard greps from
  `docs/product/ui-ux.md`, focused Flutter tests for theme tokens, shared form
  controls, shared buttons, gradient header, payment delivery metrics, Sao kê,
  Cấn trừ provider, and Báo cáo (20 tests), `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter expanded` (211 tests), follow-up focused
  payment monitor/shared-control tests (32 tests), focused scanner tests (3
  tests), focused Báo cáo/shared-control tests (9 tests), and
  `git diff --check`.
- `UI-UX-001`/`UPDATE-001`/`PAYMENT-MONITOR-001`, 2026-06-29: started the
  Figma Design System 2026 migration at the shared theme layer by mapping
  semantic Foundation colors, typography, radius, and spacing into
  `AppColors`, `AppTextStyles`, `AppRadius`, `AppLayoutTokens`, and `AppTheme`
  while keeping legacy aliases; added Flutter web build/deploy to production
  and staging roots with Caddy SPA fallback after API/ws/download/help/upload
  routes; kept `Tiền vào` and payment speaker runtime off web with a logged
  unsupported direct route. Validation: `dart format --output=none
  --set-exit-if-changed`, workflow YAML parse through backend `js-yaml`,
  `flutter build web --debug --no-pub
  --dart-define=API_BASE_URL=https://opshub.hoanghochoi.com/api`,
  `flutter analyze --no-pub`, focused Flutter tests for platform capabilities,
  router unsupported route, Home, shared buttons, and gradient header (15
  tests), and `git diff --check`. Gap: local Caddy validation could not run
  because Docker daemon is unavailable and local `caddy` is not installed; live
  staging/production route smoke and real Windows speaker regression remain
  post-deploy checks.
- `SALES-REPORT-001`, 2026-07-01: sales reports now require `Tên khách hàng`,
  map Listing `categories` to `Type` in `data/categories.csv` by highest
  category level for order-item `categoryType`, and export Vietnamese CSV
  shapes. At that point `HVTC` was one row per report and `Doanh số` was a
  summary by customer type/category type; later evidence above adds the
  `Trả góp` export. CSV values are sanitized instead of quote-wrapped.
  Validation: `npx prisma validate`, `npx prisma generate`,
  `npm test -- --runInBand src/sales-reports` (21 tests), `npm run build`,
  `flutter test --no-pub --reporter expanded test/sales_report_hub_test.dart`
  (10 tests), focused `dart analyze` on changed sales-report files, and
  `git diff --check` (CRLF warnings only).
- `SALES-REPORT-001`, 2026-06-29: Purchased order check now blocks ERP orders
  whose `confirmationStatus` or `fulfillmentStatus` is `cancelled` regardless
  of case; purchased form supports QR/barcode order scan and checking another
  order; reports support multiple selected category groups; installment reports
  store success/failure plus one or more fixed partners and require a failure
  reason for not-purchased installment failures. Validation:
  `npx prisma validate`, `npx prisma generate`,
  `npm test -- --runInBand src/sales-reports` (14 tests), `npm run build`,
  `flutter test --no-pub --reporter expanded test/sales_report_hub_test.dart`
  (5 tests), `flutter analyze --no-pub`, and `git diff --check`.
- `SALES-REPORT-001`, 2026-06-30: after a report submit succeeds, the Flutter
  form resets and scrolls back to the top of the page. The sales-report CSV
  export now uses a compact `query_1`-style 34-column shape: one row per ERP
  item, order/item/payment fields in dedicated columns, and OpsHub form answers
  folded into `Order note` to avoid repeated form columns. Validation:
  `npm test -- --runInBand src/sales-reports` (17 tests), `npm run build`,
  `flutter test --no-pub --reporter expanded test/sales_report_hub_test.dart`
  (8 tests), and `flutter analyze --no-pub`.
- `SALES-REPORT-001`, 2026-06-30: admin `Báo cáo sale` list/export now has a
  `Ngày` filter that sends `startDate`/`endDate` date-only query params and
  preserves the selected range when moving between pages. Validation:
  `flutter test --no-pub --reporter expanded test/sales_report_hub_test.dart`
  (10 tests).
- `SALES-REPORT-001`, 2026-06-30: Sales report forms switch user-facing
  selectors from dropdowns to checkbox groups, add customer type/student and
  CTKM fields, expand installment capture to need/partner/approval/loan
  amount/no-installment reason with Mirae Asset and MPOS, persist ERP customer
  type and payment methods, and export one CSV row per ERP product item.
  Validation: `npx prisma validate`, `npx prisma generate`,
  `npm test -- --runInBand src/sales-reports` (15 tests), `npm run build`,
  `flutter test --no-pub --reporter expanded test/sales_report_hub_test.dart`
  (5 tests), `flutter analyze --no-pub`, and `git diff --check` (CRLF warnings
  only).
- `SALES-REPORT-001`, 2026-07-01: Purchased-report customer type auto-detect
  reads `data.order.billingInfo.customerType` and
  `data.order.billingInfo.taxCode`; top-level `order.customerType` is ignored.
  Validation: `npm test -- --runInBand src/sales-reports` (26 tests),
  `npm run build`, and `git diff --check`.
- `SALES-REPORT-001`, 2026-07-01: Category auto-detect keeps canonical group
  names such as `PC` exact-only, while IDs/Vietnamese labels/subcategory aliases
  remain fallback candidates. This prevents service item names containing `PC`
  from auto-selecting `Máy tính bộ`; the reported VGA/PSU/network-card/service
  example maps to `NH03`, `NH08`, and `NH95` only. Validation:
  `npm test -- --runInBand src/sales-reports/sales-report-categories.service.spec.ts`.
- `SALES-REPORT-001`, 2026-07-01: Purchased-order category candidates now
  include `result.products[].categories[].code/id/name` from Listing before the
  product name fallback, so level-1 codes like `NH08` are used directly for
  auto-ticking ngành hàng even when `productGroup` is missing. Validation:
  `npm test -- --runInBand src/sales-reports/sales-report-erp.service.spec.ts`.
- `SALES-REPORT-001`, 2026-06-30: Customer type UI makes
  `Học sinh - Sinh viên` a child checkbox of `Cá nhân`, auto-selects `Cá nhân`
  when HS-SV is checked, clears/locks personal flags when `Doanh nghiệp` is
  selected, and formats sales-report money fields/displays with `vi_VN`
  thousand separators. Validation: `npm test -- --runInBand src/sales-reports`
  (16 tests), `npm run build`,
  `flutter test --no-pub --reporter expanded test/sales_report_hub_test.dart`
  (7 tests), focused `dart analyze` on changed sales-report/helper/test files,
  and `git diff --check`. Full `flutter analyze --no-pub` is blocked by the
  unrelated dirty VietQR `_historyLoaded` errors in
  `lib/features/vietqr/presentation/screens/vietqr_screen.dart`.
- `SALES-REPORT-001`, 2026-06-29: Listing `productGroup.code` is included in
  category candidates and matched directly to `Cat group ID` from
  `data/categories.csv`; category aliases remain fallback. Sales report forms
  require customer need, category, not-purchased reason when applicable, and
  explicit behavior answers instead of defaulting to `Có`. Validation:
  `npm test -- --runInBand src/sales-reports` (9 tests), `npm run build`,
  `flutter test --no-pub --reporter expanded test/sales_report_hub_test.dart`
  (2 tests), `flutter analyze --no-pub`, and `git diff --check`.
- `SALES-REPORT-001`, 2026-06-29: moved the admin `Báo cáo sale` list/export
  entry out of `Quản trị` and into the `Báo cáo` hub. Home and `/sales-reports`
  now open when either `SALES_REPORT` or node-assigned `ADMIN_SALES_REPORTS` is
  available; the submit forms still require `SALES_REPORT`, and the admin
  list/export route still requires `ADMIN_SALES_REPORTS`. Validation:
  focused Flutter widget tests for `sales_report_hub_test.dart` and
  `home_feedback_action_test.dart`, `flutter analyze --no-pub`, and
  `git diff --check`.

| Story                 | Contract                                                                                                                                                                                                                                                                                                                      | Unit    | Integration                             | E2E                          | Platform                                       | Status              | Evidence                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | --------------------------------------- | ---------------------------- | ---------------------------------------------- | ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SALES-REPORT-001      | Sale report forms for purchased and not-purchased customers, purchased order ERP check before submit, unique purchased `orderCode`, categories from `data/categories.csv` with Vietnamese labels, node-feature admin query/export, and dashboard-ready DB tables.                                                               | yes     | backend build/API contract              | app analyze + Home test      | ERP live smoke pending                         | in_progress         | 2026-06-29: added backend Prisma schema/migration, sales-report API, ERP lookup service, CSV category sync, Flutter Home/Admin entries, report form, admin list/export shell, and docs. Validation in current patch: `npx prisma generate`, `npx prisma validate`, focused backend `npm test -- --runInBand src/sales-reports/sales-reports.service.spec.ts` (4 tests), backend `npm run build`, `flutter analyze`, focused `flutter test test/home_feedback_action_test.dart --reporter expanded` (6 tests), and `git diff --check`. Pending: live ERP credential smoke, migration apply on deployed DB, and CSV open-in-Excel smoke; focused sales-report widget coverage is now tracked above in `test/sales_report_hub_test.dart`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| AUTH-001              | Email/password registration, sign-in, accepted Phong VÃ…Â© email domains, and JWT-backed sessions for Phong VÃ…Â© staff                                                                                                                                                                                                       | partial | no                                      | no                           | mobile smoke needed                            | changed             | 2026-05-15: flow changed to explicit registration; validation pending in current patch                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| AUTH-002              | Authenticated password change, forgot-password email reset codes, in-app password reset, super-admin direct password reset, single-use hashed reset tokens, and JWT token-version invalidation                                                                                                                                | yes     | backend reset-code tests                | no                           | SMTP/app smoke pending                         | changed             | 2026-06-03: changed forgot-password from emailed reset links to 6-digit email reset codes that expire after 10 minutes, added in-app code verification before entering the new password, changed SUPER_ADMIN user management reset to direct password setting, and documented Gmail SMTP sender display as the verified alias `admin@hoanghochoi.com`. Validation: focused backend auth/user Jest (4 suites, 41 tests), `npx prisma validate`, `npx prisma generate`, `npm run build`, full backend `npm test -- --runInBand` (30 suites, 198 tests), focused Flutter auth repository test, `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded` (52 tests), and `git diff --check`. Gap: live SMTP sender/code delivery smoke and deployed app click-through remain pending. Earlier 2026-05-31 evidence: reset token table, tokenVersion, backend reset APIs, backend-served legacy reset page, Flutter forgot/change/admin reset UI, and AppLogger events.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| AUTH-003              | One active auth session per user/platform (`windows`, `android`, `ios`, `macos`, `linux`, `web`), same-platform login replacement, protected-route session enforcement, logout revocation, and client app-local device identity                                                                                               | yes     | backend session/JWT tests               | no                           | same-platform and cross-platform smoke pending | changed             | 2026-05-31: added Prisma user platform session table, backend session issuance/enforcement/logout, locked-user JWT rejection, reset-password session revocation, Flutter device metadata on login/register, and auth-failure local session clearing. Validation: `npx prisma validate`, `npx prisma generate`, focused auth/session Jest, full `npm test -- --runInBand` (29 suites, 164 tests), `npm run build`, `flutter analyze --no-pub`, `flutter test --no-pub --reporter expanded` (39 tests), `git diff --check`. Gap: same-platform/cross-platform live smoke after deploy pending.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| FIFO-001              | FIFO check, export/unexport, sort workflows against OpsHub `fifo_inventory`, daily BigQuery inventory refresh, supplemental manual Excel import, and admin history                                                                                                                                                            | partial | backend unit tests                      | no                           | mobile smoke needed                            | changed             | 2026-06-05: moved the manual `Cáº­p nháº­t tá»“n kho` entry from Quáº£n trá»‹ into the FIFO menu, added `/fifo/inventory-import` as the visible route, kept `/admin/inventory-import` as a backward-compatible alias, and kept both import routes guarded by `FIFO_IMPORT`; Home now opens FIFO when either FIFO workflows or FIFO import is available. Validation: `dart format`, `git diff --check`, `flutter analyze --no-pub`, and full `flutter test --no-pub --reporter expanded` (59 tests). Gap: live admin-user menu click-through remains manual. 2026-05-26: rebuilt FIFO cache contract around canonical BigQuery columns plus `opshub_*` metadata; serial check uses 20-day FIFO date tolerance, display-reserved handling, and short production labels. Manual Excel import maps the Vietnamese serial inventory export into canonical columns and stays additive. Targeted backend tests passed; pending live BigQuery env/deploy smoke and mobile smoke. 2026-05-24: manual import now preserves FIFO `import_date` priority as BigQuery date > existing DB date > file date; when no original/DB date exists, the file date is used for FIFO sorting and also stored separately in `manual_import_date`. Also moved FIFO inventory ownership to OpsHub DB and added admin manual inventory Excel parser/import endpoint and UI entry; parser verified against sample file shape. 2026-05-23: added SR-scoped FIFO API and sort delegation, exported toggle contract, replaced the legacy conversation-style FIFO UI, and cleaned up navigation; pending full live VPS smoke                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| WARRANTY-001          | Warranty/repair image capture, upload, same-showroom read/status scope, legacy n8n metadata migration, and status updates                                                                                                                                                                                                     | yes     | production metadata migration smoke     | no                           | upload and WebSocket smoke needed              | changed             | 2026-06-06: changed the n8n warranty migration script to reconcile existing OpsHub warranty rows instead of skipping them; supports `--store=CP62` and explicit `--reassign-existing-creators`, merges normalized n8n image links with existing app links, rewrites stored legacy n8n image hosts to `IMAGE_BASE_URL`, creates/patches locked legacy technical users only when passwordless/no store, and preserves app-created images. Validation: `node --check scripts/migrate-n8n-warranty-metadata.mjs`, `node --test scripts/migrate-n8n-warranty-metadata.test.mjs` (7 tests), VPS app DB backup `/srv/opshub/backups/opshub-before-warranty-creator-reassign-20260606043026.sql.gz`, production CP62 dry-run (77 existing rows, 73 creator updates, 0 image updates), production apply (73 existing creators updated, 0 image updates), post-apply compare (77 n8n receipts, 77 app receipts, 0 creator mismatches, 0 CP62 rows still under `super_admin@phongvu-mna.vn`), idempotent dry-run (0 pending creator/image updates), and production image verification (77 rows, 715 app URLs, 0 legacy image hosts, 0 bad URLs, 0 missing files). Gap: upload/WebSocket smoke remains pending. 2026-06-03: added backend showroom-scoped Warranty list/search/detail/status checks with SUPER_ADMIN full access, repo-tracked n8n metadata migration script, and migrated production n8n-only metadata into OpsHub DB. Validation: focused warranty Jest, `npm run build`, DB backup before apply, production migration dry-run/apply, post-apply idempotent dry-run, and production verify: 78 Warranty rows, 717/717 app URLs with existing files, 0 legacy image hosts, all creators store-scoped. Gap: deployed scoped API smoke after build and mobile upload/WebSocket smoke remain pending.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| FEEDBACK-001          | Staff feedback submission through app and API                                                                                                                                                                                                                                                                                 | partial | no                                      | no                           | mobile smoke needed                            | existing_unverified | Product docs seeded from README/code inspection                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| VIETQR-001            | Manual VietQR transfer QR creation screen, API payload generation with optional amount/content, persisted payment intent, MAP transaction confirmation rule, QR-screen auto confirmation polling, confirmed transaction detail display, and secured n8n QR image/info API                                                     | yes     | MAP live smoke partial                  | no                           | mobile smoke needed                            | changed             | 2026-06-02: added backend DB-only auto reconciliation for every `PENDING` VietQR payment intent every 5 seconds, sharing the same stored MAP transaction matching rule across app-created and n8n-created QR records; still-pending intents become `FAILED` after their Vietnam-local creation day has passed, and app confirm no longer revives failed intents through direct MAP fallback. Validation: focused VietQR Jest (28 tests), `npm run build`, full `npm test -- --runInBand` (30 suites, 188 tests), `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded` (41 tests), and `git diff --check`. Gap: live deployed n8n/app status smoke pending. 2026-06-01: added API-key protected `/vietqr/n8n` JSON and `/vietqr/n8n/image` PNG endpoints for n8n, server-rendered the app-style VietQR image from the same backend payload, fixed the confirmed QR UI so the waiting card no longer remains after payment success, and added image decode proof that generated PNGs contain the exact service QR payload with valid CRC. Validation: focused VietQR Jest, `npm run build`, full `npm test -- --runInBand` (30 suites, 179 tests), `flutter analyze --no-pub`, `flutter test --no-pub --reporter expanded` (40 tests), visual PNG check, and `git diff --check`. Gap: live n8n call and real banking-app scan against production account pending. 2026-05-21: added Vietnam-local MAP timestamp parsing, matched transaction detail persistence, and Flutter confirmed-state UI; `npx prisma generate`, `npm run build`, `npm test -- --runInBand`, `flutter analyze`, `flutter test`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| PAYMENT-MONITOR-001   | Backend polls configured VietinBank MAP accounts, persists successful incoming transactions, creates scoped payment audio notifications, publishes store-filtered realtime events, and Windows PC plays `ting ting` plus generated/fallback speech for every newly observed amount independent from OpsHub QR/payment intents | yes     | MAP/payment notification/realtime tests | no                           | Windows build proof                            | changed             | 2026-06-03: Windows payment audio now parses/logs WAV headers and, only after MCI returns `326` for WAV, writes a local temp `WAV PCM 16-bit mono 44100 Hz` and retries once without requesting a larger server payload. `PaymentSpeaker` logs WinMM device count, MCI code/message, source/normalized WAV metadata, and normalized playback status. Validation: `flutter test --no-pub test\payment_wav_tools_test.dart --reporter expanded`, `flutter test --no-pub test\payment_speaker_io_test.dart --reporter expanded`, `flutter test --no-pub test\payment_monitor_provider_test.dart --reporter expanded`, `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded` (50 tests), `flutter build windows --release --no-pub --dart-define=API_BASE_URL=https://opshub.hoanghochoi.com/api`, `git diff --check`. Gap: physical speaker smoke on a real machine that reproduces MCI 326 remains pending. 2026-06-01: Windows payment monitor now initializes `media_kit` for desktop audio, plays each notification through `media_kit` -> Win32 `PlaySoundW` (WAV) -> MCI fallback, uploads `PaymentSpeaker` started/succeeded/failed logs with sanitized context, retries failed playback up to 3 attempts with a 10-second delay while reusing the same downloaded audio bytes, acknowledges interim `PLAYBACK_FAILED`, and only acknowledges terminal `FAILED` after attempt 3. Validation: `flutter analyze --no-pub`, `flutter test --no-pub --reporter expanded` (40 tests), `npm test -- --runInBand src/payment-notifications/payment-notifications.service.spec.ts` (9 tests), `npm run build`, `flutter build windows --debug --no-pub`, `git diff --check`. Follow-up 2026-06-01: pinned `media_kit_libs_windows_audio` to upstream git commit `7102e7da96f39c718487a8f7a59b6a034aae7f45` (`fix: CMP0175 warning on Windows (#1377)`), re-ran `flutter clean`, `flutter pub get`, and a clean `flutter build windows --debug --no-pub`, and the previous Windows CMake `add_custom_command` policy warning no longer appeared. Gap: live Windows speaker smoke still needs physical-audio verification. 2026-05-30: payment notification TTS text now ends with a period and Piper speed defaults to `0.90` so final `Ä‘á»“ng` audio has more room to finish. Validation: generated and verified `artifacts/tts-samples/payment-speed-090-no-period.wav` and `artifacts/tts-samples/payment-speed-090-period.wav`, `npm test -- --runInBand src/payment-notifications/payment-notifications.service.spec.ts`, `npm run build`, `git diff --check`. Gap: live VPS env/deploy smoke pending. 2026-05-27: added repo-tracked Piper `vi-vais1000` TTS sidecar files for home-server deploy; it keeps the existing `/synthesize` payload contract, returns WAV, accepts legacy `custom:suong-vo`, and rolls out on port `18081` with VieNeu on `18080` as rollback. Validation: `python -m py_compile deploy/home-server/tts-piper/app.py`, VPS temp sidecar smoke on port `18082`, `npm test -- --runInBand src/payment-notifications/payment-notifications.service.spec.ts`, `npm run build`, `git diff --check`. 2026-05-27: global MAP account sync added as primary path; backend maps `virtualAccount` to `Store.transferAccountNumber`, stores matched transactions by showroom, quarantines unmapped/ambiguous rows without audio, and keeps per-store credentials as fallback. Validation: `npx prisma generate`, `npm test -- --runInBand src/map-vietin/map-vietin.service.spec.ts src/payment-notifications/payment-notifications.service.spec.ts src/vietqr/vietqr.service.spec.ts`, `npm run build`, `git diff --check`. 2026-05-27: compacted payment monitor UI by removing the standalone last-updated banner, moving the timestamp into the auto-update chip, and adding Vietnam-local stored-transaction date range filtering. Validation: `flutter analyze`, `flutter test`, `npm test -- --runInBand src/map-vietin/map-vietin.service.spec.ts`, `npm run build`, `git diff --check`. 2026-05-26: payment notification TTS now reads `Phong VÅ© Ä‘Ã£ nháº­n: <amount> Ä‘á»“ng` through VieNEU voice id `custom:suong-vo` (`Suong Vo`) at speed `0.98` and pitch `1.00`. Validation: `npm test -- --runInBand src/payment-notifications/payment-notifications.service.spec.ts`, `npm run build`, `git diff --check`. 2026-05-26: mute toggle now disables speaker only while transaction sync continues; muted notifications are acknowledged as `SILENCED` so they are not replayed later, and the payment monitor screen shows sync loading in a separate stable chip. Validation: `npm test -- --runInBand src/payment-notifications/payment-notifications.service.spec.ts`, `npm run build`, `flutter analyze`, `flutter test`, `git diff --check`. 2026-05-21: added payment notification tables/service, scoped realtime filtering, Flutter realtime notification parsing, and Windows audio asset build proof; `npx prisma generate`, `npm run build`, `npm test -- --runInBand src/payment-notifications/payment-notifications.service.spec.ts src/map-vietin/map-vietin.service.spec.ts src/vietqr/vietqr.service.spec.ts src/auth/auth.service.spec.ts`, `go test ./...`, `flutter analyze`, `flutter test`, `flutter build windows --debug` |
| PAYMENT-STATEMENT-001 | MAP bank statement reconciliation stores multiple extracted order codes, preserves manual edits, supports scoped search/export, inline order correction with audit history, sticky statement layout, copyable text, and order-presence card borders in Sao ke and Tien vao                                                    | yes     | focused MAP statement service tests     | no                           | Windows UI smoke manual                        | changed             | 2026-06-01: fixed Sao ke SR searches for SUPER_ADMIN by defaulting an empty date range to the current Vietnam-local day and paging the full snapshot in 100-row backend-safe chunks; added focused Flutter provider coverage and backend super-admin `storeIds` coverage. Validation: `flutter test --no-pub test\bank_statement_provider_test.dart --reporter expanded`, `npm test -- --runInBand src/map-vietin/map-vietin.service.spec.ts`, `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded`, `npm run build`, `git diff --check`. Gap: live Windows UI click-through remains manual. 2026-05-29: added Prisma order array/audit migration, MAP multi-order extraction with manual-preserve behavior, statement list/update/history/export endpoints, Flutter Sao ke screen, home route, AppLogger events, Tien vao order-presence borders, and bank statement model/provider tests. Validation: `npx prisma validate`, `npx prisma generate`, `npm test -- --runInBand src/map-vietin/map-vietin.service.spec.ts` (23 tests), `npm run build`, `flutter analyze --no-pub`, `flutter test --no-pub --reporter expanded` (33 tests). Gap: full Windows UI click-through remains manual.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| PROFILE-ADMIN-001     | Profile avatar, admin-assigned organization nodes, pending-assignment auth gate, store account import, fixed `SUPER_ADMIN -> ADMIN -> USER` roles, Lv0-Lv5 organization tree administration through `ADMIN_ORG_TREE`, retired legacy Region/Area/SR/admin-store/self-select APIs, scoped MAP credential settings, hidden legacy feature codes, and tree-first admin user management | yes     | backend auth/user/feature tests         | mobile smoke                 | Android                                        | changed             | 2026-06-13: registration/login no longer self-selects SR; users without `organizationNodeId` get `assignmentPending=true` and are routed to `/assignment-pending`; `/users/me/select-store` returns `410 Gone`; admin user editing uses a searchable organization-node picker with no direct department/job-role rows; org-tree route/menu uses `ADMIN_ORG_TREE`; legacy `ADMIN_STORES`, `ADMIN_REGIONS`, and `ADMIN_PERSONNEL` are hidden from the feature picker with migration/backfill to `ADMIN_ORG_TREE`. Validation: `npx prisma validate`, `npx prisma generate`, backend `npm run build`, full backend `npm test -- --runInBand` (35 suites, 256 tests), `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded` (87 tests), and `git diff --check`. Gap: live staging smoke remains manual.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| PERSONNEL-001         | Personnel assignment keeps fixed system roles separate from department, job role, Lv0-Lv5 organization node placement, derived `NATIONAL -> REGION -> AREA -> STORE` compatibility scope, generated `JOBROLE_SR_AREA_REGION` personnel codes, and API-level feature gates                                                      | yes     | backend feature/user/auth tests         | no                           | admin UI smoke needed                          | changed             | 2026-06-04: added Region/Area catalogs, SR area assignment, scope fields `regionCode`/`areaCode`, virtual `CHATSALE`/`TELESALE` Region scopes, `STORE_MANAGER` operational job role, `ONLINE -> CHATSALE` migration, `MULTI_STORE` migration precheck/rejection, feature definitions/rules with backend guards, `/features/me`, admin feature UI, and removed bottom navigation in favor of Home feature grid. Validation in current patch: `npx prisma validate`, `npx prisma generate`, backend `npm run build`, focused auth/user/feature Jest, full `npm test -- --runInBand` (31 suites, 208 tests), `flutter analyze --no-pub`, and full `flutter test --no-pub --reporter expanded` (53 tests).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| UI-UX-001             | Android and Windows operational UI uses consistent auth density, desktop max-width layout contracts, shared form spacing, shared empty/loading/error/status states, and 16 KB Android native-library build readiness                                                                                                          | yes     | no                                      | Windows smoke partial        | Android build and Windows smoke                | changed             | 2026-06-05: added the canonical UI/UX product contract at `docs/product/ui-ux.md`, centralized payment-monitor platform support through `AppPlatformCapabilities`, kept unsupported direct route access on a shared Windows-only state, made warranty details responsive with tokenized colors and download logging, and replaced targeted admin/FIFO/warranty/sort hard-coded colors with `AppColors` tokens. Validation: focused platform capability test, focused unsupported-screen widget test, `dart format --output=none --set-exit-if-changed`, `git diff --check`, `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded` (56 tests), `flutter build windows --debug --no-pub`, and `flutter build apk --debug --no-pub`. Gap: authenticated Android/Windows visual screenshot smoke with real warranty/admin/sort data remains manual. 2026-05-25: implemented `docs/ux-ui-audit-2026-05-25.md` follow-up pass; `git diff --check`, `flutter analyze`, `flutter test`, `flutter build apk --debug`, `zipalign -c -P 16 -v 4 build/app/outputs/flutter-apk/app-debug.apk`, Windows debug smoke. Follow-up form/layout consistency pass normalized auth/profile/retired branch-assignment/admin/FIFO/sort/warranty/feedback/VietQR/payment/FIFO scanner input spacing and responsive wrappers; re-ran `git diff --check`, `flutter analyze`, `flutter test`, and Windows debug smoke. Android device install was blocked by `INSTALL_FAILED_USER_RESTRICTED` without forced uninstall.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| SETTINGS-001          | Side menu opens app settings, and Windows users can toggle per-user startup with Windows through the current app executable registry entry                                                                                                                                                                                    | no      | no                                      | no                           | Windows startup smoke partial                  | changed             | 2026-05-27: added side-menu Settings route and Windows startup toggle backed by per-user `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` value `PhongVuOpsHub`; flow logs load, unsupported platform, toggle start, success, and failure through `AppLogger`. Validation: `flutter analyze --no-pub`, `flutter test --no-pub --reporter expanded`, `flutter build windows --release --no-pub --dart-define=API_BASE_URL=https://opshub.hoanghochoi.com/api`, and local reversible registry smoke confirmed the value can be written as a quoted path to the release exe and deleted back to missing. Gap: full UI click-through/restart login smoke remains manual.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| CLIENT-LOGS-001       | Authenticated clients upload one sanitized previous-day activity summary per day through the existing app-log pipeline without sending the raw log file                                                                                                                                                                       | yes     | no                                      | no                           | Windows runtime smoke needed                   | implemented         | 2026-05-30: added client daily log summary builder, sanitizer, authenticated once-per-day upload trigger, and story/docs. Validation: `flutter test --no-pub test/daily_activity_log_test.dart --reporter expanded`, `flutter analyze --no-pub`, `flutter test --no-pub --reporter expanded`, `git diff --check`. Gap: live Windows authenticated upload smoke remains manual.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| WINDOWS-DIST-001      | Windows releases support internal Authenticode signing for the app executable and Inno installer when GitHub signing secrets are configured, keep unsigned fallback explicit when secrets are missing, publish SHA256 checksums for direct Windows downloads, and expose Windows EXE/ZIP links through `/download`            | no      | no                                      | no                           | Windows package proof partial                  | changed             | 2026-06-04: added `/download` and `/downloads/latest.json` so staff can download the current Windows installer, portable ZIP, and checksum from a public landing page; manual `workflow_dispatch skip_client_build=true` refreshes only static download assets and manifest from live artifacts without rebuilding Windows packages. Validation: `git diff --check`, workflow YAML parse, `node --check scripts/download-manifest.mjs`, temp artifact manifest smoke, live artifact manifest smoke against the current public APK/EXE/ZIP/checksum, inline HTML JavaScript syntax check, and local static route smoke for `/download`, `/download/`, `/downloads/latest.json`, and icon. Gap: local Caddy validation unavailable because local `caddy` is missing and Docker daemon is not running; workflow now validates Caddyfile on the VPS with `caddy:2-alpine` before applying it; live skip-build dispatch remains pending. 2026-06-03: added optional internal Windows signing in GitHub Actions, signing helper script, post-signing SHA256 generation for direct Windows ZIP/installer downloads, bundled current-user certificate import in Inno when a signing certificate is available, and internal certificate rollout docs. Validation: `dart pub get --offline`, workflow YAML parse check, PowerShell parser check for `scripts\sign-windows-artifact.ps1`, `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded` (50 tests), `flutter build windows --release --no-pub --dart-define=API_BASE_URL=https://opshub.hoanghochoi.com/api`, Inno Setup 6.7.0 local compile of validation installers with and without `/DInternalCodeSigningCertPath`, local SHA256 file generation for validation ZIP/installer, and signing helper smoke with a temporary self-signed PFX on a copied EXE (`Get-AuthenticodeSignature` became non-`NotSigned`; status `UnknownError` because the temporary cert was not trusted). Gap: signed GitHub Actions run requires real signing secrets; target-PC warning smoke requires a managed PC with the public `.cer` installed in Trusted Root and Trusted Publishers.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| WINDOWS-INSTALL-001   | Windows installer bundles Microsoft Visual C++ Redistributable x64, installs it before app launch when the runtime is missing/old/incomplete, keeps Windows update metadata pointed at the setup EXE, and leaves the portable ZIP as manual/internal distribution                                                             | no      | no                                      | installer smoke partial      | Windows installer build proof                  | changed             | 2026-06-03: installer now performs a non-blocking Windows audio preflight before install by checking `Audiosrv`, `AudioEndpointBuilder`, and WinMM `waveOutGetNumDevs`; interactive installs show a warning when audio service/device checks fail, while silent installs only log the warning and continue. Validation: Microsoft `vc_redist.x64.exe` downloaded with valid signature, `flutter build windows --release --no-pub --dart-define=API_BASE_URL=https://opshub.hoanghochoi.com/api`, Inno Setup 6.7.0 compile succeeded with the bundled redist and updated preflight code, `git diff --check`. Gap: clean-VM missing-service/no-output interactive warning smoke and missing-runtime/UAC path remain pending. 2026-05-27: installer now embeds official Microsoft `vc_redist.x64.exe`, checks registry version plus required DLLs, runs the prerequisite elevated with `/install /quiet /norestart /log`, accepts reboot-required outcomes, and skips postinstall launch when reboot is needed. Validation: redist downloaded with valid Microsoft signature, `git diff --check`, `flutter build windows --release --dart-define=API_BASE_URL=https://opshub.hoanghochoi.com/api`, Inno Setup 6.7.0 compile confirmed `vc_redist.x64.exe` included, and silent installer smoke exited 0 on a machine where runtime 14.44 was already present. Gap: missing-runtime/UAC path still needs clean Windows VM smoke before push.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| PLATFORM-001          | NestJS, Go realtime, PostgreSQL, Redis local stack health                                                                                                                                                                                                                                                                     | partial | no                                      | no                           | health checks needed                           | existing_unverified | Product docs seeded from README/code inspection                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| UPDATE-001            | Mobile clients check backend version metadata and require APK updates when server build is newer or minimum supported build is raised; staff can use `/download` backed by `/downloads/latest.json` to download the latest APK, Windows installer, Windows ZIP, and checksum                                                  | yes     | no                                      | mobile/download smoke needed | Android, Windows, public web                   | changed             | 2026-06-05: fixed old Android/Windows clients losing the update prompt during startup redirects by keeping the update result in `AppUpdateGate` state and rendering a blocking modal overlay above the router instead of a transient navigator dialog; optional prompts dismiss only from `Äá»ƒ sau`, required prompts keep blocking and open the update URL. Validation: focused `flutter test --no-pub test/app_update_gate_test.dart --reporter expanded`, `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded` (59 tests), `flutter build windows --debug --no-pub`, `flutter build apk --debug --no-pub`, `git diff --check`. Gap: live old APK/Windows installer startup smoke against production metadata remains manual. 2026-06-04: added the public `/download` landing page, CI-generated `latest.json`, and manual `skip_client_build=true` static-only deploy path that does not change app-version metadata or rebuild APK/EXE/ZIP. Validation: `git diff --check`, workflow YAML parse, `node --check scripts/download-manifest.mjs`, temp artifact manifest smoke, live artifact manifest smoke against current public files (`2026.06.03.55+100055`), inline HTML JavaScript syntax check, and local static route smoke. Gap: local Caddy validation unavailable because local `caddy` is missing and Docker daemon is not running; live workflow dispatch smoke remains pending.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| HELP-001              | Public `/help` serves Markdown-authored staff guidance and roadmap content with image assets, `/download` links to it, and the Flutter Home side menu opens the help page externally with `AppLogger` coverage                                                 | yes     | no                                      | static route smoke           | Web, Android, Windows                          | implemented         | 2026-06-27: added Markdown sources under `docs/help/`, `navigation.json` parent/child menu config, static help renderer, build script, Caddy `/help` route, production/staging deploy copy and smoke steps, `/download` help link, and Home side-menu help link with sanitized AppLogger start/success/failure logging. Follow-up: added the `getting-started.md` child-page example and expanded `docs/help/README.md` with Markdown syntax, image rules, child-page setup, top-level page setup, design template, local preview, deploy, and checklist guidance. 2026-06-29: production workflow also listens to `help-content`; that branch is the production `docs/help` content source, pushes to it run only the static help/download deploy, and full `main` deploys load `docs/help` from `origin/help-content` when available. Validation: `node --check scripts/build-help-site.mjs`, `node scripts/build-help-site.mjs`, inline JavaScript syntax checks for `deploy/home-server/help.html` and `deploy/home-server/download.html`, workflow YAML parse through backend `js-yaml`, local Node static route smoke for `/help` plus navigation and Markdown files, `flutter test --no-pub test\home_avatar_test.dart --reporter expanded` (4 tests), `flutter analyze --no-pub`, and `git diff --check`. Gap: live `/help` smoke waits for staging/production deploy; local Caddy validation skipped because `caddy` is not installed. |
| UPDATE-003            | Running Android, Windows, and web clients receive a public app-version WebSocket event after backend deploy, then re-read public `/app-version` metadata before showing the existing optional/required update prompt or web reload action                                                                                       | yes     | mocked Redis/WebSocket contracts        | widget flow verified         | Android, Windows, and web builds             | implemented         | 2026-07-03 Web smoke added `scripts/opshub-web-smoke-proxy.mjs` and proved the local same-origin Web build can open production `/ws/app-updates` without browser console errors. 2026-07-03 live staging smoke published `APP_VERSION_UPDATED` through staging Redis; raw public WebSocket received `APP_UPDATE` with `web.latestBuild=200083`, and Chrome CDP on deployed Flutter web saw `/ws/app-updates`, the smoke frame, and one follow-up `/api/app-version?platform=web` request with console/runtime errors at 0. 2026-06-30: web metadata uses `platform=web`, an empty update URL, `forceUpdate=false`, and reload-only UI so web does not inherit Android APK updates. 2026-06-24: NestJS publishes sanitized Android/Windows build metadata to Redis after startup, Go exposes public update-only `/ws/app-updates`, and Flutter reconnects with backoff then re-checks HTTP metadata on event, connection, resume, and metadata retry. Public clients cannot receive warranty/payment events. Validation: focused Flutter update-gate tests (7), full Flutter tests (139), Flutter analyze, Windows release build, Android production-debug APK build, focused NestJS app-version tests (5), full backend Jest (39 suites, 308 tests), NestJS build, Go tests, and live staging Redis/WebSocket/browser smoke. Live smoke reused current metadata to avoid forcing staff; visible forced-prompt UI remains covered by widget/local update-gate tests. |

## Recent Evidence

- UI-UX-001, 2026-07-03: Redesign audit baseline now has a status addendum so
  the 30/06/2026 score is not mistaken for the current migration state. The
  addendum points acceptance tracking to the gap map and this matrix, records
  the current 72 route/viewport web visual smoke scope, and keeps remaining
  native camera/QR, Windows hardware, and screen-reader checks explicit before
  calling full visual parity. Validation: `git diff --check`.
- UI-UX-001, 2026-07-03: Web visual smoke failure output now redacts
  `access_token`, JWT-like values, and bearer tokens before writing console,
  page, or fatal errors to stdout/summary. Validation: `node --check
  scripts\opshub-web-visual-smoke.mjs`, focused
  `flutter test --no-pub --reporter expanded
  test\design_system_migration_guard_test.dart`, and `git diff --check`.
- UI-UX-001, 2026-07-03: Figma route-gap retire sync now matches the code
  decision for frames without runtime contracts. `figma-use` renamed the active
  screen-page copies of `Data Workspace` and `FIFO Conversation Check` to
  `Retired / ...` and set `visible=false` for desktop/tablet/mobile nodes
  (`97:2`, `135:597`, `135:171`, `152:2715`, `152:626`, `151:466`), then
  verified `activeRetired: []` across `05 Mobile Screens`, `06 Tablet Screens`,
  and `07 Desktop Screens`. `design_system_migration_guard_test.dart` now locks
  that retire evidence in the gap map while still proving those routes stay
  absent from `app_router.dart`. Validation: focused
  `flutter test --no-pub --reporter expanded
  test\design_system_migration_guard_test.dart` (7 tests),
  `flutter analyze --no-pub`, and `git diff --check`.
- PROFILE-ADMIN-001/UI-UX-001, 2026-07-03: Personnel Catalog Admin now has a
  focused screen proof for the `/admin/personnel` runtime contract. The screen
  accepts an injected `AuthRepository` for tests while default runtime still
  uses `AuthRepository(ApiClient())`, renders content-only department/job-role
  tabs without `Scaffold`/`GradientHeader`, avoids the loading nested-scroll
  layout failure, and shows shared retryable error state on load failure.
  Validation: focused Personnel + design-system guard/router/nav/menu
  `flutter test --no-pub --reporter expanded
  test\personnel_catalog_admin_screen_test.dart
  test\design_system_migration_guard_test.dart test\app_router_test.dart
  test\app_nav_model_test.dart test\admin_menu_screen_test.dart` (22 tests),
  `flutter analyze --no-pub`, full `flutter test --no-pub --reporter compact`
  (296 tests), and `git diff --check`.
- UI-UX-001/FIFO-001/VIETQR-001/SALES-REPORT-001/WARRANTY-001, 2026-07-03:
  upgraded the shared scanner from `mobile_scanner` 5.2.3 to 7.2.0 and verified
  that its runtime format contract includes Code 128 and Data Matrix. The
  visible frame is now guidance while detection covers the full preview;
  Android requests `1280x720` analysis plus auto-zoom, Android/iOS support
  tap-to-focus, and logs record the detected format without raw values. The
  scanner UI now depends on `BarcodeScannerService`, with the `mobile_scanner`
  package isolated behind `MobileScannerBarcodeScannerService`. Android
  release build config was verified with minSdk 24, compile/target SDK 36,
  AGP 8.11.1, Gradle 8.14, Kotlin 2.2.20, JVM target 17, explicit CAMERA
  permission, and dependency graph alignment for Kotlin stdlib 2.2.20, ML Kit
  barcode scanning 17.3.0, Play Services ML Kit barcode scanning 18.3.1, and
  CameraX 1.5.3. Scanner guidance was synced and visually checked in Figma for
  Mobile (`151:611`), Tablet (`152:821`), and Desktop (`152:3267`).
  Validation: `flutter clean`, `flutter pub get`,
  `flutter pub outdated --no-transitive`, `flutter analyze`,
  `flutter test --reporter compact` (310 tests),
  `.\gradlew.bat :app:dependencies --configuration productionReleaseRuntimeClasspath`,
  and `flutter build apk --release --flavor production --verbose` with the
  production API/env dart-defines built
  `build\app\outputs\flutter-apk\app-production-release.apk` (92.2 MB).
  Gap: physical callback proof is still required for the supplied Code 128 and
  small Data Matrix labels, plus iOS/web camera smoke.
- UI-UX-001/FIFO-001/VIETQR-001/SALES-REPORT-001/WARRANTY-001, 2026-07-03:
  shared QR/barcode scanner no longer blocks web camera use. The scanner now
  treats web/mobile browsers as camera-capable through `mobile_scanner`, hides
  torch on web/unsupported desktop targets, keeps manual entry inside the
  camera screen for permission/no-camera fallback, and preserves Windows/Linux
  native manual fallback. All scan callers now go through the shared
  `showBarcodeScanner` navigation helper, preserving raw order-code mode with
  `parsePhongVuSku: false` for VietQR and Sales Report, and the migration guard
  blocks production callers from constructing `BarcodeScannerScreen` directly.
  Validation: focused scanner + guard
  `flutter test --no-pub --reporter expanded
  test\barcode_scanner_screen_test.dart test\design_system_migration_guard_test.dart`
  (25 tests), `flutter analyze --no-pub`,
  `flutter test --no-pub --reporter compact` (316 tests), and
  `git diff --check`. Android
  staging smoke on device `21081111RG` (Android 14) with build
  `2026.07.03.97+200097` verified the runtime permission prompt, camera grant,
  live preview/scan window, camera ID `0` owned by the staging package, and
  camera release after leaving the scanner. Gap: the camera did not see the QR
  test target, so physical decode/callback remains unverified; iOS camera smoke
  also remains manual.
- UI-UX-001, 2026-06-29: shared QR/barcode scanner now uses a smaller centered
  runtime `scanWindow` matching the visible frame, dims the outside area, keeps
  camera/manual/error copy Vietnamese, and logs scanner open/success/failure
  branches with sanitized context. Validation: focused scanner window unit test,
  `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded`,
  and `git diff --check`. Gap: physical Android camera smoke with real QR/barcode
  remains manual.
- PAYMENT-MONITOR-001, 2026-06-28: restored the Super Admin Home display for
  the speaker-speed/history pill by mounting the existing
  `PaymentDeliveryMetricsChip` in Home's custom header while keeping it hidden
  for non-Super Admin users and missing-provider test surfaces. Validation:
  focused Home widget test, focused delivery metrics chip/provider tests,
  `flutter analyze --no-pub`, and `git diff --check`.
- PAYMENT-MONITOR-001, 2026-06-27: expanded the Super Admin speaker-speed KPI
  chip into a history dialog. Backend now exposes a Super Admin-only
  `GET /payment-notifications/delivery-history` endpoint capped to 10-20 rows,
  joining delivery logs, notifications, and MAP transactions to return SR,
  amount, MAP first-seen time, `PLAYED` ack time, first-seen-to-played duration,
  and latest playback failure status/message when present. Flutter opens the
  dialog from the chip, keeps operational details selectable/copyable, and logs
  dialog/history load start/success/failure through `AppLogger`. Validation:
  focused backend payment notification Jest, focused Flutter repository/provider/
  widget tests, Flutter analyze, backend build, and `git diff --check`.
- PAYMENT-STATEMENT-001 / OFFSET-ADJUSTMENT-001, 2026-06-27: notification bell
  badges now count unread rows for the signed-in user instead of raw API totals.
  Opening or refreshing the global bell and the legacy `Sao kê` bell marks the
  visible notification ids as read through backend read receipts, persists a
  local fallback by environment/user, and reloads the global provider after
  `Sao kê` read-state changes so badge state does not stay stale across
  screens or devices. Validation: `npx prisma validate`, `npx prisma generate`,
  focused backend notification/MAP/offset Jest (60 tests), backend
  `npm run build`, full backend Jest (42 suites, 358 tests), focused Flutter
  notification/bank-statement provider and widget tests (30 tests),
  `flutter analyze --no-pub`, and full
  `flutter test --no-pub --reporter expanded` (179 tests),
  `dart format --output=none --set-exit-if-changed`, and `git diff --check`.
- PAYMENT-MONITOR-001, 2026-06-27: added Super Admin header KPI for speaker
  completion speed beside the global notification bell. Backend now logs each
  completed `PLAYED` acknowledgement with MAP first-seen-to-ack duration,
  exposes a Super Admin-only 24-hour delivery-metrics endpoint, and logs KPI
  load start/success/failure. Flutter loads the KPI only for Super Admin and
  shows the current average plus up/down delta versus the previous 24 hours.
  Validation: focused `payment-notifications` Jest (28 tests), backend
  `npm run build`, focused Flutter repository/provider/header tests (7 tests),
  `flutter analyze --no-pub`, full `flutter test --no-pub --reporter compact`
  (167 tests), and `git diff --check`.
- OFFSET-ADJUSTMENT-001 / PAYMENT-STATEMENT-001 / AUTH-001, 2026-06-27:
  shared notification bell now returns rejected `Cấn trừ` requests to the
  submitting SR through requester-scoped `NOTIFICATION` queries while reviewers
  keep seeing pending work; statement reviewers who are also requesters keep
  their own rejected statement notifications; Home no longer exposes logout in
  the header and moves `Đăng xuất` into the side menu with AppLogger coverage.
  Validation: `npx prisma validate`, focused backend Jest for MAP statement and
  offset adjustments (2 suites, 56 tests), backend `npm run build`, full
  backend Jest (41 suites, 348 tests), focused Flutter notification/Home tests
  (6 tests), `flutter analyze --no-pub`, full Flutter tests (164 tests), and
  `git diff --check`.
- PROFILE-ADMIN-001 / PAYMENT-MONITOR-001 / PAYMENT-STATEMENT-001,
  2026-06-29: added `Tiền vào` row-level order workflow reusing
  the existing `Sao kê` backend contract. Stored payment transactions now carry
  statement permission action flags, pending order-transfer state, and reviewer
  eligibility; Flutter parses those fields, shows the compact order editor on
  payment rows, supports direct save, Kế toán confirmation requests,
  approve/reject, and order history without adding export or checkbox selection
  to `Tiền vào`. Validation: focused MAP statement Jest, focused payment
  monitor Flutter model/provider/widget tests, bank-statement regression tests,
  `flutter analyze --no-pub`, backend `npm run build`, and `git diff --check`.
- PROFILE-ADMIN-001 / PAYMENT-MONITOR-001 / PAYMENT-STATEMENT-001,
  2026-06-26: added multi-showroom user assignments through
  `UserOrganizationAssignment`, admin create/update/import assignment sync,
  assigned-showroom scope for statement/payment MAP APIs, active-showroom speaker
  gating, SR chips on `Tiền vào`, shared dropdown filters/date-range controls,
  staff-facing `dd/mm/yyyy` date input formatting, app-wide route content
  selection, synced notification icon buttons, and MAP night sync at a
  30-minute cadence while preserving `MAP_VIETIN_SYNC_ENABLED=false` as the
  full stop switch. Validation: `npx prisma validate`, `npx prisma generate`,
  backend `npm run build`, focused backend Jest for user/MAP/payment
  notifications (3 suites, 111 tests), focused Flutter payment monitor tests,
  `flutter analyze --no-pub`, full `flutter test --no-pub` (152 tests), and
  `git diff --check`. Gap: live database migration, admin multi-SR click-through,
  Windows speaker active-SR smoke, and staging/prod deploy smoke remain manual.
- OFFSET-ADJUSTMENT-001, 2026-06-25: added the dedicated `Cấn trừ` feature for
  SR-created offset adjustment requests and ACC/FIN_ACC review. The backend now
  stores request/history rows, blocks same old/new order codes for single-order
  requests, blocks duplicate wallet order/transaction codes per wallet type,
  requires reject reasons, and requires `Mã CT` only when completing VNPAY
  QROFF. Flutter adds the home route, four entry dialogs, detail/review dialog,
  server-side filters, status borders, single-order reuse count chip, and
  offset realtime refresh. Realtime is isolated on Redis channel
  `OFFSET_ADJUSTMENT_UPDATED` and WebSocket event
  `OFFSET_ADJUSTMENT_NOTIFICATION`; payment notification ready/audio/ack
  contracts remain on their existing paths and event types. Validation:
  `npx prisma validate`, `npx prisma generate`, focused backend Jest for
  offset/auth/feature/payment notification (4 suites, 56 tests), backend
  `npm run build`, Go realtime `go test ./...`, focused Flutter offset/user/
  payment monitor tests (31 tests), `flutter analyze --no-pub`, and
  `git diff --check`. Gap: live database migration, deployed Redis/WebSocket
  delivery, ACC/SR click-through, and the manual runtime smoke with `Tiền vào`
  speaker enabled remain pending.
- PAYMENT-STATEMENT-001, 2026-06-26: changed statement order-transfer request
  cutoff from a rolling 24-hour window to the Vietnam-local transaction day,
  auto-expires stale pending requests after 00:00 UTC+7, opens the generic
  `Thông báo` bell for reviewers and requesters, adds transaction/request
  timestamps to notification/review UI, supports optional rejection notes, and
  returns rejected notifications to the requester with next-step guidance.
  Validation: `npx prisma validate`, `npx prisma generate`, focused
  `npm test -- --runInBand src/map-vietin/map-vietin.service.spec.ts` (46
  tests), `npm run build`, Go realtime `go test ./...`, focused Flutter bank
  statement/header tests (23 tests), `flutter analyze --no-pub`, and
  `git diff --check`. Gap: live deployed DB migration plus Redis/WebSocket
  notification delivery remain pending.
- PAYMENT-STATEMENT-001, 2026-06-29: added an independent `Mã sao kê` primary
  filter to `Sao kê`. It searches the displayed statement reference and falls
  back to MAP transaction number. Validation: focused Flutter bank statement
  provider/screen tests (24 tests), focused MAP statement Jest (54 tests),
  `flutter analyze --no-pub`, backend `npm run build`, and `git diff --check`.
- PAYMENT-STATEMENT-001, 2026-07-01: statement number, order code, exact amount,
  and transfer-content searches now scan all stored statement accounts instead
  of being limited to the user's assigned showroom; showroom/date/status-only
  searches remain scoped. Selected-row CSV export keeps the same global lookup
  filter so visible out-of-showroom rows can be exported without allowing raw id
  guessing. Validation: focused Flutter bank statement provider tests (23
  tests), focused MAP statement Jest (59 tests), `flutter analyze --no-pub`,
  backend `npm run build`, and `git diff --check`.
- PROFILE-ADMIN-001, 2026-06-26: changed `Quản lý người dùng` text search to
  local filtering over the loaded user list, while backend reloads are reserved
  for filter changes or manual refresh; role/feature/scope-tree metadata is
  cached after first load. Validation: `flutter analyze --no-pub`, focused
  Flutter bank statement/header regression tests (23 tests), and
  `git diff --check`. Gap: live admin-user typing smoke remains manual.
- PAYMENT-STATEMENT-001, 2026-06-25: added ACC-reviewed statement order
  transfer requests. Visible statement users can request order replacement
  within 24 hours from `paidAt ?? firstSeenAt`; duplicate pending requests and
  over-24h requests are blocked; `SUPER_ADMIN`, `FIN_ACC`, and `ACC`
  department/org-node users can approve or reject. Pending rows use yellow
  border and `Chờ ACC xác nhận`; approved rows replace orders, write order
  audit with source `OFFSET`, and show `Đã cấn trừ`; status filters now include
  `Chờ xác nhận` and `Giao dịch cấn trừ`; ACC users receive a scoped
  notification bell backed by sanitized Redis/WebSocket events. Validation:
  `npx prisma validate`, `npx prisma generate`, focused MAP statement service
  Jest (43 tests), backend `npm run build`, Go realtime `go test ./...`,
  focused Flutter provider/widget tests (20 tests), `flutter analyze --no-pub`,
  and `git diff --check`. Gap: live DB migration, deployed Redis/WebSocket
  delivery, and ACC click-through remain manual.
- OFFSET-ADJUSTMENT-001, 2026-06-26: fixed reviewer notification bell behavior
  so it opens a pending-review list instead of changing the main filter/search,
  switched SR filtering to searchable multi-select, kept empty date range as
  `Tất cả ngày`, added calendar pickers beside manual date inputs, and added
  CSV export by all types or a selected offset type. Also added an in-row
  statement approval button for pending order-transfer requests when the user
  has review access. Validation: focused backend offset Jest, focused Flutter
  offset/bank-statement widget tests, backend `npm run build`,
  `flutter analyze --no-pub`, and `git diff --check`.
- PROFILE-ADMIN-001 / PAYMENT-STATEMENT-001, 2026-06-24: tightened user
  import/create/delete and statement-order edit permissions. `SUPER_ADMIN` is
  now required for admin user creation/import, imports validate email syntax and
  allowed domains before any write, newly created users receive welcome email
  guidance for first password setup, SMTP failure is reported without rolling
  back creation, and locked-user hard delete is blocked for active/self/
  `SUPER_ADMIN`/history-backed accounts. Statement order edits now allow
  non-FIN users to fill only currently empty orders; existing AUTO/MANUAL orders
  can be edited only by `SUPER_ADMIN` or `FIN_ACC`, while existing showroom
  scope remains unchanged. Validation: `npx prisma validate`, focused backend
  user/import/MAP statement Jest (3 suites, 83 tests), backend `npm run build`,
  full backend `npm test -- --runInBand` (39 suites, 317 tests), focused
  Flutter bank statement provider test (15 tests), full Flutter
  `flutter test --no-pub --reporter expanded` (142 tests), `flutter analyze
  --no-pub`, and `git diff --check`. Gap: live SMTP delivery, user-admin
  click-through, and Windows statement UI smoke remain manual.
- AUTH-002, 2026-06-24: forgot-password now returns an explicit not-found
  response when an allowed-domain email has no OpsHub account, and Flutter shows
  a `Chưa có tài khoản` dialog with a `Đăng ký tài khoản` action that opens
  registration with the email prefilled instead of advancing to reset-code
  entry. The flow logs missing-account dialog shown, register navigation, and
  dismiss decisions through `AppLogger`; backend keeps logging the missing-email
  reset request without sending mail. Validation: focused backend auth/password
  reset Jest (`src/auth/password-reset.service.spec.ts`,
  `src/auth/auth.service.spec.ts`, `src/auth/auth.controller.spec.ts`; 3 suites,
  40 tests), backend `npm run build`, focused Flutter auth tests
  (`test\auth_device_info_test.dart`, `test\forgot_password_screen_test.dart`;
  6 tests), rerun of the focused forgot-password widget test after lint fix,
  `flutter analyze --no-pub`, and `git diff --check`. Gap: live SMTP delivery
  and deployed app click-through remain manual.
- HOME-SUPPORT-001, 2026-06-24: Home header now shows a `Hỗ trợ` icon that
  opens the Seatalk support group QR asset and invite link without changing the
  Home feature-tile order. The flow logs dialog requested/shown/closed plus
  link-open start/success/failure through `AppLogger` with sanitized host/path
  context. Validation: focused Home widget tests
  (`test\home_feedback_action_test.dart`, `test\home_avatar_test.dart`),
  `flutter analyze --no-pub`, and `git diff --check`. Gap: live Seatalk app
  handoff remains manual.

- UPDATE-003, 2026-06-24: added deploy-triggered realtime update discovery while
  keeping public `/app-version` as the authority. NestJS publishes sanitized
  Android/Windows build metadata to Redis after startup; Go relays only update
  events to unauthenticated `/ws/app-updates` clients; Flutter reconnects with
  backoff and re-checks HTTP metadata on an event, successful connection, app
  resume, or metadata retry before rendering the existing update prompt. Logs
  cover publish/connect/event/check/retry success and failure without tokens or
  sensitive payloads. 2026-07-03 live staging smoke published
  `APP_VERSION_UPDATED` through Redis and proved both raw public WebSocket
  delivery and deployed Flutter web recheck: Chrome CDP saw `/ws/app-updates`,
  the `APP_UPDATE` smoke frame, and one follow-up
  `/api/app-version?platform=web` request with console/runtime errors at 0.
  Validation: focused update-gate widget tests (7), full Flutter tests (139),
  `flutter analyze --no-pub`, Windows release build, Android production-debug
  APK build, focused app-version Jest (5), NestJS build, full backend Jest
  (39 suites, 308 tests), `go test ./...`, and live staging
  Redis/WebSocket/browser smoke. Live smoke reused current metadata to avoid a
  staff-disrupting forced update; visible forced-prompt UI remains covered by
  widget/local update-gate tests. Previously installed clients gain realtime
  behavior only after installing this first realtime-enabled build.

- PAYMENT-STATEMENT-001, 2026-06-25: inline statement order editing now renders
  existing multiple order codes one per line and accepts newline-separated saves
  alongside comma/semicolon/whitespace input. CSV export preserves long numeric
  order codes as Excel text and emits multiple order codes as line breaks inside
  the `Mã đơn hàng` cell. Validation: focused statement provider tests (16
  tests), focused MAP statement service tests (36 tests), and `git diff
  --check`. Gap: opening a live exported CSV in Excel remains manual.
- PAYMENT-STATEMENT-001, 2026-06-24: statement CSV export now reads MAP
  `rawData.txnReference` into a `Sao kê` column without adding a duplicate
  database column. The value is emitted as Excel text so leading zeroes and long
  numeric references remain intact; export logs start/success/failure plus row
  and populated-reference counts without logging reference values. Validation:
  focused MAP statement Jest (32 tests), NestJS build, full backend Jest
  (39 suites, 306 tests), and `git diff --check`. Gap: the configured local
  database contains only seed rows without `txnReference`; production payload
  presence and opening a live exported CSV in Excel remain unverified.
- PAYMENT-MONITOR-001, 2026-06-23: added an opt-in fixed-prefix payment audio
  trial through `PAYMENT_TTS_AUDIO_MODE=amount_only_with_prefix` plus
  `PAYMENT_PREFIX_WAV_PATH` and optional `PAYMENT_CUE_PREFIX_WAV_PATH`. When
  the compatible prefix WAV exists, backend TTS receives only the dynamic amount
  text and playback/download paths rejoin the fixed prefix; `includeCue=true`
  now prefers the prejoined cue+prefix WAV before appending the amount audio.
  Amount WAVs are cached by text/voice/speed/pitch and newer clients first
  request `rawAmount=true`, trim zero padding, join bundled
  `data/payment-cue-prefix.wav` to the downloaded amount with an 80 ms gap, and
  play one WAV. Incompatible PCM formats fall back to sequential playback, and
  missing prefix assets fall back to the
  existing full-sentence TTS path, and TTS/cache generation logs mode, cache
  source, text length, bytes, MIME type, and duration.
  The prefix WAV was generated by the production Piper sidecar on `hoang-n8n`;
  prefix and cue+prefix WAVs were installed at `/srv/opshub/import/`, and
  `/srv/opshub/env` now points the API container to both `/data/import` paths.
  Validation: focused payment-notification Jest (24 tests), full backend Jest
  (39 suites, 306 tests), NestJS build, focused Flutter repository/provider/
  speaker tests, Flutter analyze, `git diff --check`, dist asset copy
  inspection, and WAV header inspection
  (`payment-prefix.wav` 82,502 bytes/about 1.87s; `payment-cue-prefix.wav`
  154,550 bytes/about 3.50s; both mono/22050Hz/16-bit). Gap: new-code deploy
  and physical Windows speaker smoke remain pending.
  2026-06-24 follow-up: local client joining removes 420 ms of the prefix's
  500 ms zero tail, preserves an exact 80 ms phrase gap, trims amount leading
  zero padding, and avoids opening the player twice. Validation: direct Dart
  smoke against the production-format assets (`gapMs=80`,
  `prefixTrimMs=420`, combined 239,618 bytes), focused payment monitor/speaker/
  WAV tests (30 tests), full Flutter tests (135 tests),
  `flutter analyze --no-pub`, Windows release build, and `git diff --check`.
  Gap: physical
  Windows speaker playback remains pending.
- PLATFORM-001, 2026-06-22: production and staging workflows now serialize
  deploys, use GitHub Environments, and pin checkout, Flutter, and Tailscale
  actions to immutable commits. Added public-cutover/environment-secret
  runbooks plus PowerShell helpers that generate secret bundles only outside
  the repo and tighten their local ACLs. Validation: production/staging workflow
  YAML parse, PowerShell parser checks, live read-only confirmation that both
  environments contain 12 secret names, staged `gitleaks` scan with no findings,
  full project validation, and `git diff --check`. Gap: staging and production
  workflow smoke remain pending.
- PROFILE-ADMIN-001, 2026-06-22: policy rule create/edit is now tree-only and
  requires an organization node. Legacy selectors remain readable for old
  rules but are rejected on write; the Flutter editor logs blocked saves and
  create/update outcomes through `AppLogger`. Validation: focused policy and
  feature-guard coverage within full Flutter/backend suites, `flutter analyze
  --no-pub`, full Flutter tests (109 tests), NestJS build, full NestJS tests
  (38 suites, 294 tests), Go realtime tests, and `git diff --check`. Gap: live
  policy-admin click-through remains manual.
- PAYMENT-STATEMENT-001, 2026-06-22: `BANK_STATEMENT_ALL_SCOPE` now grants the
  bank-statement route, backend feature-guard fallback, statement APIs, and
  all-showroom selection without requiring the base feature or a manager role.
  Validation: focused Flutter/backend coverage within full suites, Flutter
  analyze/tests, NestJS build/tests, Go tests, and `git diff --check`. Gap:
  live finance-user Windows click-through remains manual.
- PAYMENT-MONITOR-001, 2026-06-23: production payment audio now applies
  `PAYMENT_CUE_GAIN=0.80` only to the server cue, uses a gain-versioned combined
  WAV cache, and removes both legacy and gain-versioned cache files on expiry.
  Piper defaults and the systemd unit use `PIPER_LEADING_SILENCE_MS=0` while
  preserving the 500ms tail, so speech joins the quieter cue without a
  configured gap. The Windows local fallback uses cue volume `80%` and voice
  volume `100%`. Validation: focused payment-notification Jest (20 tests),
  focused Flutter speaker tests (3 tests), full NestJS Jest (38 suites, 295
  tests), full Flutter tests (123 tests), NestJS build, Flutter analyze, Python
  compile, focused Piper padding unittest, and `git diff --check`. Gap:
  production sidecar/API rollout and physical Windows speaker smoke remain
  pending.
- PAYMENT-MONITOR-001, 2026-06-23: `Tiền vào` now preserves MAP payer name and
  account fields in the Flutter transaction model, shows the payer summary on
  each card, and opens a selectable full-detail dialog when the card is tapped.
  AppLogger records detail open/close/failure using sanitized identifiers only.
  Validation: focused payment transaction model/widget tests (5 tests),
  `flutter analyze --no-pub`, full Flutter tests (121 tests), and
  `git diff --check`. Gap: live Windows MAP transaction click-through remains
  manual.
- PAYMENT-STATEMENT-001, 2026-06-23: `Sao kê` now shows the MAP payer
  name/account in each transaction summary and opens a selectable full-detail
  dialog from that summary without changing checkbox selection or inline order
  actions. The dialog includes payment, showroom, order, manual-edit, and
  first-seen metadata; AppLogger records open/close/failure with sanitized
  context. Validation: focused statement provider/detail tests (13 tests),
  `flutter analyze --no-pub`, full Flutter tests (122 tests), and
  `git diff --check`. Gap: live Windows statement click-through remains manual.
- PAYMENT-STATEMENT-001, 2026-06-23: `Sao kê` now pages statement results from
  the backend instead of fetching a full client snapshot, keeps selected
  transaction ids across page changes, exports selected ids when present, and
  blocks CSV export ranges over 31 days in both Flutter and the statement API.
  Validation: focused statement provider tests (14 tests), focused MAP
  statement service tests (30 tests), `flutter analyze --no-pub`,
  `npm run build`, and `git diff --check`. Gap: live Windows statement
  click-through remains manual.
- PAYMENT-MONITOR-001, 2026-06-22: server-combined payment audio now preserves
  the full Piper-generated TTS WAV when appending it after `payment-cue.wav`,
  including Piper's configured 650ms leading silence and 500ms tail silence, so
  long amount announcements keep the original voice ending. The combined-audio
  log now records `voiceDataBytes` instead of trim window settings. Validation:
  focused backend coverage within the full NestJS suite (38 suites, 294 tests),
  NestJS build, full Flutter analyze/tests (109 tests), Go tests, and
  `git diff --check`.
- PROFILE-ADMIN-001, 2026-06-15: fixed production deploy boot failure in
  org-tree legacy catalog sync when existing Lv2/Lv3 organization nodes have
  blank display names. The sync now falls back to node name/business code and
  logs the fallback instead of crashing `onModuleInit`; the deploy workflow
  now emits container diagnostics and rolls back to the last healthy release
  when backend health fails. Validation in current patch: focused backend
  `user.service.spec.ts` (38 tests), backend `npm run build`, full backend
  `npm test -- --runInBand` (37 suites, 285 tests), and `git diff --check`.
- PROFILE-ADMIN-001, 2026-06-15: fixed moving an Lv4 showroom under a newly
  created Lv3 area node from the organization tree. Backend now syncs the
  ancestor Lv2/Lv3 legacy Region/Area rows inside the same transaction before
  updating Store/User location fields, avoiding the previous 500 from missing
  legacy area references. Validation in current patch: focused backend
  `user.service.spec.ts`, backend `npm run build`, full backend
  `npm test -- --runInBand`, and `git diff --check`.
- PAYMENT-MONITOR-001, 2026-06-15: increased server-combined payment audio
  tail silence from 150ms to 300ms and logs the combined-audio leading/tail
  silence settings when generating cached cue+TTS WAV files. Validation in
  current patch: focused backend `payment-notifications.service.spec.ts`,
  backend `npm run build`, full backend `npm test -- --runInBand`, and
  `git diff --check`.
- PROFILE-ADMIN-001, 2026-06-15: restored full Lv0-Lv5 organization-node
  creation in the admin org-tree editor/API. The node type dropdown again
  exposes Lv1/Lv2/Lv3 options, parent validation uses level ordering instead
  of a root-showroom-only allowlist, and manual org-tree create/update no
  longer syncs or blocks on legacy Region/Area/Department/JobRole catalogs.
  Lv4 showroom nodes still sync Store runtime metadata for QR/MAP/payment
  behavior. Validation in current patch: focused backend
  `user.service.spec.ts` (36 tests), backend `npm run build`, focused Flutter
  `admin_user_tree_scope_test.dart` (7 tests), `flutter analyze --no-pub`, and
  `git diff --check`.
- PROFILE-ADMIN-001, 2026-06-15: fixed scoped admin user listing for store
  managers assigned to Lv5 position nodes. Admin data scope now lifts a direct
  Lv5 position under a Lv4 showroom to the owning showroom subtree for user and
  store management, so accounts such as `hoang.nv1@phongvu-mna.vn` can see all
  staff in their managed showroom instead of only users assigned to the same
  Lv5 position. Validation in current patch: focused backend
  `user.service.spec.ts` (36 tests), backend `npm run build`, and
  `git diff --check`.
- PAYMENT-MONITOR-001/PROFILE-ADMIN-001, 2026-06-15: split payment speaker
  access into node feature `PAYMENT_SPEAKER` (`Đọc loa`) under
  `PAYMENT_MONITOR`. `PAYMENT_MONITOR` keeps the transaction view and realtime
  refreshes, while `PAYMENT_SPEAKER` controls ready notification polling, audio
  streaming, and speaker ack on supported Windows PCs. The rollout backfills
  `PAYMENT_SPEAKER` only for Lv5 `STORE_MANAGER`/`CASH` node groups that
  already have `PAYMENT_MONITOR`; other node groups can receive speaker access
  by assigning `Đọc loa` directly. Mobile/non-Windows still do not start the
  speaker path by default. Validation in current patch: `npx prisma validate`,
  focused backend `feature.service` + `payment-notifications.service` Jest (32
  tests), backend `npm run build`, `flutter analyze --no-pub`, focused Flutter
  `payment_monitor_provider_test.dart` (15 tests), and `git diff --check`.
- PAYMENT-MONITOR-001, 2026-06-15: added opt-in server-side combined payment
  audio. `GET /payment-notifications/:id/audio` remains TTS-only for older
  clients, while `includeCue=true` returns one cached WAV containing
  `payment-cue.wav` plus Piper TTS when the source audio is WAV. Legacy
  non-WAV audio or missing cue assets return a clear error so the Flutter
  client falls back to TTS-only download plus local `data/ting_ting.mp3`.
  Flutter now logs and plays either `server_combined_cue` without local cue or
  `local_cue_fallback` with local cue. Validation in current patch: cue WAV
  inspected as PCM 16-bit mono 22050 Hz, focused backend
  `payment-notifications` Jest (19 tests), focused Flutter payment monitor /
  repository / speaker tests, backend `npm run build` with cue asset copied to
  `dist`, `go test ./...`, `flutter analyze --no-pub`, full Flutter
  `flutter test --no-pub --reporter compact` (102 tests), Windows release
  build with production API define, `git diff --check`, and local combined WAV
  smoke sample generated under `build/tts-tests/`. Gap: physical Windows
  speaker smoke on production artifact remains manual.
- PAYMENT-MONITOR-001/UPDATE-001, 2026-06-15: changed the payment monitor from
  5-second transaction polling to realtime payment-notification events with a
  30-second fallback refresh. Initial/manual/page/date loads still request a
  total count, while realtime/fallback refreshes send `includeTotal=false` to
  skip the count query. Flutter added a manual icon-only refresh action,
  debounced/coalesced realtime refreshes, and keeps muted speakers from
  downloading audio while acknowledging ready notifications as `SILENCED`.
  Backend added the lightweight transaction-list contract and a delivery-log
  index for `clientId/storeCode/event/createdAt`. Piper TTS leading silence is
  now 650ms with 500ms tail silence, and the client asset
  `data/ting_ting.mp3` remains bundled for full production client builds.
  Validation in current patch: focused Flutter payment monitor test,
  focused backend map-vietin/payment-notifications Jest, `npx prisma validate`,
  `npx prisma generate`, backend `npm run build`, `go test ./...`,
  `python -m py_compile deploy/home-server/tts-piper/app.py`,
  `flutter analyze --no-pub`, full Flutter
  `flutter test --no-pub --reporter compact` (101 tests), Windows
  release build with production API define, and matching SHA256 for
  `data/ting_ting.mp3` in the release `flutter_assets` bundle. Gap: live
  production artifact endpoint checks and physical Windows speaker smoke remain
  manual.
- PAYMENT-MONITOR-001, 2026-06-30: production enabled
  `PAYMENT_SPEAKER_STREAMING_ENABLED=true` so new payment notifications publish
  `PAYMENT_SPEAKER_STREAM` before waiting on server TTS. Flutter reduces the
  missed-event fallback refresh from 30 seconds to 10 seconds, reconnects the
  payment-monitor WebSocket after disconnects, and drains up to five ready
  notification batches in one poll so a speaker PC with backlog does not wait
  for later fallback ticks. Validation in current patch: focused Flutter
  `payment_monitor_provider_test.dart`, Flutter analyze, and `git diff --check`.
- PAYMENT-MONITOR-001, 2026-07-01: fixed overlapping speaker playback when a
  repeated `PAYMENT_SPEAKER_STREAM` event and fallback `/ready` refresh raced
  for the same transaction. Stream audio requests now pass `clientId`, backend
  records stream opens as `DELIVERED` claims, `/ready` excludes recent
  `DELIVERED`/`STREAM_STARTED` in-flight rows for that client, and Flutter
  skips notification ids that are already queued or actively playing. Validation
  in current patch: focused Flutter payment monitor/repository tests, focused
  backend payment-notifications Jest, backend `npm run build`, and
  `git diff --check`.
- PROFILE-ADMIN-001, 2026-06-13: changed runtime feature access from per-user
  allowlists to direct organization node-group assignments. Backend added
  `OrganizationNodeFeatureAssignment`, migration preflight/backfill, read-only
  audit script, `/admin/features/node-assignments` APIs, node-group
  `/features/me` resolution, and user-list feature filtering through node
  assignments. Flutter added node assignment management in feature management
  and organization tree, removed the user-editor feature picker, and stopped
  sending user `featureTreeCodes`. Validation: `npx prisma validate`,
  `npx prisma generate`, `node --check
  scripts/audit-node-feature-permissions.mjs`, backend `npm run build`,
  focused backend user/feature Jest (3 suites, 44 tests), full backend `npm
  test -- --runInBand` (36 suites, 262 tests), focused Flutter admin user tree
  test, `flutter analyze --no-pub`, full Flutter `flutter test --no-pub
  --reporter expanded` (97 tests), and `git diff --check`. Follow-up
  2026-06-13: staging deploy exposed a legacy orphan user with enabled
  per-user features but no active direct organization node. The migration now
  still blocks divergent node groups, but reports and skips orphaned users from
  backfill, and the staging deploy workflow auto-resolves the stale failed
  migration state for this exact migration when the target table was never
  created. Follow-up 2026-06-14: deploy compose now scopes runtime env per
  service so app-version metadata only changes the API container config, while
  Postgres/realtime/Caddy use explicit environment keys; staging/prod workflows
  wait for recreated app services and verify API app-version env before public
  metadata smoke. SSH heredoc deploy commands route Docker Compose through a
  stdin-closed helper so Compose cannot consume the rest of the remote script.
  Gap: staging/prod must run `npm run audit:node-features` against live data
  before migration, and live admin UI plus `/features/me` smoke remains manual.
- PAYMENT-MONITOR-001, 2026-06-23: split payment monitor list access from the
  Windows-only speaker capability. Android/non-web clients with
  `PAYMENT_MONITOR` now see the `Tiền vào` Home action and load stored
  transactions, while `PAYMENT_SPEAKER` audio polling/download/ack remains
  Windows-only. Validation: focused Flutter
  `flutter test --no-pub test\app_platform_capabilities_test.dart test\home_feedback_action_test.dart test\payment_monitor_provider_test.dart test\payment_monitor_unsupported_screen_test.dart --reporter expanded`.
  Gap: live Android APK click-through remains manual.
- WARRANTY-001/FEEDBACK-001, 2026-06-23: raised the shared image upload limit
  from 10 to 20 files for warranty image save and staff feedback attachments.
  Flutter now caps warranty picker selections at 20 before submitting, feedback
  UI copy matches 20, and NestJS warranty/feedback multipart interceptors use
  the shared backend limit. Validation: focused backend Jest
  `npm test -- --runInBand src/upload/image-upload.options.spec.ts src/upload/upload.controller.spec.ts src/feedback/feedback.controller.spec.ts`,
  backend `npm run build`, focused Flutter
  `flutter test --no-pub test\feedback_screen_test.dart test\warranty_upload_contract_test.dart --reporter expanded`,
  `flutter analyze --no-pub`, and `git diff --check`. Gap: live device
  picker/upload smoke remains manual.
- WARRANTY-001, 2026-06-13: fixed warranty image upload failing with
  `property user should not exist` by aligning the Flutter multipart payload
  with the Nest `UploadWarrantyImagesDto`; the client now sends only `receipt`,
  and the backend tolerates the legacy `user` field for installed clients while
  continuing to resolve the creator from the authenticated JWT user. Validation:
  focused Flutter
  `flutter test --no-pub test\warranty_upload_contract_test.dart --reporter expanded`,
  focused backend upload Jest
  `npm test -- --runInBand src/upload/upload.dto.spec.ts src/upload/upload.controller.spec.ts src/upload/upload.service.spec.ts`,
  backend `npm run build`, full backend `npm test -- --runInBand` (36 suites,
  261 tests), `flutter analyze --no-pub`, full Flutter
  `flutter test --no-pub --reporter expanded` (96 tests), and `git diff
  --check`. Gap: live authenticated upload smoke remains pending.
- AUTH-001, 2026-06-15: removed Flutter-side bundled-domain gating from login,
  registration-code, registration, and forgot-password email validation so
  `AUTH_ALLOWED_EMAIL_DOMAINS` remains the backend source of truth. Login also
  stops applying password-strength policy before auth, and only requires a
  non-empty password so existing valid accounts can reach the backend credential
  check. This fixes runtime domains such as `phongvu-mna.vn` being rejected
  before `/auth/login` or related public auth endpoints are called. Validation:
  focused Flutter
  validators/auth repository tests (`flutter test --no-pub test/validators_test.dart
  test/auth_device_info_test.dart`), focused backend auth/policy domain tests
  (`npm test -- --runInBand src/auth/auth.service.spec.ts
  src/policy/policy.service.spec.ts src/auth/email-domain-policy.spec.ts`),
  `flutter analyze --no-pub`, backend `npm run build`, and `git diff --check`.
- AUTH-001/PROFILE-ADMIN-001, 2026-06-13: changed registration/login so new
  users do not self-select SR/store. Auth/profile responses now expose
  `assignmentPending`; Flutter routes pending users to `/assignment-pending`
  with the approved support message, refresh, and logout actions. The retired
  `/users/me/select-store` API returns `410 Gone`. Admin user editing removes
  direct department/job-role rows and replaces the old node dropdown with a
  searchable, filtered, breadcrumb-based organization picker. Feature taxonomy
  adds `ADMIN_ORG_TREE`, moves org-tree route/menu guards to it, hides legacy
  `ADMIN_STORES` and `ADMIN_REGIONS` from the picker, and backfills
  assignments/rules from `ADMIN_REGIONS`. `ADMIN_PERSONNEL` was re-exposed in
  the 2026-07-03 redesign follow-up as `Danh mục nhân sự`. Validation: `npx prisma
  validate`, `npx prisma generate`, backend `npm run build`, full backend `npm
  test -- --runInBand` (35 suites, 256 tests), `flutter analyze --no-pub`, full
  Flutter `flutter test --no-pub --reporter expanded` (87 tests), and `git diff
  --check`. Gap: manual staging smoke for register -> pending -> admin assign
  -> refresh/login remains pending.
- PROFILE-ADMIN-001/PERSONNEL-001/PAYMENT-MONITOR-001, 2026-06-13: backfilled
  every Lv4 store with five fixed Lv5 position nodes (`STORE_MANAGER`, `SA`,
  `TECHNICIAN`, `CASH`, `WAREHOUSE`) and creates them automatically for new
  stores. Backend user assignment keeps the selected Lv5 node as
  `organizationNodeId`, derives legacy personnel codes from the tree, and syncs
  compatibility job-role catalog rows without changing SR identity/payment/MAP
  fields. Payment speaker ready/audio/ack is now controlled by the separate
  node feature `PAYMENT_SPEAKER` (`Đọc loa`) on supported Windows PCs; users
  with only `PAYMENT_MONITOR` keep transaction list/realtime refresh access but
  do not poll, stream, or ack speaker audio. Rollout backfills `PAYMENT_SPEAKER`
  only for active Lv5 `STORE_MANAGER`/`CASH` node groups that already have
  `PAYMENT_MONITOR`. Validation in current patch: `npx prisma
  validate`, `npx prisma generate`, backend `npm run build`, focused backend
  feedback/payment Jest (3 suites, 19 tests), full backend
  `npm test -- --runInBand` (35 suites, 259 tests), `flutter analyze --no-pub`,
  focused Flutter feedback/payment monitor tests, full Flutter
  `flutter test --no-pub --reporter expanded` (91 tests), and `git diff
  --check`. Gap: live staging smoke remains pending.
- PROFILE-ADMIN-001/PERSONNEL-001, 2026-06-12: changed organization
  administration to the Lv0-Lv5 source-of-truth tree. Backend normalizes active
  org node types to `LV0_DOMAIN`, `LV1_BLOCK`, `LV2_DEPARTMENT`,
  `LV2_REGION`, `LV3_AREA`, `LV3_UNIT`, `LV4_STORE`, and `LV5_POSITION`,
  allows skipped-level parent links, retires active subdomain responses,
  derives legacy scope fields from `organizationNodeId`, keeps SR/store runtime
  data compatible, and returns `410 Gone` for legacy `/admin/regions`,
  `/admin/areas`, and `/admin/stores`. System roles are fixed to
  `SUPER_ADMIN`, `ADMIN`, and `USER`, with rollout aliases normalized for old
  tokens/imports. Flutter removes legacy Region/Area/SR admin screens, makes
  role management read-only, sends tree-only user assignment payloads, keeps
  feature/policy rule editors tree-first, and logs changed admin/store-selection
  flows. Validation in current patch: `npx prisma validate`, `npx prisma
  generate`, backend `npm run build`, focused backend user/auth/feature/policy
  Jest (4 suites, 67 tests), focused FIFO regression (14 tests), full backend
  `npm test -- --runInBand` (35 suites, 250 tests), focused Flutter user
  tree-scope test (4 tests), `flutter analyze --no-pub`, full Flutter
  `flutter test --no-pub --reporter expanded` (84 tests), and `git diff
  --check`. Gap: live staging smoke remains manual.
- PROFILE-ADMIN-001/AUTH-002, 2026-06-15: added Excel-based admin user import
  through `POST /admin/users/import` guarded by `ADMIN_USERS`. The import
  accepts the `user_temp.xlsx` header contract, resolves `lv0`-`lv5` values by
  active organization node `code`/`businessCode`, assigns the deepest matched
  node, creates passwordless users, upserts existing users without changing
  passwords, and keeps first-password setup on the in-app forgot-password
  email-code flow. Validation in current patch: `npx prisma validate`, backend
  `npm run build`, full backend `npm test -- --runInBand` (37 suites, 280
  tests), `flutter analyze --no-pub`, and full Flutter
  `flutter test --no-pub --reporter expanded` (103 tests), plus
  `git diff --check`.
- PROFILE-ADMIN-001, 2026-06-12: fixed organization node creation for Region
  nodes under Block parents such as `Kinh Doanh`. Backend parent validation now
  allows `REGION` under `BLOCK`, preserves existing showroom-under-block trees,
  and regression-covers creating `HCM-BD` under a block. Flutter organization
  node payloads now send showroom-only fields only for `SHOWROOM` nodes, filter
  parent choices by selected node type, use the prepared body for both create
  and update, and show backend `ApiException.message` instead of a generic save
  failure. Validation: focused backend user Jest, focused Flutter admin tree
  test, backend `npm run build`, `flutter analyze --no-pub`, full Flutter
  `flutter test --no-pub --reporter expanded` (84 tests), full backend Jest
  (35 suites, 250 tests), and `git diff --check`.
- PROFILE-ADMIN-001, 2026-06-12: changed user feature assignment and admin
  rule editing to tree-first payloads. Flutter user management now sends
  `featureTreeCodes` from the feature tree instead of `featureCodes`; backend
  create/update user accepts `featureTreeCodes`, expands selected child feature
  nodes to include ancestors, and keeps legacy `featureCodes` as a
  compatibility fallback. Feature-rule and policy-rule editors in the app now
  use organization tree nodes instead of legacy Region/Area/SR selectors, while
  preserving display/backfill support for old rules. Policy settings validation
  now accepts JSON arrays as well as objects so array-valued settings can be
  saved. Validation: focused backend user/feature/policy Jest (5 suites, 48
  tests), focused Flutter admin tests (9 tests), backend `npm run build`,
  `flutter analyze --no-pub`, full backend `npm test -- --runInBand` (35
  suites, 249 tests), and full `flutter test --no-pub --reporter expanded`
  (83 tests). Gap: live staging click-through for saving user feature
  assignments, feature/policy rules, and settings remains manual.
- PROFILE-ADMIN-001, 2026-06-13: policy management now loads organization
  scope nodes through an `ADMIN_POLICIES`-guarded scope tree endpoint instead
  of requiring `ADMIN_ORG_TREE`; policy runtime context prefers the user's
  assigned `organizationNodeId` before showroom fallback so Lv5 policy rules
  match tree-assigned users; the Flutter policy rule editor uses a searchable
  tree node picker for single-rule edit and batch creation.
- PROFILE-ADMIN-001, 2026-06-12: completed tree-only user work-scope assignment.
  Backend user create/update now accepts `organizationNodeId` as the assignment
  input, derives legacy `storeId`/`regionCode`/`areaCode`, keeps SUPER_ADMIN
  global NATIONAL scope as null, blocks scoped admins from editing SUPER_ADMIN,
  and limits ADMIN_PHONGVU/ADMIN_ACARE assignments plus `/admin/users/scope-tree`
  to their organization roots. Flutter user management now loads the user
  scope tree through the ADMIN_USERS endpoint, uses only root/showroom/active
  region/area tree nodes in the editor, sends tree-only payloads, and shows
  backend `ApiException.message` in save snackbars. Validation: focused backend
  user Jest, focused Flutter user tree-scope test, `npx prisma validate`,
  `npx prisma generate`, `npm run build`, full backend `npm test --
  --runInBand` (34 suites, 243 tests), `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter expanded` (82 tests), and `git diff
  --check`. Gap: live staging user-editor click-through remains manual.
- PROFILE-ADMIN-001/FEEDBACK-001/WARRANTY-001, 2026-06-09: renamed the legacy `ADMIN` system role to `ADMIN_PHONGVU` with backend alias/migration support; scoped `ADMIN_PHONGVU` and `ADMIN_ACARE` user/SR management to their organization roots; allowed scoped admins to reset in-scope user passwords and edit only SR MAP username/password while blocking transfer-account/SR identity/scope edits; changed org-node deletion to return explicit blockers; added debounced user search and user-edit confirmation; added super-admin-only feedback list UI/API; fixed warranty image MIME upload; and wired Flutter warranty realtime WebSocket subscription to `WARRANTY_STATUS_UPDATED`. Validation: `npx prisma validate`, `npx prisma generate`, `npm run build`, full backend `npm test -- --runInBand` (33 suites, 233 tests), `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded` (79 tests), `go test ./...`, and `git diff --check`. Gap: live staging smoke for org scope, MAP credential edit, feedback list visibility, warranty upload, and realtime event remains manual.
- PROFILE-ADMIN-001/AUTH-001, 2026-06-08: refactored admin authorization to an
  organization tree plus strict per-user feature allowlist. Backend now adds
  `OrganizationNode`, `UserFeatureAssignment`, org-node links, `/admin/org-tree`
  CRUD APIs, `/admin/features/tree`, user filters by search/domain/org
  node/feature/role/status, `AUTH_ALLOWED_EMAIL_DOMAINS` login resolution,
  strict feature assignment enforcement, and break-glass bootstrap for
  `admin@hoanghochoi.com` while retiring `super_admin@phongvu-mna.vn` by delete
  or tombstone depending on references. Flutter adds organization tree admin UI,
  user-management filters, user feature checkbox tree, root-domain fallback
  domains (`phongvu.vn`, `acare.vn`), and exact break-glass email allowance.
  Validation: `npx prisma validate`, `npx prisma generate`, `npm run build`,
  full backend `npm test -- --runInBand` (33 suites, 226 tests), `dart format
  --output=none --set-exit-if-changed` on changed Dart files, `flutter analyze
  --no-pub`, full `flutter test --no-pub --reporter expanded` (76 tests), and
  `git diff --check`. Gap: local/prod DB migration apply smoke and live
  `SUPER_ADMIN` admin-UI click-through remain manual.
- PROFILE-ADMIN-001, 2026-06-07: added configurable admin policy core and UI contract. Backend now has policy definitions, policy rules, system settings, `/policies/me`, and `/admin/policies`/rules/settings APIs; feature fallback now resolves through policy rules and explicit feature allow does not grant access beyond policy authorization. Runtime policy checks cover admin user/store/catalog capability, FIFO import/log, warranty all-scope, bank statement scope, payment monitor all-scope, VietQR cross-store confirmation, auth allowed domains, and inventory sync feature guard metadata. Flutter loads `/policies/me`, parses `resolvedAdminPolicies`, exposes policy/rule/settings admin models, and keeps feature access dependent on backend-resolved maps except `SUPER_ADMIN` bypass. Validation: `npx prisma validate`, `npx prisma generate`, `npm run build`, focused backend policy/feature/user/auth/map-vietin/vietqr/payment/inventory/fifo-log Jest (9 suites, 115 tests), full backend `npm test -- --runInBand` (33 suites, 229 tests), focused Flutter admin policy/user tests (11 tests), `flutter analyze --no-pub`, and full `flutter test --no-pub --reporter expanded` (75 tests). Gap: live deployed admin policy click-through and direct API 403 smoke remain manual.
- PROFILE-ADMIN-001, 2026-06-06: feature management now supports
  email-domain access rules. `SUPER_ADMIN` can create/update rule payloads with
  `emailDomain`/`emailDomains`; backend matching derives the user email domain,
  gives domain rules the highest access-rule priority, lets domain allow
  override legacy authorization, and lets domain deny beat user/SR/role rules
  while global feature inactive state still blocks access. Flutter rule
  management can enter domain rules and logs domain counts during save flows.
  Validation: focused backend `src/feature/feature.service.spec.ts` (12 tests),
  focused Flutter `test/admin_feature_definition_test.dart` (2 tests), `npx
  prisma validate`, `npx prisma generate`, `npm run build`, full backend `npm
  test -- --runInBand` (32 suites, 221 tests), `flutter analyze --no-pub`, and
  full `flutter test --no-pub --reporter expanded` (72 tests). Gap: live
  admin feature-management click-through after migration remains manual.- PROFILE-ADMIN-001, 2026-06-06: added system role `ADMIN_ACARE`, seeded it
  through migration, moved `admin@acare.vn` from `ADMIN` to `ADMIN_ACARE`
  when present, scoped `ADMIN_ACARE` user management to `@acare.vn`, and
  changed Flutter API handling so `403 Forbidden` no longer clears the login
  session. Validation: focused backend user/feature Jest (2 suites, 22 tests),
  focused Flutter `test/user_personnel_test.dart` (6 tests), `npx prisma
  validate`, `npm run build`, full backend `npm test -- --runInBand` (32
  suites, 218 tests), `flutter analyze --no-pub`, and full `flutter test
  --no-pub --reporter expanded` (70 tests). Gap: live deployed
  `admin@acare.vn` user-management smoke after migration remains manual.
- AUTH-001, 2026-06-06: added `acare.vn` to the accepted OpsHub staff
  domain list and updated Flutter/backend validation copy so ACareTek users are
  not rejected as non-Phong Vu staff. Validation: focused backend auth/VietQR
  Jest (3 suites, 48 tests), focused Flutter validators/brand test (13 tests),
  `npm run build`, full backend `npm test -- --runInBand` (31 suites, 213
  tests), `flutter analyze --no-pub`, and full `flutter test --no-pub
  --reporter expanded` (68 tests). Gap: live registration/reset-code smoke for
  an `acare.vn` mailbox remains manual.
- VIETQR-001, 2026-06-30: added 15-minute QR expiry, persisted QR history and
  status, desktop two-column history layout, and `SUPER_ADMIN` full-showroom
  selection in the VietQR flow. Validation: `flutter test --no-pub
  test/vietqr_screen_test.dart test/validators_test.dart --reporter expanded`,
  `npx jest --runInBand src/vietqr/vietqr.service.spec.ts
  src/vietqr/vietqr.controller.spec.ts`, `npm run build`, `flutter analyze
  --no-pub`, and `git diff --check`. Gap: live desktop click-through and
  bank-app scan smoke remain manual.
- VIETQR-001, 2026-06-06: VietQR responses now include `qrBrand`; stores in
  the ACareTek Region render/export QR images with title `ACareTek` and
  `assets/icon/acare_logo.png`, while other stores keep title `Phong Vũ` and
  the Phong Vũ logo. n8n image rendering uses the same brand resolver and
  exposes brand headers. Validation: focused backend auth/VietQR Jest (3
  suites, 48 tests), focused Flutter validators/brand test (13 tests), `npm run
  build`, full backend `npm test -- --runInBand` (31 suites, 213 tests),
  `flutter analyze --no-pub`, and full `flutter test --no-pub --reporter
  expanded` (68 tests). Gap: live AC001 app QR creation and live n8n image call
  remain manual.

- FIFO-001, 2026-06-05: moved the manual `Cáº­p nháº­t tá»“n kho` entry from
  Quáº£n trá»‹ into the FIFO menu, added `/fifo/inventory-import` as the visible
  route, kept `/admin/inventory-import` as a backward-compatible alias, and kept
  both import routes guarded by `FIFO_IMPORT`. Home opens FIFO when either FIFO
  workflows or FIFO import is available. Validation: `dart format`, `git diff
--check`, `flutter analyze --no-pub`, and full `flutter test --no-pub --reporter expanded` (59 tests). Gap: live
  admin-user menu click-through remains manual.
- UPDATE-001, 2026-06-05: fixed old Android/Windows clients losing the
  update prompt during startup redirects by rendering update metadata as a
  stateful blocking overlay in `AppUpdateGate` instead of a transient navigator
  dialog. Optional prompts dismiss only from `Äá»ƒ sau`; required prompts keep
  blocking and open the configured update URL. Validation: focused `flutter
test --no-pub test/app_update_gate_test.dart --reporter expanded`, `flutter
analyze --no-pub`, full `flutter test --no-pub --reporter expanded` (59
  tests), `flutter build windows --debug --no-pub`, `flutter build apk --debug
--no-pub`, and `git diff --check`. Gap: live old APK/Windows installer
  startup smoke against production metadata remains manual.
- UI-UX-001, 2026-06-05: added `docs/product/ui-ux.md` as the canonical
  UI/UX contract; centralized payment-monitor Windows-only support through
  `AppPlatformCapabilities`; added an unsupported-platform screen with
  `AppLogger` evidence; made warranty details use responsive wrappers,
  responsive image grids, shared state surfaces, token colors, and image
  download logging; and replaced targeted admin/FIFO/warranty/sort literal
  colors with `AppColors` tokens. Validation: focused platform capability
  test, focused unsupported-screen widget test, `dart format --output=none
--set-exit-if-changed`, `git diff --check`, `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter expanded` (56 tests), `flutter build
windows --debug --no-pub`, and `flutter build apk --debug --no-pub`. Gap:
  authenticated Android/Windows visual screenshot smoke with real
  warranty/admin/sort data remains manual.
- PAYMENT-STATEMENT-001, 2026-06-03: fixed CSV export for Excel by preserving
  server CSV bytes in Flutter, ensuring a UTF-8 BOM before save, exporting long
  numeric identifiers as Excel text, and formatting statement timestamps in
  Vietnam local time. Validation: focused `npm test -- --runInBand
src/map-vietin/map-vietin.service.spec.ts`, focused `flutter test --no-pub
test\bank_statement_provider_test.dart --reporter expanded`, `npm run build`,
  `flutter analyze --no-pub`, full `npm test -- --runInBand` (30 suites, 189
  tests), and full `flutter test --no-pub --reporter expanded` (51 tests).
  Gap: manual open-exported-CSV-in-Excel smoke on target Windows remains
  pending.
- PAYMENT-MONITOR-001, 2026-06-03: fixed `/payment-notifications/ready`
  starvation where long-running clients could see transactions in `Tien vao`
  but not receive newer audio notifications because the backend capped old
  READY candidates before excluding the client's terminal
  `PLAYED`/`SILENCED`/`FAILED` logs. The endpoint now excludes terminal
  notification ids in the READY query and logs large terminal exclusion counts.
  Validation: focused `npm test -- --runInBand
src/payment-notifications/payment-notifications.service.spec.ts`,
  `npm run build`, and full `npm test -- --runInBand` (30 suites, 189 tests).
  Gap: live Windows speaker/poll smoke after deploy remains pending.
- UI-UX-001, 2026-06-03: fixed Android release startup blank screen caused by
  unconditional `MediaKit.ensureInitialized()` before `runApp`; media_kit now
  initializes only on non-web Windows, logs the startup branch through
  `AppLogger`, and lets the app continue with fallback audio if Windows media
  initialization fails. Validation: reproduced the blank screen on a real
  Android 14 device (`21081111RG`) with release APK `versionCode=100050`, where
  logcat showed `media_kit: ERROR: MediaKit.ensureInitialized`; after the fix,
  `flutter analyze --no-pub`, full `flutter test --no-pub` (43 tests), release
  APK build `versionCode=100051`, install over the existing app without data
  wipe, logcat startup check with no media_kit startup error, and screenshot
  proof showing the Home screen rendered on the same device. Gap: GitHub deploy
  proof pending until this fix is pushed.
- PAYMENT-STATEMENT-001, 2026-06-02: Sao ke date range now shows `Hom nay`
  when no explicit range is selected, treats incomplete custom ranges as the
  default current-day query, and renders short transaction summary pills for
  `VietinBank`, SR code, amount, and the transfer-success state without showing
  the raw MAP API status. Validation: `dart format --output=none
--set-exit-if-changed` for changed Dart files, `git diff --check`, `flutter
analyze --no-pub`, full `flutter test --no-pub` (42 tests), and `flutter
build windows --debug --no-pub`. Gap: live Windows UI click-through remains
  manual.
- UI-UX-001, 2026-06-02: refreshed home, bottom navigation, shared action
  buttons, status panels, feature tiles, and FIFO empty/loading states for more
  consistent desktop/mobile density while keeping existing routes and data flows
  unchanged. Validation: `dart format --output=none --set-exit-if-changed` for
  changed Dart files, `git diff --check`, `flutter analyze --no-pub`, full
  `flutter test --no-pub` (42 tests), and `flutter build windows --debug
--no-pub`. Gap: manual visual smoke on target Windows hardware remains
  pending.
- PAYMENT-MONITOR-001, 2026-06-01: Windows payment monitor now initializes
  `media_kit` and retries each payment notification up to 3 times with a
  10-second delay before falling back to terminal `FAILED`. The client uploads
  `PaymentSpeaker` started/succeeded/failed logs, acknowledges interim
  `PLAYBACK_FAILED`, and reuses the same downloaded audio bytes across retry
  attempts while keeping `PLAYED`, `SILENCED`, and `FAILED` as the only
  terminal delivery events. Validation: `flutter analyze --no-pub`, `flutter
test --no-pub --reporter expanded` (40 tests), `npm test -- --runInBand
src/payment-notifications/payment-notifications.service.spec.ts` (9 tests),
  `npm run build`, `flutter build windows --debug --no-pub`, `git diff
--check`. Follow-up: pinned `media_kit_libs_windows_audio` to upstream git
  commit `7102e7da96f39c718487a8f7a59b6a034aae7f45` (`fix: CMP0175 warning on
Windows (#1377)`), then re-ran `flutter clean`, `flutter pub get`, and a
  clean `flutter build windows --debug --no-pub`; the prior CMake
  `add_custom_command` policy warning no longer appeared. Gap: live Windows
  speaker smoke still needs physical-audio verification.
- PAYMENT-MONITOR-001, 2026-06-01: changed only the backend MAP-history fetch
  scheduler so each scheduled fetch waits a random 3000-5000ms after the
  previous run finishes; client polling of OpsHub stored transactions remains
  unchanged. When `MAP_VIETIN_SYNC_ENABLED=false`, the scheduler does not start
  a timer, so paused MAP sync stays paused until the backend is restarted with
  sync enabled. Validation: `npm test -- --runInBand
src/map-vietin/map-vietin.service.spec.ts` (26 tests), `npm run build`, full
  `npm test -- --runInBand` (29 suites, 171 tests), `git diff --check`.
  Gap: live VPS deploy/smoke pending.

## Evidence Rules

- Unit proof covers pure validators, service rules, and focused repositories.
- Integration proof covers API behavior, database persistence, Redis, BigQuery,
  uploads, and auth enforcement.
- E2E proof covers user-visible app flows.
- Platform proof covers mobile runtime, Docker services, deployment, health
  checks, and WebSocket behavior.
