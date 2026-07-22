# Test Matrix

This file maps product behavior to proof. Existing flows are marked
`existing_unverified` until fresh validation evidence is attached.

- `OPS-11`, 2026-07-22: Piper `piper-vi-vais1000-chunk-v1` supersedes the
  rejected VieNeu/Ngọc Linh pack and ships as a
  Windows-only pack with 1.103 PCM16 mono 24 kHz assets. Matching realtime
  events compose locally, claim delivery without opening audio, retain existing
  FIFO/dedupe/ACK behavior, and fall back to server audio on any pack or version
  failure. The generated and copied source packs passed SHA-256/format/guard/
  full-scale validation for all 1.103 WAV files (74.793.470 bytes); generator
  tests passed 8/8, focused Flutter passed 96/96 including a real five-asset
  compose, full Flutter passed 601 with 3 skips, analyzer was clean, NestJS
  build and 44 focused tests passed, and Go realtime passed 64 tests. Windows
  Release build and its packaged copy of all 1.103 assets passed the independent
  verifier. Local real-speaker playback confirmed the 150 ms cue gap and 45 ms
  chunk gap. Remaining staging gates: authenticated-app burst FIFO, corrupt-
  asset fallback and p95 WebSocket-to-first-audio QA.

- `OPS-8`, 2026-07-21: Flutter web now selects full CanvasKit through the
  source-controlled bootstrap, while retaining the generated service-worker
  version and deployment cache-busting token. A release build and the static
  bootstrap verifier passed; Chrome CDP loaded `/canvaskit/canvaskit.wasm` and
  reported zero `IntlV8BreakIterator` deprecation issues on the login route.
  The uncompressed selected Wasm artifact is 7,083,768 bytes versus 5,708,955
  bytes for the Chromium-specific variant. Intake `85` protects the existing
  Flutter analyzer, full test suite, release build, service-worker bootstrap,
  and cache-busting consumers.

- `GIT-WORKFLOW-001`, 2026-07-21: feature work defaults to a Linear-linked
  task branch and PR into `staging`; direct protected-branch pushes now require
  an explicit current-task command without waiving clean scope, CI, QA,
  release-window, or fast-forward gates. The production promotion guard accepts
  only the exact `origin/staging` SHA, defaults to dry-run, verifies GitHub
  checks/statuses when dispatched, never force-pushes, and re-fetches to require
  `origin/main == origin/staging`. Fixture proof passed 8/8 tests: dry-run no-op,
  successful fast-forward, blocked divergence, stale SHA, missing QA, dirty
  worktree, GitHub CI pass/fail, existing staging/production deploy triggers,
  the always-on `Release guard` PR check, and static no-force policy. All six
  workflow YAML files parsed and `git diff --check` passed. GitHub external audit
  confirms the production reviewer, branch policy, App ID variable, private-key
  environment secret name, and disabled admin bypass. Remaining external gates:
  observe one live `Release guard` check, verify App token mint, configure the
  App ruleset bypass, create missing Linear statuses, and perform a controlled
  workflow rehearsal.

- `AUTH-FEATURE-GATE-001`, 2026-07-20: `ADMIN` users now receive the same
  feature-gated workspace behavior as `SUPER_ADMIN` within their assigned
  scope; policy rules may narrow capability or widen data scope only after the
  feature is enabled. Disabled `Cấn trừ`/`Sao kê` features no longer reopen
  through policy-only access or realtime ticket claims. Fresh proof: NestJS
  focused suites `151/151`, NestJS build, Prisma validation, Go `64/64`,
  Flutter analyze, and Flutter permission/navigation/route tests `32/32`.
  Full Flutter also passed `582` tests with `3` platform skips. Evidence is
  recorded in intake `77` and the protected `PROFILE-ADMIN-001` story.

- `UI-DATE-RANGE-001`, 2026-07-11: replaced the Material range dialog with the
  canonical token-based `DateRangePicker`: desktop compact anchored popover
  attached to the trigger button with preset sidebar plus dual calendars, mobile
  one-month bottom sheet, draft Apply/Cancel/Clear, inclusive standard presets,
  range highlighting, min/max/disabled dates and keyboard navigation. Existing
  Home, sales-report, payment-monitor, bank-statement and offset-adjustment
  filters continue through `AppDateRangeDropdown`; API date-only `yyyy-MM-dd`
  and local-day semantics are unchanged. Validation:
  9 focused picker widget tests and Sales Report integration suite passed;
  canonical date-range guard passed; `flutter analyze --no-pub`,
  `flutter test --no-pub` passed 493 tests with 0 failures/errors, Windows
  release build passed, and `git diff --check` passed.

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

- `WINDOWS-DIST-001`, 2026-07-02: the manual MSIX workflow supports an
  internal signed sideload artifact with the selected Windows signing PFX, plus
  the existing Store artifact path with Partner Center identity secrets. Runtime
  distribution remains unchanged: production/staging deploys still publish the
  Inno EXE, ZIP, checksum, `/download`, and Windows `/app-version` EXE update
  URL. Validation target: workflow syntax, PowerShell parser, `git diff
  --check`, and an MSIX CI run that reaches Microsoft Defender scan plus
  artifact upload.
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

- `OPS-10`, 2026-07-21: khôi phục baseline Design System cho Sales Report.
  Modal nhập Excel dùng `AppDirtyFormGuard`, đánh dấu thay đổi sau khi chọn tệp
  và xác nhận trước khi hủy dữ liệu chưa nhập; thao tác nhập thành công vẫn đóng
  và tải lại danh sách. Nút chọn tệp và thẻ dòng lỗi dùng primitive chung;
  nội dung hiển thị đổi `SR` thành `showroom` mà không đổi `storeCode` hay scope
  dữ liệu. Không sửa hoặc làm yếu global guard. Validation: focused Design
  System/dialog/Sales Report passed 35 tests, `flutter analyze --no-pub` sạch,
  full Flutter passed 591 tests with 3 platform skips. Harness intake 87 giữ
  completion record theo đúng changeset fingerprint.
- `UI-PASTE-001`, 2026-07-19 follow-up: physical iOS PWA staging build
  `2026.07.19.210` proved that the all-Flutter web policy created two Paste
  controls: Flutter's toolbar initiated clipboard access, then Safari opened
  its native confirmation. Intake 73 restores browser-native ownership for
  iOS/Android PWA while desktop web keeps the Flutter toolbar. Shared inputs
  retain their system/adaptive builder; Flutter web suppresses that builder
  automatically while `BrowserContextMenu` is enabled. The runtime guard still
  requires every editable field to flow through `AppTextInput`,
  `AppFormTextInput`, or `AppCombobox`. Corrected automated and physical proof
  Focused shared/native proof passed 40 tests; `flutter analyze --no-pub` and
  `flutter build web --release --no-pub` (including the Wasm dry run) passed. A
  Playwright iPhone-profile smoke (platform override before Flutter boot)
  verified an uncanceled browser `contextmenu`, one DOM clipboard insertion,
  and zero Flutter `Paste` labels. The full suite reached 570 passed and 3
  intentional skips; two unrelated realtime timing assertions were flaky in
  the aggregate run and each passed in isolation. Physical iOS PWA smoke on
  staging remains the final platform gate.
- `UI-PASTE-001`, 2026-07-19 intermittent-paste hardening: the first iOS touch
  used to focus an input and mouse, keyboard, or programmatic clicks continue to
  Flutter normally. Only a touch sequence on the already-focused input, or a
  fast repeated touch on that same input, is WebKit-owned without canceling its
  default action. Ownership requires the same `pointerId` and target, so
  unrelated multi-touch events are not suppressed. Only the paired click is
  stopped before Flutter's engine can relocate `.flt-text-editing` to
  `-9999px`. A null-target blur is protected while that owned touch remains
  active or during one single-use 220ms grace immediately after its matching
  pointer-up or pointer-cancel, including a terminal event retargeted by WebKit,
  and only while `relatedTarget` is null and the document stays focused and
  visible. An outside pointer, focus on another control, hidden/page lifecycle,
  or a new primary touch clears stale ownership; later and
  keyboard-dismissal blur continue normally. The bridge observes both native
  DOM `paste` and
  `beforeinput(insertFromPaste)` in capture phase. It resolves the direct or
  active Flutter DOM input, replaces the exact selection synchronously, and
  emits one synthetic `input`. A cached target is eligible only when that exact
  input produced the guarded transient blur no more than 10 seconds earlier and
  still matches the retained focused `EditableTextState`. An empty first event
  retains one 180ms lease only for an immediate opposite event carrying text;
  a second empty, same-source, late, foreign, focus, or lifecycle event consumes
  it. Arbitrary queried nodes and foreign inputs are rejected. A single-use
  180ms marker consumes only the paired opposite
  event, including a neutral `body` target and formatter normalization. If the
  Flutter engine drops that DOM
  update, the retained `EditableTextState` receives the same replacement through
  `userUpdateTextEditingValue`, keeping formatters and `onChanged` intact. The
  path is initialized only for browser-native mobile mode, keeps the browser
  as the sole menu owner, and logs sanitized source/branch/length context
  without clipboard contents.
  Focused policy/guard/bootstrap proof passed 29 tests, `flutter analyze
  --no-pub` was clean, and the release web build plus Wasm dry run succeeded.
  Local Playwright iPhone-profile smoke on the final release build verified the
  first-focus touch/click passed, the focused native touch kept the same DOM
  input and transform without `preventDefault`, and paired paste/beforeinput
  produced one exact replacement. Retargeted up/cancel stayed owned, cancel
  preserved blur without creating a click lease, `pagehide` released the old
  pointer, new-primary recovery worked, unrelated/non-primary touches bubbled,
  and blur/click propagated after 220/300ms. On an actual focused Flutter input,
  empty paste followed by a data-bearing opposite event inserted once, while a
  later body paste and empty/empty/data sequence did not reuse the stale field.
  A new paste with the same clipboard still inserted, and foreign HTML-input
  paste was neither canceled nor redirected. The full Flutter run reached
  574 passed and 3 skips; the unrelated offset-adjustment max-wait timing
  assertion failed with expected 2
  versus actual 3 and reproduced in isolation. The Chrome widget runner still
  times out before its test-manager handshake; physical iOS PWA repeat remains
  the final device gate. Intake 74 affected-runtime run/record/check passed
  against the narrowed implementation fingerprint for
  `PAYMENT-STATEMENT-KEYBOARD-001`, `UI-KEYBOARD-001`, `UI-PASTE-001`, and
  `UI-UX-001`.
- `HOME-DASHBOARD-002`, 2026-07-19: modal `Đơn chưa báo cáo` thêm cột
  `Giá trị đơn` ngay sau `Mã đơn hàng`, lấy từ
  `HomeSummaryOrderFact.grandTotal` và định dạng VND. Details API v1/v2 dùng
  cùng contract nullable để dữ liệu cũ không có giá trị vẫn hiển thị an toàn.
  Validation: focused Home Summary NestJS passed 36 tests, focused Home
  dashboard Flutter passed 26 tests, `npm run build`,
  `flutter analyze --no-pub`, and `git diff --check` passed.
- `UI-KEYBOARD-001`, 2026-07-19: audited 31 Flutter presentation files that own
  text inputs and their shared viewport shells. Fixed the two risky compact
  layouts: Bank Statement now scrolls filters, states, and results in one mobile
  viewport while keeping the focused filter visible; the unsupported-camera
  barcode fallback now uses the shared responsive scroll surface. Added mobile
  keyboard-inset regression coverage for both fixes, supported-camera barcode,
  and the last registration field. Desktop layouts and third-party iOS keyboard
  theming remain unchanged by contract. Validation: the 13-file representative
  bundle passed 68 tests, the combined Bank Statement provider/screen/keyboard
  bundle passed 38 tests, and `flutter analyze --no-pub` passed. Full Flutter
  passed 569 tests with 3 platform skips; the income-type row-message test also
  verifies its intended 3-second expiry. Final gates: affected-runtime Harness
  proof and staged-diff review before the staging push.
- `SALES-REPORT-001`, 2026-07-19: export `Trả góp` chèn `Đơn hàng` và
  `Giá trị đơn hàng` ngay sau `Email người báo cáo`, lấy lần lượt từ
  `orderCode` và tổng tiền ERP; báo cáo chưa mua để trống hai cột này. Trường
  `Khách hàng tìm sản phẩm gì?` dùng chung giới hạn 1.000 ký tự ở Flutter,
  DTO và service backend. Validation: focused SalesReportsService Jest (72
  tests), focused Sales Report Flutter (23 tests), Design System migration
  guard đa nền tảng LF/CRLF (20 tests), full NestJS (80 suites/782 tests),
  full Flutter (563 passed/3 skipped), `flutter analyze --no-pub`, Prisma
  validate/generate, Nest build, Go realtime 64 tests và `go vet ./...`.
- `CONTRACT-APPENDIX-001`, 2026-07-17: triển khai source-of-truth từ
  `SalesReportErpService.lookupOrder`, chỉ dùng item `finalSellPrice`; adapter
  PPM dùng cùng tài khoản/token cache ERP, terminal `49180_PRICE_0001`, batch
  50 SKU, Redis cache 5 phút và miss cache 30 giây. Backend tính integer VND,
  phân biệt VAT 0% với KCT qua tax metadata, hỗ trợ thuế nhập tay có cờ, quote
  conflict, snapshot cá nhân 30 ngày và tiền bằng chữ. Proof đạt: Prisma
  format/validate/generate, Nest build, 33 test trọng tâm và full 79 suite / 760
  test. Flutter proof đạt `flutter pub get`, focused guard/core/screen (28 test),
  `flutter analyze --no-pub`, full Flutter (558 passed, 3 skipped), Windows
  release, web release và Android staging debug build. Live PPM CLI qua auth
  dùng chung trả SKU `250902982` là `8%` (`vatRateBps=800`). Staging workflow
  `29564482891` apply migration và public proof đúng SHA `708ba564`; local
  migration rollback scratch chưa chạy vì Docker Desktop Linux engine chưa
  khởi động. User đã xác nhận rich table paste được vào Word Windows. Follow-up
  khóa layout editor/preview một cột, preview desktop 960px, Times New Roman
  12pt trên từng ô, cột tiền căn giữa, căn lề theo mẫu và tách `Bằng chữ` khỏi
  table. Follow-up CF_HTML dùng fragment thuần, font trực tiếp trên text run và
  khóa tỷ lệ cột `6/40/6/7/16/9/16`; hàng đầu vẫn là `tbody/tr/td`, không dùng
  `thead/th` nên không đánh dấu lặp header. Còn recheck định dạng thật trên cả
  tài liệu Word trắng và file mẫu sau khi phát hành follow-up.

- `SALES-REPORT-001` / `SALES-REPORT-002`, 2026-07-17: biểu mẫu khách chưa
  mua đã bỏ ô Zalo tự do; số điện thoại chỉ nhận đúng 10 chữ số bắt đầu bằng
  `0` hoặc để trống. Hai kênh `ZALO_PERSONAL` và `ZALO_OA` được chọn độc lập,
  lưu cùng `PHONE` trong `customerContactChannels`, dùng lại ở follow-up,
  HVTC export và BigQuery facts. Migration backfill dữ liệu cũ, dọn số điện
  thoại rác và cài DB constraints cho dữ liệu mới. Validation passed: Prisma
  validate/generate, focused Flutter (30 tests), focused NestJS (77 tests),
  full Flutter (548 passed, 3 skipped), full NestJS (723 tests),
  `flutter analyze --no-pub`, NestJS build và `git diff --check`. Chưa smoke
  migration trên PostgreSQL thật do Docker local không chạy và compose secrets
  chưa được cấu hình.

- `SALES-REPORT-002`, 2026-07-20: màn hình `Chăm sóc lại` thêm bộ lọc
  `Mã SR / Showroom` chỉ cho Super Admin; chọn SR truyền `storeCode` vào API,
  reset về trang đầu và giữ nguyên scope của các vai trò khác. Validation:
  focused Flutter follow-up widget test và affected-runtime guard.

- `AUTH-004`, 2026-07-15: passive production evidence showed healthy resource
  headroom while HTTP 429 reached 8,814/13,416 requests in 30 minutes;
  `/home/summary` alone returned 798/2,115 throttles. That evidence diagnoses
  the former global IP bucket; it does not prove the new composite tracker. The
  accepted contract is now one `principal` bucket: verified
  `userId + sha256(trustedIp)`, hashed anonymous email, then hashed trusted-IP
  fallback, with no second global IP bucket. Required fresh proof is focused
  guard tests, full Nest build/tests, no raw-IP leakage, 60 principals behind
  one staging NAT with zero unexpected 429, and a separate one-user
  120/minute semantics run where the control user stays 200.

- `PAYMENT-MONITOR-002`, 2026-07-15 release gate: focused tests must prove one
  manual cooldown-bypass ticket per method/path 429 cycle, no second ticket
  after a bypass receives 429, expiry/success reset, endpoint isolation,
  coalesced user-action preservation, and no background/realtime bypass. Live
  staging proof must produce one bypass request after the first manual refresh
  and defer the second locally. This entry defines required proof and does not
  claim the live test has run.

- `HOME-DASHBOARD-003`, 2026-07-15 release gate: repository and route freshness
  share one 60-second TTL. Focused proof requires no HTTP at 59 seconds, exactly
  one revalidation at 60 seconds, stale fallback retaining original
  `fetchedAt`, and realtime/reconnect/resume force-network behavior without a
  polling timer. Staging capacity proof uses 70% Home traffic over a verified
  COMPLETE 1/7/30/90-day projection window.

- `HOME-DASHBOARD-003`, 2026-07-16 tail-latency checkpoint: the minute
  reconciliation skips only an unchanged COMPLETE date with a known source
  watermark or an existing GLOBAL queue job; forced hourly/nightly windows
  remain the repair path for a missed source trigger. Projection events
  invalidate only overlapping response ranges whose exact per-date projection
  version is older; duplicate/out-of-order outbox delivery is idempotent across
  cache generations. Invalidated in-flight work cannot repopulate or remove a
  newer generation. The 60-second hard TTL remains intact while a deterministic
  30-50 second refresh-ahead window spreads hot-key renewal; failed refreshes
  keep the original expiry. Focused Jest passed 34/34, full Jest passed 69/69
  suites and 691/691 tests, and Nest build passed. The k6 proof now gates the
  isolated 15-minute 100-QPS hold, both overall and per-range 1/7/30/90-day Home
  latency, instead of relying on a percentile diluted by lighter ramp phases.
  Active staging proof remains required before promotion.

- `UPDATE-004`/`WINDOWS-DIST-001`, 2026-07-15 release gate: Windows runtime is
  HTTPS same-origin/type/size/SHA-256 only and has no signer build define.
  Release CI still requires PFX/password/pin, valid Authenticode plus timestamp,
  a matching signer fingerprint and clean Defender scan. Focused tests cover
  stable code/stage/severity and SHA-mismatch cleanup; staging must prove an
  installed N to N+1 relaunch without changing the production installation.

- `PLATFORM-001`, 2026-07-15 release gate: Caddy `/download/` and `/help/`
  return direct-origin 308 to their exact canonical paths without loops;
  enforced CSP remains intact. Staging deploy must prove automatic rollback to
  the previous release on migrate/recreate/health failure and force ERP
  cache/status, VietQR reconcile, MAP global sync, Home ERP backfill and SMTP
  side effects off.

- `STAGING-LOAD-001`, 2026-07-15 proof contract: use 60 temporary STAFF users,
  deterministic round-robin tokens, 100 QPS with a 15-minute hold and 60
  `/ws/v2` connections. Pass at HTTP success >=99.9%, p95 <=500 ms, p99 <=1 s,
  zero unexpected 429/dropped iterations/invalid WS envelopes and bounded
  resource health. Revoke sessions, increment token versions, delete all 60
  users and remove token/k6 files after any outcome. This is a staging release
  proof, not rolling-30-day evidence; Engineering stops promotion below 25%
  error-budget remaining. RPO 24h/RTO 4h remain separate production gates.

- `RELEASE-GATE-2026-07-15`: before push, run focused suites above, NestJS
  build plus full Jest, Flutter analyze plus full tests, Go test plus vet, Caddy
  validate/adapt and redirect contract checks, platform-security verification,
  workflow syntax validation and `git diff --check`. After push, require exact
  remote SHA, green staging deploy, public API/WS/download health, the active
  load and rate-semantics runs, manual Payment bypass, installed Windows N to
  N+1 smoke and verified zero-count cleanup. Record actual results in the
  staging proof report; this line is a gate definition, not execution evidence.

- `APP-PERF-001`, 2026-07-15: status `implemented`, proof scope
  `local_verified`. Saved-session auth now hydrates last-known-good access,
  conditionally refreshes `GET /auth/bootstrap` with ETag/`304`, uses the legacy
  three-call refresh only for `404/501`, retains access on network/`5xx`, and
  clears session plus persisted query cache on `401`. The app owns one shared
  authenticated `/ws/v2`; route/lifecycle gating separates Home, warranty,
  notification, sales-report and payment-list reads from the global Windows
  speaker. Notification rows load through one `GET /notifications/feed`, with
  old endpoint fallback only when unsupported. Delivery metrics use typed
  invalidation with 30-second trailing debounce and a 15-minute foreground
  fallback instead of one-minute polling. Authorization hardening separates
  `policyCodes` from organization codes, invalidates access after relevant
  user/org/store topology mutations, and rejects stale in-flight provider
  responses after same-user scope revocation. Local proof: changed Dart files
  passed formatter check, full-project `flutter analyze --no-pub` passed, and
  full `flutter test --no-pub --reporter compact` passed 520 tests with 2
  intentional skips. Changed Nest files passed Prettier check, `npm run build`
  passed, and full Jest passed 69/69 suites with 676/676 tests. Go
  `go test -count=1 ./...` and `go vet ./...` passed. `git diff --check` passed.
  No staging or production request-count, runtime, compatibility, Windows/
  Android/Web UI smoke proof has been run; those remain rollout gates before
  claiming the request-reduction targets.

- `AUTH-CONTEXT-001`, 2026-07-17: status `implemented`, proof scope
  `staging_verified`. Nest now hydrates one versioned `AuthContextService` for
  bootstrap/profile/feature/policy compatibility routes, realtime-ticket and
  Home scope options. Bootstrap performs ETag preflight before resolver work;
  policy definitions/rules are batch-loaded; organization tree reads use a
  bounded cache; scope-options use shared Redis with versioned keys and
  process/distributed deduplication. `User.accessVersion` and its Prisma
  migration are included, and context scope snapshots explicitly exclude
  password/token/session secrets. Local proof: Prisma generate/validate, Nest
  build, full Jest (73 suites, 718 tests), focused ETag/context/batch/Redis
  tests, and `git diff --check` passed. Staging proof passed on head `ad7efa03`:
  two-VU limiter semantics had zero unexpected failures; the 121,628-request
  `25 → 50 → 100 QPS` ladder had 100% HTTP success, aggregate p95/p99
  85.976/176.193 ms, zero dropped iterations and 60/60 WebSocket sessions;
  two replicas shared/deduplicated cache entries and rejected an invalidated
  version; controlled Redis loss returned bootstrap/scopes `200` through
  PostgreSQL fallback and recovered healthy. Node/PostgreSQL profiles were
  captured, staging profiling settings were reset, and 60 synthetic users plus
  every raw token/profile artifact were removed with zero records remaining.

- `AUTH-CONTEXT-001-HOTFIX`, 2026-07-17: status `local_verified`, release scope
  `staging_pending`. Bootstrap now includes authenticated `id/email`; Flutter
  shares the v1 contract fixture with Nest, tolerates a missing email only via
  the current saved-session identity, rejects identity mismatch, classifies
  contract failures with sanitized metadata, and falls back once only when no
  usable snapshot exists. Pre-v2 upgrade, `200` missing-email, malformed JSON,
  cached contract failure, `401`, `404/501`, `503`, `304` without usable cache,
  logout race and AppShell fail-closed/retry regressions passed. Validation:
  targeted Flutter 36 tests; Flutter analyze; full Flutter 545 tests/3 skips;
  targeted Nest 21 tests; Nest build; full Nest 73 suites/720 tests; Go 62
  tests/vet; Windows debug build; Android `staging` debug build;
  `git diff --check`. Production remains application-rolled-back to `1b174205`
  until exact-candidate staging upgrade smoke and passive observation pass.

- `HOME-DASHBOARD-003`, 2026-07-15: Home projection/outbox, `/ws/v2` and
  Flutter reconnect/resume path passed Prisma validation, scratch-database
  migration up/down (`90/90/90` seed), Nest build, 42 focused Jest tests, 31 Go
  tests, 24 focused Flutter tests, the 458-test Flutter suite and
  `flutter analyze`. Staging load/SLO and 1/7/30/90-day runtime parity remain
  rollout gates. The date-sensitive ERP 40/10 quota fixture now derives a
  recent order date instead of expiring after the calendar advances; focused
  Sales Report passed 65/65 and full Nest passed 64/64 suites, 629/629 tests.
- `HOME-DASHBOARD-003`, 2026-07-20 Phase 1 closure: projection work is
  coalesced by date/kind with lease and dirty-generation recovery; SALES and
  FINANCE snapshots commit independently and publish only after the atomic
  replace. Flutter now owns one authenticated socket at app-session scope,
  compares Home versions per affected date, refreshes on overlap/resume, and
  pages details v2 with a typed keyset cursor. Scratch migration proof passed
  up/seed/burst/down (`90/180/180`, `5000 -> 1`); focused Home Nest passed 58,
  full Nest passed 81 suites/812 tests, Go passed 64 plus vet, focused Flutter
  passed 37, design/Home details passed 49, full Flutter passed 580 with 3
  intentional platform skips, and analyze passed. Staging k6/SLO, worker
  latency, 1/7/30/90 parity and RAM remain rollout gates; k6 is unavailable on
  the local host.
- `HOME-DASHBOARD-003`/`PAYMENT-MONITOR-001`, 2026-07-15: identical MAP rows
  are discarded by a bounded TTL/LRU fingerprint cache before database access;
  database comparison remains the fallback and new rows are committed before
  asynchronous payment notification publication. MAP-only projection enqueue
  now uses a 2-second trailing debounce with a 5-second maximum wait, while
  irrelevant MAP updates do not enqueue projection work. Provider and app API
  HTTP 429 responses now publish/honor `Retry-After` and suppress repeat calls
  during endpoint-specific cooldowns. Validation: migration up/down with
  `90/90/90` seed, Prisma validation, Nest build, 112 focused and 635 full Jest
  tests, Flutter analyze, 3 focused and 474 full Flutter tests, web build, and
  `git diff --check` passed. Live load, speaker latency and 429-rate reduction
  remain post-deploy measurements.

- `PAYMENT-MONITOR-001`/`PAYMENT-MONITOR-002`, 2026-07-14: production runtime
  diagnosis found the displayed 24-hour average `139.206s` was inflated by a
  stale `READY` notification replayed on another client about 17.4 hours later;
  the first-ever stream-start average was `6.794s` with median `5.954s`.
  The MAP fast-window delay is now configurable and defaults to `1000-2000ms`
  with a `500ms` safety floor, the lightweight `/ready` fallback checks every
  5 seconds after realtime silence, and `/ready` plus `/stream` reject both
  `PENDING` and `READY` notifications older than the 30-second recovery window.
  Delivery metrics now assign each notification only to its first-ever
  `STREAM_STARTED` bucket. Validation: 138 focused backend tests, 30 focused
  Flutter tests, Nest build and Flutter analyze passed; `git diff --check` is
  clean. A fresh live window after deployment is still required to verify the
  `<5s` target.
- `SECURITY-001`, 2026-07-14: NAS backup regression found release-note values
  with spaces in the Docker dotenv file. Backup scripts now read only an explicit
  dotenv allowlist instead of sourcing the full runtime env as shell code. Proof:
  Bash syntax, fixture with unquoted release notes, encrypted backup publication,
  6/6 destination checksum and no `.incoming` directory.
- `PAYMENT-MONITOR-001`/`PAYMENT-STATEMENT-001`/`VIETQR-001`, 2026-07-14:
  MAP fast-window polling now fetches page 1 only every 1-2 seconds. A bounded
  deep sweep fetches up to the configured 2-page cap at backend startup, after
  MAP session refresh, and every random 30-60 seconds so backfill remains
  covered without doubling every fast loop. HTTP 429 applies exponential
  30/60/120-second backoff plus jitter; a persistent HTTP 403 after one session
  refresh pauses for 5 minutes. Logs include mode, page count, duration,
  provider status, backoff attempt and retry time. Validation: focused MAP Jest
  passed 96 tests, the full backend Jest command and Nest build completed
  successfully, and `git diff --check` passed. Live provider cadence and `<5s`
  speaker latency remain post-deploy measurements.
- `UI-UX-001`, 2026-07-14: mobile quick actions now occupy a real centered fifth
  `NavigationBar` slot, with five equal-width columns instead of an absolute
  button overlapping four destinations. Phone-only density below 600 px uses a
  68 px bar, 22 px destination icons, compact labels, a 46 px quick-action
  launcher, and a global 0.92 typography factor; tablet and desktop remain
  unchanged. Validation covers equal
  column spacing, launcher bounds, route-index mapping, mobile text scaling,
  focused shell/quick-action/theme tests, Flutter analyze, and diff check.
- `PAYMENT-MONITOR-001`/`PAYMENT-STATEMENT-001`/`VIETQR-001`, 2026-07-14:
  user-facing eFAST statement fields now use `trxId`, matching the MAP statement
  reference, instead of exposing numeric provider `trxRefNo` values. The shared
  backend resolver covers statement API responses, CSV export, transfer-request
  details, and stored VietQR confirmations; MAP behavior is unchanged.
  Validation: focused MAP/VietQR Jest passed 110 tests, Nest build passed, and
  `git diff --check` passed.
- `PAYMENT-STATEMENT-001`, 2026-07-17: eFAST mapping keeps `pmtId` as the
  preferred showroom identity and falls back to the configured receiving
  account when `pmtId` is missing or unmapped. Creating/changing a showroom
  account immediately assigns only matching `storeCode=null` rows; scheduled
  sync repairs remaining historical rows and maps new transactions using the
  latest account index. Existing manual assignments are preserved. Runtime
  diagnosis first found 207 post-assignment LO rows still null under the old
  logic; the production checkpoint later captured 210. The hotfix remapped all
  210 to LO (`NULL=0`) while preserving the one CP68 row and one CP75 row. Live
  sync counters showed `sourceAccountMapped=17`, then `accountRemapped=0` on
  the following run, both with `quarantined=0`. Focused MAP/User Jest passed
  162 tests on staging and 155 tests on the exact production release; both Nest
  builds passed.
- `PAYMENT-STATEMENT-001`, 2026-07-17: Sao kê now persists `incomeType`,
  classifies high-confidence partner/internal markers (`BC CN/CP/CTY/DKKD`,
  `So GD goc`, VNSHOP, RECESS, ShopeePay, ZaloPay, VNPAY, Nhat Tin, GHTK and
  EMB/KHDN), and keeps generic `CT DEN` as sales. SR users are constrained to
  `SALES` even for global lookup and selected export; FIN_ACC/national scope can
  see both. Export is XLSX with income type and receiving account columns, and
  mobile Sao kê collapses filters after search. Validation: Prisma generate,
  Nest build, focused MAP/income-type Jest, Flutter analyze, and focused bank
  statement provider/screen tests including the mobile collapse regression.
- `PAYMENT-STATEMENT-001`, 2026-07-18: MAP sync now preserves both `MANUAL` and
  approved `OFFSET` orders. De-duplication keeps identifier matching as the
  primary path and adds an exact opposite-source fingerprint fallback using
  showroom, amount, bank timestamp, and stored content. Flutter statement cards
  are keyed and reindexed by transaction ID; failed order saves keep the editor
  open and distinguish invalid 14-digit format from an invalid `YYMMDD` date.
  Validation: focused MAP Jest (106 tests), Nest build, bank-statement provider
  tests (29), widget tests (7), and Flutter analyze passed. The checkpointed
  production repair removed six exact eFAST duplicate rows and notifications,
  retained their audit/delivery evidence on MAP, and restored seven rows from
  the latest approved OFFSET audits; immediate post-check was duplicate `0`,
  deleted references `0`, and restored OFFSET `7/7`. Prevention code remains
  local pending the normal release gate. Full Nest regression passed 80 suites /
  780 tests. Full Flutter reached 562 passed and 3 skipped; the only failure was
  the unrelated existing design-system route-count guard against an unchanged
  router/gap-map document.
- `PAYMENT-STATEMENT-001`, 2026-07-19: income type no longer filters statement
  visibility beyond the user's existing organization/showroom scope. FIN_ACC
  and protected-statement administrators can change the Vietnamese pill, and
  `incomeTypeSource=MANUAL` protects that choice from MAP/eFAST sync. Automatic
  classification only uppercases/removes whitespace, then matches the accepted
  `BC CN/CP/CTY/DKKD` prefixes, Nhat Tin, VNPAY TT 217344, ShopeePay MS/WSS
  withdrawal, GiaoHangTietKiem CoD, ZaloPay wallet settlement, `Dieu tien tu
  dong`, the mapped store's `TNG<storeCode>NOPTIEN`, or a configured payer
  account. Focused income-type/MAP Jest passed 138 tests, the full Nest
  regression passed 80 suites / 803 tests, and Nest build passed. Focused Bank
  Statement provider/screen tests passed 37 tests, Flutter analyze passed, and
  full Flutter passed 569 tests with 3 platform skips.
- `PAYMENT-STATEMENT-001`, 2026-07-20: fixed the Sao ke XLSX HTTP transport.
  The workbook service already produced valid XLSX bytes, but its controller
  returned a raw Node `Buffer` and Nest serialized that object as JSON while
  retaining the XLSX filename/header. The controller now returns
  `StreamableFile`, with regression coverage for the binary `PK` bytes and
  response headers. Validation: 111 focused MAP/controller Jest tests, full
  Nest 81 suites / 804 tests, Nest build, 72 protected Flutter consumer tests,
  production health, and an authenticated live export parsed successfully as
  a 540,952-byte XLSX workbook with one worksheet. No migration or client
  release was required.
- `PAYMENT-STATEMENT-001`, 2026-07-20: TNG classification now uses only the
  whitespace-compacted content prefix: every content starting with `TNG` is
  `PARTNER_INTERNAL`, independent of showroom code or subsequent wording. A new
  migration backfills only `AUTO` rows so manual classifications remain intact.
  Statement list, global lookup, and selected export constrain every user
  outside `FIN_ACC` to `SALES`; only `FIN_ACC` can view or edit both types.
  Validation: Prisma generate/validate, focused MAP/income-type Jest 145 tests,
  full Nest 81 suites / 811 tests, Nest build, 72 protected Flutter consumer
  tests, Flutter analyze, and diff check all passed.
- `PAYMENT-STATEMENT-001`/`PAYMENT-MONITOR-001`/`VIETQR-001`, 2026-07-22
  (OPS-12): MAP and eFAST identifiers are preserved together under
  `rawData.providerIdentifiers`, with `efastTrxId` preferred for statement
  display, search, XLSX, transfer details, and stored VietQR confirmation.
  Either source may arrive first; exact opposite-source matches enrich one
  survivor and its linked VietQR intent without publishing a second payment
  notification. Ambiguous fingerprints and conflicting identifiers stop before
  mutation. The historical repair is dry-run by default and requires immutable
  checkpoint/hash proof before apply. Validation: Prisma generate/validate,
  Nest build, 193 focused Nest tests, full Nest 84 suites / 839 tests, 4 repair
  planner tests, and 94 protected Flutter consumer tests passed. A real
  checkpoint-backed repair dry-run plus deployed staging API/XLSX proof remain
  pending.
- `UI-UX-001`, 2026-07-11: sửa race thứ hai của `AppCombobox` trên
  desktop/Windows: khi bấm chuột chọn option, `TextField` mất focus ở
  mouse-down và timer đóng overlay cũ có thể đóng menu trước mouse-up/onTap,
  khiến dropdown chỉ chọn được bằng search rồi Enter. Component giữ field và
  overlay trong cùng `TapRegion`, chỉ đóng khi click thật sự ra ngoài hoặc
  nhấn Escape/Tab, đồng thời ghi `AppLogger` cho outside dismiss. Validation:
  regression test giữ mouse-down 180ms trước mouse-up cho single-select và
  multi-select, outside-click test, 82 Flutter tests cho shared controls, Home,
  Sales Report, Sao kê, Cấn trừ, Tiền vào, VietQR, User Admin,
  design-system guard; `flutter analyze --no-pub`.
- `UI-UX-001`, 2026-07-11: sửa race của `AppCombobox` khi người dùng bấm
  trực tiếp icon kính lúp/mũi tên ở cuối filter. `TextField` có thể nhận focus
  và mở overlay trước callback của icon; icon cũ đọc trạng thái mới rồi đóng
  lại ngay trong cùng một cú click. Component dùng trạng thái tại pointer-down
  để phân biệt mở/đóng, giữ thao tác xóa filter không làm menu bật ngoài ý
  muốn, và ghi `AppLogger` cho nhánh mở/chọn/xóa/thất bại. Đã tái hiện trực
  tiếp trên Windows ở Home và Báo cáo bán hàng. Validation: regression test
  bấm suffix icon, 80 Flutter tests cho shared controls, Home, Sales Report,
  Sao kê, Cấn trừ, Tiền vào, VietQR, User Admin và design-system guard;
  `flutter analyze --no-pub`.
- `SALES-REPORT-001`/`UI-UX-001`, 2026-07-11: báo cáo mua hàng bắt buộc
  `CTKM áp dụng`; ERP tự fill `Đổi điểm thi` từ
  `payments[].partnerTransactionCode = PVDD*`, HSSV từ
  `priceSummary[].tags = PVHSSV*`, fallback `CTKM khác`, đồng thời map
  `INDIVIDUAL` về cá nhân và tự fill nhu cầu/số tiền trả góp từ payment method
  `installment`. Ba lối vào báo cáo trong cockpit cùng mở modal và header card
  của form giữ cố định ngoài vùng cuộn. Validation: focused Flutter sales-report
  widget/domain/provider tests (`21` tests), focused NestJS ERP/service tests
  (`67` tests), `flutter analyze --no-pub`, và `npm run build`.
- `SALES-REPORT-001`, 2026-07-11: auto-fill ngành hàng và `categoryType` chỉ
  exact-match node Listing có level sâu nhất với dòng tương ứng trong
  `data/categories.csv`; không dùng `NHxx` level 1, category cha,
  `productGroup`, `productType` hoặc tên sản phẩm làm fallback. Node sâu nhất
  không có level rõ ràng hoặc không map được thì để sale chọn tay; item `type=gift` vẫn lưu
  `categoryType=gift` nhưng không tự chọn ngành. Regression case
  `26071137825630` giữ Laptop và loại `NH11` Phụ kiện do SKU `231000787` là
  `NH11-01-98-01` (`gift`). Validation: focused category/service tests, toàn bộ
  sales-report tests (74 tests), backend build, focused Flutter sales-report
  tests (21 tests), and `git diff --check`.
- `SALES-REPORT-001`, 2026-07-15: production runtime artifact phải chứa đủ
  hai backend input được mount read-only tại `/app/data` là
  `data/categories.csv` và `data/email_domain.txt`. Runtime builder gom hai
  file vào một allowlist bắt buộc để thiếu file nào thì fail trước khi rsync;
  asset ảnh/âm thanh của Flutter vẫn được đóng vào client, còn file import thủ
  công và credential tiếp tục nằm ngoài server artifact. Validation: Node
  syntax check, runtime release build/manifest inspection, focused category
  tests, backend build và `git diff --check`.
- `UI-UX-001`/`FIFO-001`, 2026-07-11: mobile command cards for `Kiểm tra FIFO`
  and `Sắp xếp FIFO` keep the input, QR scan, and search/submit action in the
  same row for faster one-hand operation; the shared UI contract now records
  this rule. FIFO result cards and Sort FIFO cards also show inventory age as
  `Tồn X ngày` from the import date, and Sort FIFO result cards now match FIFO
  Check's white card, left FIFO status strip, metadata chips, copyable
  serial/location behavior, and sanitized `AppLogger` copy logs. Validation:
  focused FIFO/Sort Flutter widget tests (`8` tests, including 390x844 mobile
  geometry guards) and `flutter analyze --no-pub`.
- `FIFO-001`/`PROFILE-ADMIN-001`, 2026-07-11: FIFO BigQuery refresh now treats
  the latest valid BigQuery read as the full snapshot for BigQuery-sourced rows;
  rows missing from that snapshot are deactivated even when their SR is absent
  from the batch. Organization tree sync/seed preserves manually inactive
  nodes, legacy store sync does not reactivate manually disabled Lv4 stores,
  default Lv5 store positions stay inactive when manually disabled, and
  deactivating a parent node cascades inactive status to descendants. The
  organization-tree edit form now warns before saving an inactive node:
  `Nếu tắt đơn vị này thì các đơn vị con cũng sẽ tắt!`. Validation: focused FIFO
  inventory Jest and UserService Jest (`57` tests), backend `npm run build`,
  focused Flutter organization-tree widget test (`4` tests), and
  `git diff --check`.
- `PAYMENT-MONITOR-001`, 2026-07-11: đọc loa realtime không còn phát muộn khi
  client reconnect. `/ready` chỉ recover stream-pending notification trong
  `PAYMENT_STREAM_PENDING_RECOVERY_WINDOW_SECONDS` (mặc định 30 giây);
  notification quá window được ghi delivery log `SILENCED` với lý do
  `stream_recovery_window_expired`, và `/stream`/`/audio` cũng chặn lại để app
  cũ hoặc request muộn không phát âm thanh. Flutter upload log
  `PaymentMonitorRealtime` lên `/app-logs` cho connect/ready/reconnect/event
  để soi lỗi WebSocket client-side. Validation: focused backend
  `payment-notifications.service.spec.ts` (37 tests), backend `npm run build`,
  focused Flutter `payment_monitor_provider_test.dart` (30 tests), and
  `flutter analyze --no-pub`.
- `PAYMENT-MONITOR-001`/`PAYMENT-STATEMENT-001`, 2026-07-13: MAP và eFAST dùng
  chung transaction key chuẩn hóa từ mã sao kê ngân hàng, đồng thời cả hai
  chiều ingest đều dò các statement identifier đã lưu. Unique transaction key
  chặn race khi hai nguồn trả gần đồng thời; dữ liệu key legacy vẫn được bảo vệ
  bằng lookup hai chiều trước insert. Validation: focused MAP/eFAST service
  Jest, Nest build, Prisma validate, và `git diff --check`.
- `OPS-6`/`PAYMENT-STATEMENT-001`, 2026-07-21: Payment Monitor now keeps the
  persisted OpsHub transaction UUID separate from the provider statement number
  and sends the unique `transactionKey` with order-transfer requests. The NestJS
  endpoint resolves a stale or provider-facing id by that key before applying
  the existing scope, cutoff, pending-request, and authorization checks; missing
  rows now return Vietnamese reload guidance and emit sanitized start/resolve/
  failure logs. Validation: focused Flutter payment-monitor tests and focused
  MAP service Jest regression for stale-id resolution. Production deployment and
  live click-through remain pending.
- `PAYMENT-MONITOR-001`/`PAYMENT-STATEMENT-001`, 2026-07-13: migration cleanup
  một lần ưu tiên giữ giao dịch có mã đơn khi chỉ một bản có đơn; nếu cả hai
  cùng có đơn hoặc cùng trống thì giữ MAP, xóa eFAST. VietQR match, order audit,
  transfer request và notification đơn lẻ được chuyển sang bản giữ lại trước
  khi xóa. Migration dừng nếu pairing không còn one-to-one.
- `PAYMENT-MONITOR-001`/`PAYMENT-STATEMENT-001`, 2026-07-11: eFAST sync dùng
  ngày nghiệp vụ UTC+7 khi gọi history, parse chắc `DD-MM-YYYY`/`DD/MM/YYYY`
  theo giờ Việt Nam, và bỏ qua row eFAST nếu `trxId`/`trxRefNo` đã tồn tại
  trong dữ liệu MAP để không tạo trùng sao kê hoặc notification. Validation:
  focused MAP/eFAST service Jest, Nest build, và `git diff --check`.
- `PAYMENT-MONITOR-001`/`PAYMENT-STATEMENT-001`, 2026-07-10: eFAST sync
  tách khỏi nhịp MAP, chạy scheduler riêng random 50-60 giây/lần từ
  08:00-22:00 UTC+7 và 30 phút/lần từ 22:01-07:59 ngày hôm sau. Runtime giới
  hạn `VIETIN_EFAST_SYNC_MAX_PAGES=1`, page size 150 và tối đa một page cho
  mỗi account để giữ 2 account dưới giới hạn 20 truy vấn/5 phút của provider.
  Validation: focused MAP/eFAST service Jest, env validation Jest, Nest build,
  và `git diff --check`.
- `UI-UX-001`, `HOME-DASHBOARD-002`, `SALES-REPORT-001`,
  `PAYMENT-STATEMENT-001`, `OFFSET-ADJUSTMENT-001`, `PAYMENT-MONITOR-001`,
  2026-07-10: runtime filter dropdowns dùng chung `AppCombobox` search-box
  realtime cho single/multi select; showroom hiển thị dạng `CPxx - <Tên SR>`.
  Các primitive dropdown/select cũ bị gỡ khỏi runtime và guard chặn dùng lại.
  Trang chủ giữ cố định header dashboard, chỉ vùng KPI/công cụ bên dưới cuộn.
  Pagination dùng chung `AppPaginationControls` theo kiểu `Sao kê`/`Tiền vào`
  cho Báo cáo bán hàng, Sao kê, Cấn trừ và Tiền vào; guard chặn tạo nút
  `Trang trước`/`Trang sau` riêng trong feature UI. Validation:
  `flutter analyze --no-pub`, focused Flutter widget tests cho App form
  controls, VietQR, User Admin, Home dashboard, Sales Report hub, Design System
  guard, và `git diff --check`.
- `HOME-DASHBOARD-002`, `PAYMENT-STATEMENT-001`, `OFFSET-ADJUSTMENT-001`,
  2026-07-09: Home thêm card `Báo cáo đã mua` trong `Hành vi then chốt`; user
  có `ADMIN_SALES_REPORTS` bấm chữ để mở `/admin/sales-reports`. Card
  `Số lượng nhu cầu trả góp` mở modal chi tiết SR, Tên SA, Đối tác trả góp,
  Thành công và Ghi chú. Các card có route/modal có icon detail nhỏ ở góc phải
  mà không đổi layout card. Home `Tài chính` cho phép bấm
  `Tổng sao kê chưa có đơn hàng` để mở `/bank-statement` với filter
  `MISSING_ORDER` và auto-search. Màn `Sao kê` bỏ header
  `Giao dịch cần rà soát`; màn `Cấn trừ` bỏ card `Yêu cầu xử lý`.
  Validation: focused Home dashboard, AppRouter, Sao kê screen, Cấn trừ screen
  Flutter tests; focused Home Summary Jest; Nest build; `flutter analyze`;
  `git diff --check`.
- `HOME-DASHBOARD-002`, 2026-07-09: Khu vực `Bán hàng` trên Trang chủ thêm
  nhóm `KPI chính`, hiển thị hai dòng desktop theo danh sách KPI: doanh số
  khách hàng doanh nghiệp/cá nhân, CTKM đổi điểm thi, CTKM HSSV, nhu cầu trả
  góp, trả góp thành công, bảo hiểm mở rộng, laptop, PC bộ, PC ráp, Apple
  (iPhone, MacBook, iPad), màn hình, máy in và phụ kiện. Backend mở rộng
  `GET /home/summary` bằng các field KPI chính, dùng cùng hàm tổng hợp với
  export `Doanh số` cho revenue/category/installment và cùng scope/ngày/SA của
  các KPI bán hàng hiện tại; Flutter parse, log và render field mới.
  Validation: focused Home Summary/Sales Reports Jest (66 tests), focused Home
  dashboard Flutter widget test, backend `npm run build`,
  `flutter analyze --no-pub`, và `git diff --check`.
- `HOME-DASHBOARD-002`, 2026-07-11: Modal chi tiết `Hành vi then chốt` thêm
  cột `Mã showroom` cho bảng khách chưa mua và đơn chưa báo cáo để user được gán
  nhiều SR nhận biết rõ showroom của từng dòng. Backend trả `storeCode` trong
  `GET /home/summary/details`, Flutter parse và hiển thị theo cùng response
  detail hiện có. Follow-up đổi nhãn visible sang `Mã showroom` để khớp guard UI
  copy, đồng thời co cụm filter header Home ở viewport hẹp để nút loa không bị
  cắt mép phải. Validation: focused Home Summary Jest, focused Home
  dashboard Flutter widget test, Nest build, `flutter analyze --no-pub`,
  `flutter test --no-pub`, `git diff --check`.
- `HOME-DASHBOARD-002`, 2026-07-11: Home/Sales report cache không còn dùng
  `fetchedAt` làm ngày bán. Backend parse `orderCreatedAt` từ các field ngày ERP
  hoặc `sanitizedSnapshot.createdAt`, backfill cache/fact cũ bằng migration, date
  filter dashboard/cockpit chỉ dùng ngày bán ERP và detail `Đơn chưa báo cáo`
  không hiển thị giờ sync thay cho giờ bán. Validation: focused Home Summary,
  Sales Report ERP và Sales Reports Jest, `npx prisma validate`,
  `npm run build`, `git diff --check`.
- `HOME-DASHBOARD-002`, 2026-07-08: Card `Số khách chưa mua` và
  `Số đơn chưa báo cáo` trong nhóm `Hành vi then chốt` mở modal chi tiết khi
  bấm phần chữ. Modal dùng cùng ngày/scope/SA đang chọn, có bảng cuộn dọc và
  ngang cho màn nhỏ; khách chưa mua hiển thị Tên SA, Tên khách hàng, Loại khách
  hàng, Ngành hàng, Lý do không mua; đơn chưa báo cáo hiển thị Tên SA, Mã đơn
  hàng, Giá trị đơn, Thời gian bán. Validation: focused Home Summary
  service/controller/dto Jest, Nest build, focused Home dashboard Flutter
  widget test, `flutter analyze --no-pub`, `git diff --check`.
- `HOME-DASHBOARD-002`, 2026-07-08: `Tổng quan` desktop giữ đủ 4 card trên
  một hàng khi đủ rộng, với `Tiến độ báo cáo` + `Tiến độ sao kê` gộp bằng một
  phần ba chiều ngang và hai card doanh số mỗi card một phần ba. `Tổng quan cá
nhân` mặc định `Chưa chọn SA`, hiển thị hướng dẫn chọn SA và không tự lọc KPI
  `Bán hàng` khỏi scope showroom/node; chỉ khi chọn SA thì backend nhận
  `salesProgressUserId` và toàn bộ KPI bán hàng/hành vi chuyển sang scope cá
  nhân có guard theo showroom của SA. Scope cá nhân định danh SA bằng email,
  không dùng `sourceUserId`, mã nhân viên ERP hay generated personnel code; tiến
  độ SA chỉ lấy báo cáo mua hàng ERP đã hoàn thành, không lấy doanh số cache.
  Scope `Toàn hệ thống` vẫn trả danh sách SA để UI hiển thị card cá nhân ở trạng
  thái chưa chọn. Home mobile có pull-to-refresh dùng cùng luồng tải lại/log
  hiện tại. Validation: focused Home Summary Jest/controller/dto, focused Home
  dashboard Flutter widget test, Nest build, `flutter analyze --no-pub`,
  `git diff --check`.
- `SALES-REPORT-001`, 2026-07-07: Báo cáo mua hàng gửi metadata nguồn thao tác
  `MANUAL_ENTRY` hoặc `SYNC_LIST`; backend log source này kèm report id/showroom
  và định danh mã đơn đã sanitize, đồng thời lưu `rawResponses.entrySource` để
  truy vết report nhập tay so với report mở từ danh sách sync. Validation:
  focused SalesReportsService Jest và focused Sales Report widget test.
- `SALES-REPORT-001`, 2026-07-07: ERP order cache dùng
  `createdFromSiteDisplayName` dạng `[CP58] ...` làm source of truth duy nhất
  cho `storeCode` ngay từ list-sync/check-order/status-sync; nếu field này rỗng
  thì đơn không được map vào SR nào, dù còn `siteDisplayName`, context user hay
  owner. Default
  `ERP_ORDER_CACHE_SYNC_LIMIT` đặt về 50 đơn/ngày/lượt sync theo giới hạn hiện
  tại của ERP list để tránh HTTP 400. Validation: focused SalesReportsService
  Jest, Nest build, `git diff --check`.
- `SALES-REPORT-001`, 2026-07-07: Admin export `HVTC`/`Doanh số`/`Trả góp`
  đổi từ CSV sang Excel `.xlsx` để Excel/WPS đọc tiếng Việt ổn định; backend
  trả workbook MIME chuẩn và Flutter lưu file `.xlsx` trực tiếp. Validation:
  focused SalesReportsService Jest, Nest build, `flutter analyze --no-pub`,
  focused Sales Report widget test.
- `UI-UX-001`, 2026-07-07: Mobile AppShell drawer now pins the same app metadata
  footer as desktop sidebar: version, developer credit, and copyright below the
  scrollable menu. Validation: `flutter test --no-pub --reporter expanded
test\app_shell_route_viewport_test.dart`.
- `SALES-REPORT-001`, 2026-07-07: Cockpit match report mua thủ công theo
  `orderCode` với cache đơn trong filter hiện tại, nên đơn thủ công trùng mã sẽ
  chuyển khỏi cột chưa báo cáo sau khi reload dù metadata ngày/showroom của
  report không trùng hoàn toàn cache row. Validation: focused
  SalesReportsService Jest, Nest build, `git diff --check`.
- `SALES-REPORT-001`, 2026-07-07: ERP order cache list sync đổi sang mỗi 1
  phút, default batch 50 đơn/ngày và giữ giới hạn cấu hình tối đa 50 theo ERP list. Status sync
  mở rộng từ reported-only sang cả đơn pending trong cache chưa báo cáo, dùng
  Redis lease, concurrency, quota theo showroom, backoff theo failure count và
  không reset retry metadata khi list sync refresh đơn `PENDING`. Validation:
  focused SalesReportsService Jest và Nest build.
- `HOME-DASHBOARD-002`, 2026-07-07: Dropdown SA trong `Tổng quan cá nhân` nay
  điều khiển các KPI `Bán hàng`/`Hành vi then chốt` theo scope cá nhân của SA
  đã chọn; `Tổng quan Cửa hàng` vẫn giữ scope showroom/node nên giống nhau cho
  các user trong cùng SR và không đổi khi đổi SA; `Tài chính` cũng giữ scope ở
  header. Validation: focused Home Summary Jest, focused Home dashboard Flutter
  widget test, Nest build, `flutter analyze --no-pub`, và `git diff --check`.
- `HOME-DASHBOARD-002`, 2026-07-07: Tiến độ doanh số trên Home tách thành
  `Tổng quan cá nhân` và `Tổng quan Miền/Vùng/Cửa hàng`; backend trả thêm
  `personalSalesProgress`, `scopeSalesProgress`, danh sách SA hợp lệ trong
  scope hiện tại và `salesProgressUserId` để store manager/tài khoản quản lý
  chọn SA; danh sách trên 10 SA dùng picker có tìm kiếm. Super Admin giữ option
  `Toàn hệ thống` và nhận thêm từng node active có showroom bên dưới để lọc
  dashboard như RM/AM. Tiến độ cá nhân cũng nhận báo cáo theo
  `erpConsultantCustomId` để giảm lệch với doanh số cá nhân từ ERP order cache.
  Validation: focused Home Summary Jest, Nest build, focused
  Home/date-range/feedback Flutter widget tests, `flutter analyze --no-pub`,
  formatter check, và `git diff --check`.
- `PAYMENT-MONITOR-002`/`PAYMENT-STATEMENT-001`/`SALES-REPORT-001`,
  2026-07-07: `Tiền vào`, `Sao kê`, and `Cấn trừ` now keep pagination/list
  state controls in the filter card footer, `Sao kê` keeps select-all/selected
  export state there, `Tiền vào` warns Windows speaker operators to keep the
  machine awake, and the sales-report cockpit removes the duplicate summary
  header plus long ERP business-location text from order cards. Validation:
  focused Flutter widget tests for the four affected screens, `flutter analyze
--no-pub`, formatter check, and `git diff --check`.
- `HELP-001`, 2026-07-07: Mục lục runtime Help được sắp theo cây ổn định
  thay vì phụ thuộc thứ tự flat list từ API/DB: trang mẹ hiển thị trước, các
  trang con nằm ngay dưới mẹ theo `sortOrder`, trang gốc kế tiếp đứng sau; dòng
  quan hệ cha trong public Help dùng tên mục cha thay vì key kỹ thuật.
  Validation: focused Help widget test với dữ liệu trả về lộn thứ tự,
  focused Help analyze, full `flutter analyze --no-pub`, và `git diff --check`.
- `HOME-DASHBOARD-002`, 2026-07-07: Khu vực `Bán hàng` trên Trang chủ tách
  thành nhóm `Doanh số` và `Hành vi then chốt`. Backend trả doanh số tổng từ
  cache đơn hàng sau khi loại hủy/trả toàn bộ và trừ trả một phần, trung bình
  đơn, doanh số hoàn thành, pending và các tỉ lệ hành vi `YES`/tổng báo cáo
  cho 3 giải pháp, trải nghiệm, Zalo OA, tải App; Flutter render thành hai grid
  con và log đủ field mới qua `AppLogger`.
  Validation: focused Home Summary Jest, focused Home dashboard Flutter test,
  backend build, `flutter analyze --no-pub`, và `git diff --check`.
- `UPDATE-004`, 2026-07-06: Android/Windows update prompt now starts an
  in-app self-update flow instead of opening the browser: client downloads
  `packageUrl`, verifies SHA-256/size, logs progress/failure via `AppLogger`,
  Windows launches the Inno installer with silent args and `/OPSHUBRELAUNCH=1`
  so OpsHub opens again after silent install, and Android opens the system
  Package Installer through a FileProvider after package/signature
  checks. Deploy workflows now publish and verify package metadata on
  `/app-version`. Validation: focused Flutter update tests and focused NestJS
  app-version tests. Gap: manual Android and Windows installed-build update
  smoke remains required before release.
- `UPDATE-004`, 2026-07-10: `AppUpdateGate` now automatically starts the
  self-update action when startup/realtime/resume metadata checks find a newer
  Android, Windows, or web build. The visible gate stays on screen to show
  progress or retryable errors, and automatic install is skipped with a log when
  package metadata is incomplete. Validation: focused Flutter update gate tests.
- `PAYMENT-MONITOR-002`/`PAYMENT-STATEMENT-001`, 2026-07-07: WebSocket
  reconnect now waits for the socket `ready` handshake before resetting
  backoff, Windows speaker clients get a lightweight `/ready` fallback after
  realtime silence without restoring full-list polling, and Sao kê inline order
  saves send the stable `transactionKey` plus retry once after refresh when a
  visible row id is stale. Statement users may edit/update protected or
  cross-SR rows when the row was found by exactly one global lookup field:
  statement number, order code, exact amount, or exact transfer content; the
  backend re-verifies the lookup before writing audit history. Validation:
  `flutter test --no-pub --reporter expanded test/payment_monitor_provider_test.dart test/bank_statement_provider_test.dart`,
  `npm test -- --runInBand src/map-vietin/map-vietin.service.spec.ts`,
  backend `npm run build`, and `flutter analyze --no-pub`. Gap: live Windows
  speaker and production Sao kê click-through remain post-deploy manual smoke.
- `PAYMENT-MONITOR-002`, 2026-07-06: `Tiền vào` no longer polls the stored
  transaction list every 10 seconds or on WebSocket reconnect. Initial/user
  actions still load explicitly; payment realtime events refresh the list,
  read audio only when the Windows speaker path is eligible and enabled, and
  otherwise skip ready-audio polling. Validation: focused payment-monitor
  provider/widget tests, `flutter analyze --no-pub`, and `git diff --check`.
- `FIFO-002`, 2026-07-06: chip Serial và Vị trí trên card kết quả Kiểm tra FIFO
  nhận click chuột, touch và thao tác bàn phím để copy trên mọi nền tảng
  Flutter; chip dùng mode tương tác chung của `AppInfoChip`, có icon, tooltip,
  semantics, floating toast tiếng Việt và `AppLogger` đã sanitize. Validation:
  focused Flutter FIFO widget test (4 tests, gồm viewport 390x844), `flutter
analyze --no-pub`, và `git diff --check`.
- `PROFILE-ADMIN-001`/`PERSONNEL-001`, 2026-07-06: Lv5 positions created or
  updated from the organization-tree UI now sync their job-role catalog row in
  the same transaction, while assignment self-heals older nodes missing that
  row. Lv5 users inherit the direct parent's scope: positions under Region/Area
  can read every descendant showroom through the shared store-scope helper;
  positions under a showroom remain limited to that showroom. Admin user scope
  and the Flutter personnel-code preview follow the same parent scope.
  Validation: focused User/Common/Home Summary/Sales Reports Jest (4 suites,
  96 tests), backend `npm run build`, focused Flutter admin tree test (12
  tests), `flutter analyze --no-pub`, and `git diff --check`.
- `HOME-DASHBOARD-002`, 2026-07-06: Khu vực `Bán hàng` thêm card
  `Báo cáo chưa mua` giữa `Số đơn đã báo cáo` và `Số đơn chưa báo cáo`. Backend
  trả `notPurchasedReports` từ `HomeSummaryReportFact` có
  `reportType=NOT_PURCHASED`; Flutter log và hiển thị field này, đồng thời giữ
  7 KPI trên một hàng ở desktop rộng. Validation: focused Home Summary Jest,
  focused Home dashboard Flutter test, backend build, `flutter analyze
--no-pub`, và `git diff --check`.
- `SALES-REPORT-001`, 2026-07-06: Hotfix backend status sync chỉ chọn các đơn
  `PURCHASED` đã được báo cáo trong `SalesReport` để gọi ERP status, không còn
  lấy batch pending/completed trực tiếp từ `SalesReportErpOrderCache` nên đơn
  chưa báo cáo không làm phình backlog khi pending 2-3 ngày. Validation:
  `npm test -- --runInBand src/sales-reports/sales-reports.service.spec.ts`,
  `npm run build`, và `git diff --check`.
- `HOME-DASHBOARD-002`, 2026-07-06: Home dashboard mặc định chọn daterange hôm
  nay ngay khi mở trang, nên request đầu tiên gửi `startDate=endDate` và log
  `hasExplicitDateRange=true`. Các KPI/card doanh số/tài chính có chiều ngang
  hẹp dùng số tiền compact `M`/`B` để tránh wrap/ellipsis, trong khi màn chi
  tiết vẫn giữ format đầy đủ. Validation: focused
  `flutter test --no-pub --reporter expanded test\home_dashboard_test.dart`,
  `flutter analyze --no-pub`, và `git diff --check`.
- `SALES-REPORT-001`/`UI-UX-002`, 2026-07-06: Cockpit `Báo cáo bán hàng` bỏ hai
  action trùng `Xuất file`/`Danh sách`, thay picker một ngày bằng daterange chung
  và giữ contract khoảng trống mặc định 30 ngày gần nhất. Card/nút/filter đứng
  yên; chỉ vùng danh sách trong từng cột tự cuộn độc lập. `Vận hành` mở thẳng
  `/sales-reports`; `/reports` chỉ redirect tương thích; `Danh sách báo cáo
bán hàng` chuyển vào `Quản trị` theo `ADMIN_SALES_REPORTS`. API cockpit nhận
  `startDate`/`endDate`, giữ field `date` tương thích client cũ và từ chối khoảng
  ngày đảo ngược bằng thông báo tiếng Việt. Validation: focused Flutter
  navigation/admin/sales-report/home/design-guard tests, full `flutter test
--no-pub --reporter compact --concurrency=1` (360 tests), mobile widget
  375x812, `flutter analyze --no-pub`, focused Nest sales-report/home-summary
  Jest, full backend `npm test -- --runInBand` (52 suites, 467 tests),
  `npm run build`, và `git diff --check`.
- `SALES-REPORT-001`, 2026-07-07: Cockpit thêm nút `Báo cáo mua thủ công` nằm
  ngang với `Báo cáo chưa mua`. Nút mới mở lại form mua hàng hiện hữu để sale
  tự nhập/quét và kiểm tra mã đơn qua ERP trước khi gửi; không thay đổi loại
  báo cáo hay nới validation backend. Validation: focused Flutter sales-report
  widget test, `flutter analyze --no-pub`, và `git diff --check`.
- `SALES-REPORT-001`/`UI-UX-001`, 2026-07-07: Cockpit và danh sách quản trị
  `Báo cáo bán hàng` mặc định chọn ngày hiện tại giống Trang chủ; request đầu
  tiên gửi ngày bắt đầu/kết thúc cùng ngày đó. `AppDateRangeDropdown` thay hai
  date picker riêng bằng một action `Chọn khoảng ngày`, cho phép chọn cả hai mốc
  và áp dụng một lần trong range picker; preset nhanh đổi từ `Hôm nay` sang
  `Hôm qua` vì màn mặc định đã là ngày hiện tại, còn nhập tay vẫn được giữ.
  Validation: focused Flutter date-range/sales-report widget tests, shared
  consumer regression tests cho Home/Sao kê/Cấn trừ/Tiền vào,
  `flutter analyze --no-pub`, và `git diff --check`.
- `SALES-REPORT-001`, 2026-07-07: Danh sách quản trị `Báo cáo bán hàng` tách
  filter/action thành toolbar riêng và thêm filter `SR` cho user được gán nhiều
  showroom. Mặc định `Tất cả SR` giữ `storeIds` rỗng để backend lấy toàn bộ
  scope được gán; chọn từng SR sẽ gửi `storeIds` tương ứng cho cả list và export.
  Validation: `flutter test --no-pub --reporter expanded
test\sales_report_hub_test.dart` (19 tests), `flutter analyze --no-pub`, và
  `git diff --check`.
- `HOME-DASHBOARD-002`/`SALES-REPORT-001`, 2026-07-06: Dashboard đưa
  `Tổng quan` lên đầu với donut báo cáo, sao kê và doanh số ngày/tuần/tháng;
  bỏ progress bar, đồng bộ chiều cao KPI và bổ sung các icon còn thiếu. Doanh
  số thực đạt chỉ cộng báo cáo mua hàng ERP đã hoàn thành, trừ hoàn trả trước
  khi chia VAT 8%. Backend lưu lifecycle/return khi check và submit, rồi rà
  pending cùng completed 30 ngày gần nhất mỗi 20 phút với batch 50,
  concurrency 2, quota 40/10 có bù slot và Redis lease. Thêm
  `ADMIN_SALES_TARGETS`, API/màn Quản lý doanh số theo showroom/tháng và target
  cá nhân SA. Validation: Prisma format/validate/generate; focused Nest Jest
  (5 suites, 56 tests); `npm run build`; full Flutter regression (360 tests);
  `flutter analyze --no-pub`; Web/Windows release build; local web smoke ở
  428×844; `node --check scripts/opshub-web-visual-smoke.mjs`;
  `git diff --check`. Windows app đã launch được nhưng update gate của phiên
  cài đặt hiện tại chặn kiểm tra sâu dashboard; chưa chạy live ERP, apply
  migration staging hay staging visual smoke trong lượt local này.
- `SALES-REPORT-001`, 2026-07-08: Nhịp sync trạng thái ERP và re-check pending
  mặc định hạ từ 20 phút xuống 5 phút để trạng thái hoàn thành lên dashboard
  nhanh hơn, vẫn giữ batch/quota/concurrency và Redis lease hiện có. Validation:
  focused `sales-reports.service.spec.ts`, `npm run build`, và
  `git diff --check`.
- `SALES-REPORT-001`, 2026-07-16: Background status sync giới hạn theo ngày
  Việt Nam: pending tối đa 3 lượt/ngày, mỗi lượt cách nhau ít nhất 60 phút;
  completed kiểm tra lại sau 2 ngày và chỉ trong 10 ngày từ ngày bán. Pending và
  completed đều ưu tiên ngày bán gần nhất đến ngày xa nhất; pending chuyển
  completed mở đầu chu kỳ kiểm tra completed 2 ngày. Success/failure của pending
  đều tiêu lượt; check/submit do user vẫn bypass quota và persist
  cancel/return/partial-return mới nhất. Validation: focused
  `sales-reports.service.spec.ts`, `npm run build`, và `git diff --check`.
- `SALES-REPORT-001`, 2026-07-18: Background status sync chỉ chọn đơn pending
  sau ít nhất 3 giờ kể từ `orderCreatedAt`; query loại đơn mới khỏi batch và
  service giữ guard `pending_age` để không gọi ERP khi timestamp thiếu hoặc chưa
  đủ tuổi. Log sync ghi `pendingMinAgeHours` và `skippedPendingAge`. Validation:
  focused `sales-reports.service.spec.ts`, `npm run build`, và `git diff --check`.
- `SALES-REPORT-001`, 2026-07-16: Sau `check-order`, đơn còn trạng thái chưa
  thanh toán phải khóa phần nhập và nút `Gửi báo cáo`, hiện đúng toast hướng dẫn
  vào SPOS thanh toán lại hoặc hủy đơn, đồng thời đưa phần thân modal về đầu.
  Backend submit cũng re-check và từ chối tạo bản ghi nếu client bỏ qua chốt UI.
  Validation: focused widget test `Báo cáo blocks unpaid order submission and
  returns modal to top`, focused Nest test, `flutter analyze --no-pub`,
  `npm run build`, và `git diff --check`.
- `HOME-DASHBOARD-002`, 2026-07-05: Home tách KPI thành `Bán hàng` và
  `Tài chính` dùng chung ngày/scope. Bán hàng bỏ `Tổng số báo cáo hợp lệ`, đổi
  nhãn thành `Tỉ lệ báo cáo`, thêm tỉ lệ chuyển đổi theo tổng số đơn trên tổng
  báo cáo. Tài chính tổng hợp tiền chuyển khoản và số sao kê có/chưa có đơn từ
  `MapVietinTransaction`. Hai section dùng feature riêng trên cây tổ chức; SA,
  Kỹ thuật, Kho và Thu ngân chỉ chọn cá nhân hoặc từng showroom được gán, trong
  đó tài chính cá nhân chỉ tính sao kê gắn với đơn cá nhân. Scope quản lý theo
  node đã chọn và Super Admin có toàn hệ thống. Validation: focused Nest Jest
  (4 suites, 58 tests), `npm run build`, full Flutter regression (352 tests),
  `flutter analyze --no-pub`, và `git diff --check`.
- `UI-UX-002`/`NAV-GROUPS-TOP-RIGHT-TOAST`, 2026-07-05: sidebar và Vận hành
  dùng chung nhóm `Bán hàng`, `Kho`, `Tài chính`, `Kỹ thuật`; `Quản trị` chuyển
  lên Tổng quan và sở hữu `Cập nhật tồn kho`/`Lịch sử FIFO`. Toàn bộ thông báo
  tạm thời đi qua toast nổi góc trên phải, rộng tối đa 360px; source guard chặn
  việc thêm lại `showSnackBar`. Validation: focused navigation/toast/route
  widget tests, full Flutter regression (352 tests), `flutter analyze --no-pub`,
  `node --check scripts/opshub-web-visual-smoke.mjs`, và `git diff --check`.
- `UI-UX-001`/`MOBILE-NOTIFICATIONS-NAV-BACK-SIZING`, 2026-07-05: mobile
  notification entry is now a full `/notifications` shell route with bottom
  navigation visible, mobile header no longer renders a duplicate notification
  bell, Android system back returns to the previous shell route before
  double-back exit, shared action/filter/touch tokens cover 48/44/52/56/80dp
  sizing, and desktop account chip shows staff name plus SR beside the avatar
  while tablet keeps the compact avatar and mobile keeps identity in the bottom
  `Tài khoản` destination.
  Validation:
  `flutter test --no-pub --reporter expanded test\app_nav_model_test.dart test\app_shell_route_viewport_test.dart test\app_buttons_test.dart test\app_theme_tokens_test.dart test\home_avatar_test.dart`,
  `flutter analyze --no-pub`, and `git diff --check`.
- `UI-UX-001`/`HEADER-ACTION-CONSOLIDATION`, 2026-07-04: Home no longer renders
  a separate `HomeSummaryToolbar`; the scope selector, date picker, refresh
  status, stale-data banner, and speaker status now live inside
  `HomeSummaryHeader`. Sales Report admin also moves report type, date range,
  reload, and export controls into the shared workspace header instead of a
  standalone action card. Bank Statement and Offset Adjustment move their
  list-level select/count/page controls into the page header while keeping
  actual filter forms as separate work areas. Validation:
  `flutter test --no-pub --reporter expanded test\home_dashboard_test.dart test\home_feedback_action_test.dart test\sales_report_hub_test.dart test\report_workspace_screen_test.dart`,
  `flutter test --no-pub --reporter expanded test\bank_statement_screen_test.dart test\offset_adjustment_screen_redesign_test.dart`,
  `flutter analyze --no-pub`, and `git diff --check`.
- `HOME-DASHBOARD-001`/`SCOPE-DROPDOWN-SPEAKER-STATUS`, 2026-07-04: Home
  scope pill now opens a real selector, switches between `ALL` and `OWN`, and
  reloads `/home/summary` with the selected `scope`. Home no longer renders the
  payment-speaker switch/help card; it shows a compact `Loa đang bật/tắt`
  header status that toggles the existing speaker preference and logs the
  branch. Validation: focused
  `flutter test --no-pub --reporter expanded test\home_dashboard_test.dart test\home_feedback_action_test.dart test\warranty_redesign_test.dart test\sort_screen_redesign_test.dart test\vietqr_screen_test.dart test\settings_screen_redesign_test.dart test\admin_menu_screen_test.dart test\help_screen_test.dart test\personnel_catalog_admin_screen_test.dart test\fifo_check_redesign_test.dart test\sales_report_hub_test.dart test\report_workspace_screen_test.dart`
  (49 tests), `flutter analyze --no-pub`,
  `npm test -- --runInBand src/home-summary/home-summary.service.spec.ts src/home-summary/home-summary.controller.spec.ts`,
  `npm run build`, and `git diff --check`.
- `UI-UX-001`/`HEADER-COPY-CLEANUP`, 2026-07-04: auth, Home, FIFO, Sort,
  Warranty, VietQR, Admin, Help, Settings, Sales Report, and Tiền vào headers
  now remove duplicated guide paragraphs and keep title, status chips, controls,
  and operational state as the visible surface. Detailed instructions remain in
  the Help area instead of hero/header cards. Validation: same focused Flutter
  test set, `flutter analyze --no-pub`, and `git diff --check`.
- `UI-UX-001`/`FIFO-HISTORY-STATE-VIEWPORT`, 2026-07-04: FIFO History loading,
  empty, and error panels now sit inside a scroll-safe viewport so compact
  mobile retry states do not overflow after shared button/input density changes.
  Validation: focused
  `flutter test --no-pub --reporter expanded test\fifo_history_redesign_test.dart`
  (3 tests).
- `HOME-DASHBOARD-001`/`MOCKUP-POLISH`, 2026-07-04: Home dashboard UI aligned
  with the supplied desktop/tablet/mobile mockup while preserving the existing
  `/home/summary` data contract. The dashboard now starts directly with
  `Trang chủ vận hành`, scope/date/update controls, compact KPI cards, a donut
  plus 0/50/100 progress bar, and a four-item quick-tools panel. Mobile/tablet
  shell keeps bottom navigation and now exposes the collapsed navigation drawer
  through the hamburger entry while retaining support, notification, account,
  and payment-delivery metrics behavior. Validation: changed-file
  `dart format --output=none --set-exit-if-changed`, `git diff --check`,
  `flutter analyze --no-pub`, and focused
  `flutter test --no-pub --reporter expanded test\home_dashboard_test.dart test\home_feedback_action_test.dart test\home_avatar_test.dart test\app_shell_route_viewport_test.dart`
  (21 tests).
- `HOME-DASHBOARD-001`, 2026-07-04: completed Batch 3
  `Home Dashboard Theo Scope` from
  `docs/OPSHUB_MASTER_IMPLEMENTATION_PLAN.md`. Home now consumes
  `GET /home/summary?date=YYYY-MM-DD`, backend persists dedicated
  `HomeSummaryOrderFact` and `HomeSummaryReportFact` rows sourced from
  `SalesReport` plus `SalesReportErpOrderCache`, and the Flutter Home screen
  renders the new dashboard structure
  `HomeSummaryPage -> Header -> Toolbar -> SummaryCardGrid -> ReportProgressPanel`
  while keeping `/operations` as the follow-up action surface. Scope reuse stays
  anchored to `SalesReportsService`, canceled orders remain excluded from the
  metrics, and the KPI label is the safer `Tỷ lệ phủ báo cáo`. Validation:
  `npx prisma validate`, `npx prisma generate`, `npm run build`,
  `npm test -- --runInBand src/home-summary/home-summary.service.spec.ts src/home-summary/home-summary.controller.spec.ts`,
  `flutter analyze --no-pub`, focused
  `flutter test --no-pub --reporter expanded test\home_dashboard_test.dart test\home_feedback_action_test.dart test\home_avatar_test.dart test\app_nav_model_test.dart`
  (20 tests), and `git diff --check`.
- `UI-UX-001`/`AUDIT-DUPLICATE-TITLES`, 2026-07-04: completed the
  TopBar/content duplicate-title acceptance item from
  `docs/UI_UX_AUDIT_PLAN.md`. The shell top bar remains the owner of
  destination labels, while feature content now uses task/status-specific
  headings such as `Công cụ theo quyền`, `Giao dịch cần rà soát`, `Yêu cầu xử
lý`, `Chia sẻ phản hồi`, `Tùy chọn thiết bị`, `Lối vào báo cáo`, and `Đơn cần
báo cáo`. `design_system_migration_guard_test.dart` now prevents feature
  screens from reusing an exact shell destination label as a heading/card title.
  Validation: changed-file `dart format`,
  `dart format --output=none --set-exit-if-changed`, focused
  `flutter test --no-pub --reporter expanded test\admin_menu_screen_test.dart test\bank_statement_screen_test.dart test\feedback_screen_test.dart test\offset_adjustment_screen_redesign_test.dart test\settings_screen_redesign_test.dart test\report_workspace_screen_test.dart test\sales_report_hub_test.dart test\design_system_migration_guard_test.dart`
  (44 tests), `git diff --check`, `flutter analyze --no-pub`, and full
  `flutter test --no-pub --reporter compact`.
- `UI-UX-001`/`AUDIT-DESKTOP-CONTENT-WIDTH`, 2026-07-03: completed the
  desktop child-screen layout acceptance item from
  `docs/UI_UX_AUDIT_PLAN.md`. `AppResponsiveContent` and
  `AppResponsiveScrollView` now default to the explicit
  `AppLayoutTokens.contentMaxWidth` cap, feature screens are guarded against
  bypassing the shared responsive wrappers, and widget tests measure the
  desktop constraints so pages do not stretch across the full window.
  Validation: changed-file `dart format`,
  `dart format --output=none --set-exit-if-changed`, focused
  `flutter test --no-pub --reporter expanded test\app_layout_test.dart test\design_system_migration_guard_test.dart`,
  `git diff --check`, `flutter analyze --no-pub`, and full
  `flutter test --no-pub --reporter compact`.
- `UI-UX-001`/`AUDIT-SIDEBAR-GROUPS`, 2026-07-03: completed the sidebar
  grouping acceptance item from `docs/UI_UX_AUDIT_PLAN.md`. Desktop AppShell
  sidebar now renders visible sections `Tổng quan`, `Nghiệp vụ`, and `Cấu hình`
  while keeping flat navigation, no row chevrons, and the left selected
  indicator from the earlier sidebar polish batch. Validation: changed-file
  `dart format`, `dart format --output=none --set-exit-if-changed`,
  `git diff --check`, `flutter analyze --no-pub`, focused
  `flutter test --no-pub --reporter expanded test\app_shell_route_viewport_test.dart`
  (5 tests), and full `flutter test --no-pub --reporter compact` (321 tests).
- `UI-UX-001`/`AUDIT-LOGOUT-CONFIRM`, 2026-07-03: completed the logout
  confirmation acceptance item from `docs/UI_UX_AUDIT_PLAN.md`. AppShell account
  menu and Profile session-card logout now open the shared
  `Xác nhận đăng xuất` dialog before revoking the current session; choosing
  `Ở lại` keeps the session untouched, while confirming continues through the
  existing `AuthProvider.logout()` flow and `/login` navigation. AppLogger now
  records requested/cancelled/confirmed branches in addition to existing
  start/success/failure logout logs. Validation: changed-file `dart format`,
  `dart format --output=none --set-exit-if-changed`, `git diff --check`,
  `flutter analyze --no-pub`, focused
  `flutter test --no-pub --reporter expanded test\app_shell_route_viewport_test.dart test\profile_screen_test.dart test\app_buttons_test.dart`
  (9 tests), and full `flutter test --no-pub --reporter compact` (321 tests).
- `UI-UX-001`/`AUDIT-MOBILE-NOTIFICATIONS`, 2026-07-04: completed the remaining
  Phase 2 mobile bottom navigation item from `docs/UI_UX_AUDIT_PLAN.md`.
  Mobile shell navigation now stays limited to `Trang chủ`, `Thông báo`, and
  `Tài khoản`; tapping `Thông báo` opens the shared notification panel as a
  bottom sheet, reuses the global notification provider/read-state flow, and
  logs selected/opened/skipped/failed branches through `AppLogger` without
  introducing a placeholder inbox route. Validation: changed-file `dart format`,
  `dart format --output=none --set-exit-if-changed`, `git diff --check`,
  `flutter analyze --no-pub`, focused
  `flutter test --no-pub --reporter expanded test\app_nav_model_test.dart test\app_shell_route_viewport_test.dart test\design_system_migration_guard_test.dart test\bank_statement_screen_test.dart`
  (32 tests), and full `flutter test --no-pub --reporter compact` (327 tests).
- `UI-UX-001`/`AUDIT-TASKS-RETIRE`, 2026-07-03: completed the active Phase 2
  Tasks-retirement slice from `docs/UI_UX_AUDIT_PLAN.md`. The duplicated
  `TasksScreen` and `tasks_screen_redesign_test.dart` were removed,
  `AppNavModel` no longer carries `showInTasks`, Home now resolves the
  permission-aware workspace catalog through
  `visibleWorkspaceDestinations(user)`, mobile bottom nav removes `Tác vụ`, and
  legacy `/tasks` deep links redirect to `/home`. The default authenticated web
  visual-smoke inventory now has 36 shell routes, or 80 route/viewport checks
  across desktop and mobile. Validation: changed-file `dart format`,
  `dart format --output=none --set-exit-if-changed`,
  `node --check scripts\opshub-web-visual-smoke.mjs`, `git diff --check`,
  `flutter analyze --no-pub`, focused
  `flutter test --no-pub --reporter expanded test\app_nav_model_test.dart test\app_shell_route_viewport_test.dart test\design_system_migration_guard_test.dart test\home_feedback_action_test.dart`
  (32 tests), and full `flutter test --no-pub --reporter compact` (319 tests).
- `UI-UX-001`/`AUDIT-FIFO-RECENTS`, 2026-07-03: completed Phase 4C recent
  search cache from `docs/UI_UX_AUDIT_PLAN.md`. FIFO Check now loads and saves
  up to five normalized SKU/serial keywords in environment-namespaced local
  storage, shows recent-search chips only while the input is focused, and
  selecting a chip fills the field and runs the check. Cache load/save/selection
  logs use counts and query lengths, not raw SKU/serial values. Validation:
  changed-file `dart format --output=none --set-exit-if-changed`,
  `git diff --check`, `flutter analyze --no-pub`, focused
  `flutter test --no-pub --reporter expanded test\fifo_check_redesign_test.dart`
  (3 tests), and full `flutter test --no-pub --reporter compact` (319 tests).
- `UI-UX-001`/`AUDIT-SIDEBAR-INDICATOR`, 2026-07-03: completed Phase 4B
  sidebar selected-state polish from `docs/UI_UX_AUDIT_PLAN.md`. Desktop
  sidebar items now keep the menu block transparent and show selection with a
  left 4x28 indicator, selected semantics, and high-contrast foreground; the
  existing AppShell navigation logging remains unchanged. Validation:
  changed-file `dart format --output=none --set-exit-if-changed`,
  `git diff --check`, `flutter analyze --no-pub`, focused
  `flutter test --no-pub --reporter expanded test\app_shell_route_viewport_test.dart`
  (3 tests), and full `flutter test --no-pub --reporter compact` (318 tests).
- `UI-UX-001`/`AUDIT-SKELETON-SHIMMER`, 2026-07-03: completed Phase 4A
  component polish from `docs/UI_UX_AUDIT_PLAN.md`. Shared `AppListSkeleton`
  blocks now animate a moving shimmer gradient while respecting
  `MediaQuery.disableAnimations`; existing loading-state consumers keep using
  the same component. Validation: changed-file
  `dart format --output=none --set-exit-if-changed`, `git diff --check`,
  `flutter analyze --no-pub`, focused
  `flutter test --no-pub --reporter expanded test\app_form_controls_test.dart`
  (6 tests), and full `flutter test --no-pub --reporter compact` (317 tests).
- `UI-UX-001`/`AUDIT-FINANCE-STRIPS`, 2026-07-03: completed Phase 3C header
  cleanup for the finance workspaces listed in `docs/UI_UX_AUDIT_PLAN.md`.
  `PaymentMonitorScreen`, `OffsetAdjustmentScreen`, and `BankStatementScreen`
  now use compact title/status strips instead of large intro cards; existing
  store/sync/review/filter status chips and the offset refresh action remain.
  Existing `AppLogger` coverage in the three providers remains the runtime
  proof source. Validation: changed-file
  `dart format --output=none --set-exit-if-changed`, `git diff --check`,
  `flutter analyze --no-pub`, focused
  `flutter test --no-pub --reporter expanded test\payment_monitor_screen_redesign_test.dart test\offset_adjustment_screen_redesign_test.dart test\bank_statement_screen_test.dart`
  (6 tests), and full `flutter test --no-pub --reporter compact` (316 tests).
- `UI-UX-001`/`AUDIT-HOME-WELCOME`, 2026-07-03: completed a small Phase 3B
  Home header batch from `docs/UI_UX_AUDIT_PLAN.md`. Home now renders the user
  greeting as a compact `home-welcome-strip` instead of a large surface card,
  keeping the avatar, staff name, assigned showroom summary, and existing
  `Home command center resolved` `AppLogger` proof. Validation: changed-file
  `dart format --output=none --set-exit-if-changed`, `git diff --check`,
  `flutter analyze --no-pub`, focused
  `flutter test --no-pub --reporter expanded test\home_feedback_action_test.dart test\home_avatar_test.dart test\app_shell_route_viewport_test.dart`
  (14 tests), and full `flutter test --no-pub --reporter compact` (316 tests).
  Remaining header cleanup: finance/report sub-screen intro cards.
- `UI-UX-001`/`AUDIT-HEADER-CLEAN`, 2026-07-03: completed a small Phase 3A
  header-clean batch from `docs/UI_UX_AUDIT_PLAN.md`. `/fifo-menu` now renders
  the FIFO action grid or permission empty state directly under `AppShell`
  without `_FifoMenuHeader`, while keeping the existing permission resolution
  and `AppLogger` visible/hidden-count logs. `/warranty-main` now renders the
  BH/SC action grid directly and removes `_WarrantyMainHeader` plus its
  now-dead `onBackToHome` route plumbing. Validation: changed-file
  `dart format --output=none --set-exit-if-changed`, `git diff --check`,
  `flutter analyze --no-pub`, focused
  `flutter test --no-pub --reporter expanded test\app_shell_route_viewport_test.dart test\fifo_menu_redesign_test.dart test\warranty_redesign_test.dart`
  (9 tests), and full `flutter test --no-pub --reporter compact` (316 tests).
  Remaining header cleanup: Home command panel and other finance or report
  sub-screen intro cards.
- `UI-UX-001`/`AUDIT-QUICK-WINS`, 2026-07-03: completed Phase 1 from
  `docs/UI_UX_AUDIT_PLAN.md`. AppShell support keeps the Seatalk QR/open-link
  flow but no longer renders the raw invite URL, adds a copy-link action with
  sanitized `AppLogger` start/success/failure logs, and keeps the URL token out
  of log context. Desktop sidebar flat navigation no longer shows a chevron on
  each row. Home, Profile, and Offset Adjustment fallbacks now say
  `Chưa được gán Showroom` instead of `Chưa có SR được gán`. FIFO Check keeps
  its command card and result panel but hides the pre-search status chips until
  a result exists. Validation: changed-file
  `dart format --output=none --set-exit-if-changed`, `git diff --check`,
  `flutter analyze --no-pub`, focused
  `flutter test --no-pub --reporter expanded test\home_feedback_action_test.dart test\fifo_check_redesign_test.dart test\profile_screen_test.dart test\offset_adjustment_screen_redesign_test.dart`
  (13 tests), and full `flutter test --no-pub --reporter compact` (316 tests).
- `UI-UX-001`, 2026-07-01: started the OpsHub Redesign System 2026 repo import
  with Batch 1 foundation work. Authenticated routes now render inside a shared
  responsive `AppShell`: desktop persistent sidebar, tablet rail, mobile app bar
  plus bottom navigation for `Trang chủ`, `Tác vụ`, and `Tài khoản`. Added the
  `/tasks` workspace index, later retired by the 2026-07-03 UI audit because
  Home became the canonical workspace catalog, and added a shared
  permission-aware nav model that hides unavailable destinations and logs
  visible/hidden counts through `AppLogger`,
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
  mobile state that originally still showed `Tác vụ`; the later UI audit
  retired that tab so runtime bottom nav is `Trang chủ`/`Tài khoản`. Figma QA
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
- `UI-UX-001`/`TASKS-INDEX`, 2026-07-03: `/tasks` was retired from the active
  runtime contract after the UI audit found it duplicated Home. `TasksScreen`,
  `tasks_screen_redesign_test.dart`, and `showInTasks` were removed; Home now
  uses `AppNavModel.visibleWorkspaceDestinations(user)`, mobile bottom nav
  removes `Tác vụ`, and legacy `/tasks` deep links redirect to `/home`.
  Historical Figma Tasks Workspace frames `482:2`, `482:75`, and `482:145`
  remain as retired rollback references, not active runtime frames.
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
- `UI-UX-001`/`AUTH-002`, 2026-07-04: login/auth layout polish aligned the
  public auth shell with the supplied desktop/mobile mockup. Desktop auth now
  uses a 56/44 split from 1024px with a denser brand panel for tablet
  landscape; mobile hides the brand panel, shows the shared brand header with
  `Kết nối nguồn lực. Đồng bộ vận hành.`, keeps the login card full-width and
  bounded, and changes `Quên mật khẩu`/`Đăng ký`/`Hướng dẫn` from stacked
  outline buttons to compact link actions below the primary CTA. Shared tokens
  now cover auth input height, card padding, control radius, benefit icon
  sizing, card shadow, and link button focus/hover states. Focused viewport
  proof covers 1440x900, 1024x768, 768x1024, 460x920, and 390x844 with
  screenshots under `output/playwright/auth-login-*.png`. Validation in this
  patch: `dart format --output=none --set-exit-if-changed` on changed Dart
  files, `flutter test --no-pub --reporter expanded
test\auth_pre_shell_redesign_test.dart test\app_shell_route_viewport_test.dart
test\app_theme_tokens_test.dart`, `flutter analyze --no-pub`,
  `flutter build web --debug --no-pub`, and local Playwright screenshot capture
  against the debug web build. Local screenshot browser console still reports
  expected API/app-version errors because no backend was served with the static
  web build; the screenshots are visual layout proof, not API smoke proof.
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
  runtime inventory. The later 2026-07-03 UI audit retired the `Tác vụ` bottom
  tab in favor of Home as the workspace catalog. Mobile/tablet each expose 40
  active runtime frames plus 2 hidden retired frames; desktop now exposes 40 unique active runtime groups
  after archiving superseded duplicate desktop VietQR (`96:2`) and Sao kê
  (`107:2`) frames as hidden `Archived / ...` nodes. Duplicate groups and
  visible retired desktop frames both verify as empty.
- `UI-UX-001`, 2026-07-03: added repeatable web visual smoke automation in
  `scripts/opshub-web-visual-smoke.mjs`. The script checks public auth routes
  before login, then logs in through the live API using env-provided
  credentials, seeds the web session without committing secrets, captures
  ignored screenshots, and checks route hash, console/page errors, rendered
  Flutter viewport size, and visible horizontal overflow while ignoring Flutter
  semantics-only overflow nodes. The default live staging smoke now runs 86
  checks across desktop `1440x900` and mobile `390x844`: 3 public routes
  (`/login`, `/register`, `/forgot-password`), 1 pending auth route
  (`/assignment-pending`) rendered from a tokenless cached pending session, plus
  all 39 authenticated shell routes in `AppRouter`, including Home,
  Operations, Profile, Admin, FIFO, BH/SC, VietQR, Payment Monitor web
  fallback, Sao kê, Cấn trừ, Góp ý, Report/Sales Report, Help Content admin,
  and Settings.
  Follow-up guard coverage in
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
  one documented BH/SC detail skip, plus focused design-system guard. Automation
  follow-up: pass `OPSHUB_VISUAL_SMOKE_WARRANTY_RECEIPT` when a stable staging
  receipt should be included in future recurring visual smoke.
  Physical acceptance on staging build `2026.07.03.98+200098` then passed on
  real devices: Android route-switch ghost-frame regression, iOS Safari/PWA
  camera preview and scan, QR/Code 128/Data Matrix scanning across FIFO, Sort,
  BH/SC, VietQR, and Sales Report, BH/SC original multi-image upload including
  near-limit and over-limit images, Sales Report/Admin compact filters and
  export dropdown with Excel open, Organization Tree search by business code,
  abbreviation, and node name, plus Windows staging update/install,
  route-switch, and Tiền vào speaker smoke.
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
  cache/report scope. Purchased-order category auto-fill only exact-matches the
  deepest Listing category node against `data/categories.csv`; level-1 `NHxx`,
  category cha and product group/type/name fallbacks are not auto-fill signals.
  This keeps unrelated Laptop/PC labels on a Logitech B100 mouse from selecting
  extra groups. It
  reuses the existing purchased `check-order` flow when a user opens an
  unreported order dialog. Cockpit filters by ERP order creation date, SR, and
  user, with exports sharing the selected cockpit filters; `fetchedAt` is sync
  metadata only and must not pull old orders into the current day. Flutter reads
  the DB cache on open or
  manual reload, then refreshes from the same scoped API when the Go WebSocket
  forwards `SALES_REPORT_ORDERS_UPDATED` for a relevant user/SR/date; the
  event also fires when scheduled sync backfills missing store/node mapping for
  older cache rows. The admin export surface also includes `Trả góp`, which
  filters `installmentNeed = true` and exports Vietnamese installment columns
  plus the derived final payment method (`Chưa mua hàng` for `NOT_PURCHASED`,
  otherwise `Trả góp`/`Trả thẳng` from ERP methods). Validation:
  `npx prisma validate`, `npx prisma generate`,
  `npm test -- --runInBand src/sales-reports`
  (37 tests), `npm run build`, Go realtime `go test ./...`,
  `flutter test --no-pub --reporter expanded test\sales_report_hub_test.dart`
  (16 tests), focused `dart analyze` on changed sales-report files, and
  `git diff --check` (CRLF warnings only).
- `SALES-REPORT-001`, 2026-07-06: OpsHub adds outbound sales-report BigQuery
  sync for Looker Studio. The backend full-refreshes three BigQuery tables
  from the runtime DB: report fact, order item fact, and payment fact, using
  Vietnamese labels aligned with the admin export while keeping raw codes for
  filtering/reconciliation. Admins with `ADMIN_SALES_REPORTS` can trigger
  `POST /api/sales-reports/admin/bigquery-sync`; scheduled sync runs daily at
  07:00 Vietnam time only when `SALES_REPORT_BIGQUERY_SYNC_ENABLED=true`.
  Validation: focused Nest
  sales-report BigQuery sync tests and backend build.
- `SALES-REPORT-001`, 2026-07-07: `Doanh số` export chỉ cộng các báo cáo có
  tick `Có nhu cầu trả góp` và số đơn trả góp thành công theo trạng thái báo cáo
  bán hàng (`installmentStatus`, fallback `NORMAL_INSTALLMENT`), then moves
  installment reasons to the final column. BigQuery sync now also writes
  `revenue_by_store`, with one revenue summary row per store/showroom instead
  of one all-store total row. Validation: focused Nest sales-report
  export/BigQuery sync tests and backend build.
- `SALES-REPORT-001`, 2026-07-07: đơn ERP có `grandTotal <= 0` được xem là đơn
  vận hành nội bộ và bị loại khỏi báo cáo. Backend persist
  `excludedAt`/`exclusionReason = ERP_ORDER_ZERO_VALUE_INTERNAL` trên
  `SalesReportErpOrderCache`, đánh dấu report mua hàng cùng `orderCode` bằng
  `erpExcludedAt`/`erpExclusionReason`, không tính các đơn này là đơn mới cần
  báo cáo trong sync nền, và chặn check/submit thủ công bằng copy tiếng Việt.
  Validation: focused Nest sales-report service and Home Summary specs, backend
  build, and `git diff --check`.
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
- `UI-UX-001`, 2026-07-04: completed the internal-copy cleanup batch for the
  UI/UX audit plan. Visible Flutter UI now uses `Bảo hành` or
  `bảo hành/sửa chữa` instead of `BH/SC`, `showroom` instead of `SR` in labels,
  chips, filters, notifications, and speaker notices, plain order wording
  instead of `ERP` in sales-report copy, and Vietnamese admin labels for
  policy/rule/node/internal/key/configuration-value surfaces. The design-system
  guard now checks likely-visible UI copy in feature presentation screens and
  widgets so these internal terms do not reappear accidentally. Validation:
  focused UI/widget tests plus design-system guard, formatter check,
  `git diff --check`, `flutter analyze --no-pub`, and full Flutter suite.
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
  Báo cáo bán hàng admin filter/list tiles onto those shared patterns. Continuation
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
- `SALES-REPORT-001`, 2026-07-04: canceled ERP orders are now excluded
  durably instead of only being blocked inline at lookup time. When ERP confirms
  `confirmationStatus` or `fulfillmentStatus = cancelled`, OpsHub persists
  `excludedAt`/`exclusionReason = ERP_ORDER_CANCELLED` on
  `SalesReportErpOrderCache`, marks matching purchased reports with
  `erpExcludedAt`/`erpExclusionReason`, removes those rows from cockpit/admin
  list/export queries, and blocks future check/submit attempts fail-closed
  before calling ERP again if the exclusion is already cached. Validation:
  `npx prisma validate`, `npx prisma generate`,
  `npm test -- --runInBand src/sales-reports/sales-report-erp.service.spec.ts src/sales-reports/sales-reports.service.spec.ts`
  (33 tests), `npm run build`, `flutter analyze --no-pub`, and
  `git diff --check` (CRLF warnings only).
- `SALES-REPORT-001` / `PAYMENT-STATEMENT-001` / `OFFSET-ADJUSTMENT-001`,
  2026-07-04: shared empty date-range filters now keep the visible label
  `Tất cả ngày`, show a helper note when the user does not pick a range, and
  default query/export behavior to the latest 30 days instead of all history or
  the current day. Validation:
  `flutter test --no-pub --reporter expanded test/bank_statement_provider_test.dart test/offset_adjustment_provider_test.dart test/bank_statement_screen_test.dart test/sales_report_hub_test.dart`,
  `flutter analyze --no-pub`, and `git diff --check`.
- `SALES-REPORT-001`, 2026-06-30: after a report submit succeeds, the Flutter
  form resets and scrolls back to the top of the page. The sales-report CSV
  export now uses a compact `query_1`-style 34-column shape: one row per ERP
  item, order/item/payment fields in dedicated columns, and OpsHub form answers
  folded into `Order note` to avoid repeated form columns. Validation:
  `npm test -- --runInBand src/sales-reports` (17 tests), `npm run build`,
  `flutter test --no-pub --reporter expanded test/sales_report_hub_test.dart`
  (8 tests), and `flutter analyze --no-pub`.
- `SALES-REPORT-001`, 2026-06-30: admin `Báo cáo bán hàng` list/export now has a
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
- `SALES-REPORT-001`, 2026-07-01: The former group-name/ID/subcategory-alias
  matcher prevented a service item name containing `PC` from auto-selecting
  `Máy tính bộ`. That fuzzy/fallback matcher was removed on 2026-07-11; runtime
  now follows only the deepest exact Listing node contract recorded above.
  Historical validation:
  `npm test -- --runInBand src/sales-reports/sales-report-categories.service.spec.ts`.
- `SALES-REPORT-001`, 2026-07-01: ERP preserves sanitized
  `result.products[].categories[].code/id/name/level` per item for downstream
  category mapping. The former level-1 direct auto-tick behavior was superseded
  on 2026-07-11 by the deepest-node-only contract recorded above. Validation:
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
- `SALES-REPORT-001`, 2026-06-29: The initial implementation matched Listing
  `productGroup.code` and category aliases to `Cat group ID`; this behavior was
  superseded and removed on 2026-07-11 in favor of deepest exact category-only
  matching. Sales report forms
  require customer need, category, not-purchased reason when applicable, and
  explicit behavior answers instead of defaulting to `Có`. Validation:
  `npm test -- --runInBand src/sales-reports` (9 tests), `npm run build`,
  `flutter test --no-pub --reporter expanded test/sales_report_hub_test.dart`
  (2 tests), `flutter analyze --no-pub`, and `git diff --check`.
- `SALES-REPORT-001`, 2026-06-29: moved the admin `Báo cáo bán hàng` list/export
  entry out of `Quản trị` and into the `Báo cáo` hub. Home and `/sales-reports`
  now open when either `SALES_REPORT` or node-assigned `ADMIN_SALES_REPORTS` is
  available; the submit forms still require `SALES_REPORT`, and the admin
  list/export route still requires `ADMIN_SALES_REPORTS`. Validation:
  focused Flutter widget tests for `sales_report_hub_test.dart` and
  `home_feedback_action_test.dart`, `flutter analyze --no-pub`, and
  `git diff --check`.

| Story                 | Contract                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Unit    | Integration                             | E2E                          | Platform                                       | Status              | Evidence                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | --------------------------------------- | ---------------------------- | ---------------------------------------------- | ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SALES-REPORT-001      | Sale report forms for purchased and not-purchased customers, purchased order ERP check before submit, unique purchased `orderCode`, categories from `data/categories.csv` with Vietnamese labels, node-feature admin query/export, and dashboard-ready DB tables.                                                                                                                                                                                                                                                                      | yes     | backend build/API contract              | app analyze + Home test      | ERP live smoke pending                         | in_progress         | 2026-06-29: added backend Prisma schema/migration, sales-report API, ERP lookup service, CSV category sync, Flutter Home/Admin entries, report form, admin list/export shell, and docs. Validation in current patch: `npx prisma generate`, `npx prisma validate`, focused backend `npm test -- --runInBand src/sales-reports/sales-reports.service.spec.ts` (4 tests), backend `npm run build`, `flutter analyze`, focused `flutter test test/home_feedback_action_test.dart --reporter expanded` (6 tests), and `git diff --check`. Pending: live ERP credential smoke, migration apply on deployed DB, and live exported Excel workbook smoke; focused sales-report widget coverage is now tracked above in `test/sales_report_hub_test.dart`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| AUTH-001              | Email/password registration, sign-in, accepted Phong VÃ…Â© email domains, and JWT-backed sessions for Phong VÃ…Â© staff                                                                                                                                                                                                                                                                                                                                                                                                                | partial | no                                      | no                           | mobile smoke needed                            | changed             | 2026-05-15: flow changed to explicit registration; validation pending in current patch                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| AUTH-002              | Authenticated password change, forgot-password email reset codes, in-app password reset, super-admin direct password reset, single-use hashed reset tokens, and JWT token-version invalidation                                                                                                                                                                                                                                                                                                                                         | yes     | backend reset-code tests                | no                           | SMTP/app smoke pending                         | changed             | 2026-06-03: changed forgot-password from emailed reset links to 6-digit email reset codes that expire after 10 minutes, added in-app code verification before entering the new password, changed SUPER_ADMIN user management reset to direct password setting, and documented Gmail SMTP sender display as the verified alias `admin@hoanghochoi.com`. Validation: focused backend auth/user Jest (4 suites, 41 tests), `npx prisma validate`, `npx prisma generate`, `npm run build`, full backend `npm test -- --runInBand` (30 suites, 198 tests), focused Flutter auth repository test, `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded` (52 tests), and `git diff --check`. Gap: live SMTP sender/code delivery smoke and deployed app click-through remain pending. Earlier 2026-05-31 evidence: reset token table, tokenVersion, backend reset APIs, backend-served legacy reset page, Flutter forgot/change/admin reset UI, and AppLogger events.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| AUTH-003              | One active auth session per user/platform (`windows`, `android`, `ios`, `macos`, `linux`, `web`), same-platform login replacement, protected-route session enforcement, logout revocation, and client app-local device identity                                                                                                                                                                                                                                                                                                        | yes     | backend session/JWT tests               | no                           | same-platform and cross-platform smoke pending | changed             | 2026-05-31: added Prisma user platform session table, backend session issuance/enforcement/logout, locked-user JWT rejection, reset-password session revocation, Flutter device metadata on login/register, and auth-failure local session clearing. Validation: `npx prisma validate`, `npx prisma generate`, focused auth/session Jest, full `npm test -- --runInBand` (29 suites, 164 tests), `npm run build`, `flutter analyze --no-pub`, `flutter test --no-pub --reporter expanded` (39 tests), `git diff --check`. Gap: same-platform/cross-platform live smoke after deploy pending.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| FIFO-001              | FIFO check, export/unexport, sort workflows against OpsHub `fifo_inventory`, daily BigQuery inventory refresh, supplemental manual Excel import, and admin history                                                                                                                                                                                                                                                                                                                                                                     | partial | backend unit tests                      | no                           | mobile smoke needed                            | changed             | 2026-06-05: moved the manual `Cáº­p nháº­t tá»“n kho` entry from Quáº£n trá»‹ into the FIFO menu, added `/fifo/inventory-import` as the visible route, kept `/admin/inventory-import` as a backward-compatible alias, and kept both import routes guarded by `FIFO_IMPORT`; Home now opens FIFO when either FIFO workflows or FIFO import is available. Validation: `dart format`, `git diff --check`, `flutter analyze --no-pub`, and full `flutter test --no-pub --reporter expanded` (59 tests). Gap: live admin-user menu click-through remains manual. 2026-05-26: rebuilt FIFO cache contract around canonical BigQuery columns plus `opshub_*` metadata; serial check uses 20-day FIFO date tolerance, display-reserved handling, and short production labels. Manual Excel import maps the Vietnamese serial inventory export into canonical columns and stays additive. Targeted backend tests passed; pending live BigQuery env/deploy smoke and mobile smoke. 2026-05-24: manual import now preserves FIFO `import_date` priority as BigQuery date > existing DB date > file date; when no original/DB date exists, the file date is used for FIFO sorting and also stored separately in `manual_import_date`. Also moved FIFO inventory ownership to OpsHub DB and added admin manual inventory Excel parser/import endpoint and UI entry; parser verified against sample file shape. 2026-05-23: added SR-scoped FIFO API and sort delegation, exported toggle contract, replaced the legacy conversation-style FIFO UI, and cleaned up navigation; pending full live VPS smoke                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| WARRANTY-001          | Warranty/repair image capture, upload, same-showroom read/status scope, legacy n8n metadata migration, and status updates                                                                                                                                                                                                                                                                                                                                                                                                              | yes     | production metadata migration smoke     | no                           | upload and WebSocket smoke needed              | changed             | 2026-06-06: changed the n8n warranty migration script to reconcile existing OpsHub warranty rows instead of skipping them; supports `--store=CP62` and explicit `--reassign-existing-creators`, merges normalized n8n image links with existing app links, rewrites stored legacy n8n image hosts to `IMAGE_BASE_URL`, creates/patches locked legacy technical users only when passwordless/no store, and preserves app-created images. Validation: `node --check scripts/migrate-n8n-warranty-metadata.mjs`, `node --test scripts/migrate-n8n-warranty-metadata.test.mjs` (7 tests), VPS app DB backup `/srv/opshub/backups/opshub-before-warranty-creator-reassign-20260606043026.sql.gz`, production CP62 dry-run (77 existing rows, 73 creator updates, 0 image updates), production apply (73 existing creators updated, 0 image updates), post-apply compare (77 n8n receipts, 77 app receipts, 0 creator mismatches, 0 CP62 rows still under `super_admin@phongvu-mna.vn`), idempotent dry-run (0 pending creator/image updates), and production image verification (77 rows, 715 app URLs, 0 legacy image hosts, 0 bad URLs, 0 missing files). Gap: upload/WebSocket smoke remains pending. 2026-06-03: added backend showroom-scoped Warranty list/search/detail/status checks with SUPER_ADMIN full access, repo-tracked n8n metadata migration script, and migrated production n8n-only metadata into OpsHub DB. Validation: focused warranty Jest, `npm run build`, DB backup before apply, production migration dry-run/apply, post-apply idempotent dry-run, and production verify: 78 Warranty rows, 717/717 app URLs with existing files, 0 legacy image hosts, all creators store-scoped. Gap: deployed scoped API smoke after build and mobile upload/WebSocket smoke remain pending.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| FEEDBACK-001          | Staff feedback submission through app and API                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | partial | no                                      | no                           | mobile smoke needed                            | existing_unverified | Product docs seeded from README/code inspection                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| VIETQR-001            | Manual VietQR transfer QR creation screen, API payload generation with optional amount/content, persisted payment intent, MAP transaction confirmation rule, QR-screen auto confirmation polling, confirmed transaction detail display, and secured n8n QR image/info API                                                                                                                                                                                                                                                              | yes     | MAP live smoke partial                  | no                           | mobile smoke needed                            | changed             | 2026-06-02: added backend DB-only auto reconciliation for every `PENDING` VietQR payment intent every 5 seconds, sharing the same stored MAP transaction matching rule across app-created and n8n-created QR records; still-pending intents become `FAILED` after their Vietnam-local creation day has passed, and app confirm no longer revives failed intents through direct MAP fallback. Validation: focused VietQR Jest (28 tests), `npm run build`, full `npm test -- --runInBand` (30 suites, 188 tests), `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded` (41 tests), and `git diff --check`. Gap: live deployed n8n/app status smoke pending. 2026-06-01: added API-key protected `/vietqr/n8n` JSON and `/vietqr/n8n/image` PNG endpoints for n8n, server-rendered the app-style VietQR image from the same backend payload, fixed the confirmed QR UI so the waiting card no longer remains after payment success, and added image decode proof that generated PNGs contain the exact service QR payload with valid CRC. Validation: focused VietQR Jest, `npm run build`, full `npm test -- --runInBand` (30 suites, 179 tests), `flutter analyze --no-pub`, `flutter test --no-pub --reporter expanded` (40 tests), visual PNG check, and `git diff --check`. Gap: live n8n call and real banking-app scan against production account pending. 2026-05-21: added Vietnam-local MAP timestamp parsing, matched transaction detail persistence, and Flutter confirmed-state UI; `npx prisma generate`, `npm run build`, `npm test -- --runInBand`, `flutter analyze`, `flutter test`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| PAYMENT-MONITOR-001   | Backend polls configured VietinBank MAP accounts, persists successful incoming transactions, creates scoped payment audio notifications, publishes store-filtered realtime events, and Windows PC plays `ting ting` plus generated/fallback speech for every newly observed amount independent from OpsHub QR/payment intents                                                                                                                                                                                                          | yes     | MAP/payment notification/realtime tests | no                           | Windows build proof                            | changed             | 2026-06-03: Windows payment audio now parses/logs WAV headers and, only after MCI returns `326` for WAV, writes a local temp `WAV PCM 16-bit mono 44100 Hz` and retries once without requesting a larger server payload. `PaymentSpeaker` logs WinMM device count, MCI code/message, source/normalized WAV metadata, and normalized playback status. Validation: `flutter test --no-pub test\payment_wav_tools_test.dart --reporter expanded`, `flutter test --no-pub test\payment_speaker_io_test.dart --reporter expanded`, `flutter test --no-pub test\payment_monitor_provider_test.dart --reporter expanded`, `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded` (50 tests), `flutter build windows --release --no-pub --dart-define=API_BASE_URL=https://opshub.hoanghochoi.com/api`, `git diff --check`. Gap: physical speaker smoke on a real machine that reproduces MCI 326 remains pending. 2026-06-01: Windows payment monitor now initializes `media_kit` for desktop audio, plays each notification through `media_kit` -> Win32 `PlaySoundW` (WAV) -> MCI fallback, uploads `PaymentSpeaker` started/succeeded/failed logs with sanitized context, retries failed playback up to 3 attempts with a 10-second delay while reusing the same downloaded audio bytes, acknowledges interim `PLAYBACK_FAILED`, and only acknowledges terminal `FAILED` after attempt 3. Validation: `flutter analyze --no-pub`, `flutter test --no-pub --reporter expanded` (40 tests), `npm test -- --runInBand src/payment-notifications/payment-notifications.service.spec.ts` (9 tests), `npm run build`, `flutter build windows --debug --no-pub`, `git diff --check`. Follow-up 2026-06-01: pinned `media_kit_libs_windows_audio` to upstream git commit `7102e7da96f39c718487a8f7a59b6a034aae7f45` (`fix: CMP0175 warning on Windows (#1377)`), re-ran `flutter clean`, `flutter pub get`, and a clean `flutter build windows --debug --no-pub`, and the previous Windows CMake `add_custom_command` policy warning no longer appeared. Gap: live Windows speaker smoke still needs physical-audio verification. 2026-05-30: payment notification TTS text now ends with a period and Piper speed defaults to `0.90` so final `Ä‘á»“ng` audio has more room to finish. Validation: generated and verified `artifacts/tts-samples/payment-speed-090-no-period.wav` and `artifacts/tts-samples/payment-speed-090-period.wav`, `npm test -- --runInBand src/payment-notifications/payment-notifications.service.spec.ts`, `npm run build`, `git diff --check`. Gap: live VPS env/deploy smoke pending. 2026-05-27: added repo-tracked Piper `vi-vais1000` TTS sidecar files for home-server deploy; it keeps the existing `/synthesize` payload contract, returns WAV, accepts legacy `custom:suong-vo`, and rolls out on port `18081` with VieNeu on `18080` as rollback. Validation: `python -m py_compile deploy/home-server/tts-piper/app.py`, VPS temp sidecar smoke on port `18082`, `npm test -- --runInBand src/payment-notifications/payment-notifications.service.spec.ts`, `npm run build`, `git diff --check`. 2026-05-27: global MAP account sync added as primary path; backend maps `virtualAccount` to `Store.transferAccountNumber`, stores matched transactions by showroom, quarantines unmapped/ambiguous rows without audio, and keeps per-store credentials as fallback. Validation: `npx prisma generate`, `npm test -- --runInBand src/map-vietin/map-vietin.service.spec.ts src/payment-notifications/payment-notifications.service.spec.ts src/vietqr/vietqr.service.spec.ts`, `npm run build`, `git diff --check`. 2026-05-27: compacted payment monitor UI by removing the standalone last-updated banner, moving the timestamp into the auto-update chip, and adding Vietnam-local stored-transaction date range filtering. Validation: `flutter analyze`, `flutter test`, `npm test -- --runInBand src/map-vietin/map-vietin.service.spec.ts`, `npm run build`, `git diff --check`. 2026-05-26: payment notification TTS now reads `Phong VÅ© Ä‘Ã£ nháº­n: <amount> Ä‘á»“ng` through VieNEU voice id `custom:suong-vo` (`Suong Vo`) at speed `0.98` and pitch `1.00`. Validation: `npm test -- --runInBand src/payment-notifications/payment-notifications.service.spec.ts`, `npm run build`, `git diff --check`. 2026-05-26: mute toggle now disables speaker only while transaction sync continues; muted notifications are acknowledged as `SILENCED` so they are not replayed later, and the payment monitor screen shows sync loading in a separate stable chip. Validation: `npm test -- --runInBand src/payment-notifications/payment-notifications.service.spec.ts`, `npm run build`, `flutter analyze`, `flutter test`, `git diff --check`. 2026-05-21: added payment notification tables/service, scoped realtime filtering, Flutter realtime notification parsing, and Windows audio asset build proof; `npx prisma generate`, `npm run build`, `npm test -- --runInBand src/payment-notifications/payment-notifications.service.spec.ts src/map-vietin/map-vietin.service.spec.ts src/vietqr/vietqr.service.spec.ts src/auth/auth.service.spec.ts`, `go test ./...`, `flutter analyze`, `flutter test`, `flutter build windows --debug` |
| PAYMENT-STATEMENT-001 | MAP bank statement reconciliation stores multiple extracted order codes, preserves manual edits, supports scoped search/export, inline order correction with audit history, sticky statement layout, copyable text, and order-presence card borders in Sao ke and Tien vao                                                                                                                                                                                                                                                             | yes     | focused MAP statement service tests     | no                           | Windows UI smoke manual                        | changed             | 2026-06-01: fixed Sao ke SR searches for SUPER_ADMIN by defaulting an empty date range to the current Vietnam-local day and paging the full snapshot in 100-row backend-safe chunks; added focused Flutter provider coverage and backend super-admin `storeIds` coverage. Validation: `flutter test --no-pub test\bank_statement_provider_test.dart --reporter expanded`, `npm test -- --runInBand src/map-vietin/map-vietin.service.spec.ts`, `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded`, `npm run build`, `git diff --check`. Gap: live Windows UI click-through remains manual. 2026-05-29: added Prisma order array/audit migration, MAP multi-order extraction with manual-preserve behavior, statement list/update/history/export endpoints, Flutter Sao ke screen, home route, AppLogger events, Tien vao order-presence borders, and bank statement model/provider tests. Validation: `npx prisma validate`, `npx prisma generate`, `npm test -- --runInBand src/map-vietin/map-vietin.service.spec.ts` (23 tests), `npm run build`, `flutter analyze --no-pub`, `flutter test --no-pub --reporter expanded` (33 tests). Gap: full Windows UI click-through remains manual.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| PROFILE-ADMIN-001     | Profile avatar, admin-assigned organization nodes, pending-assignment auth gate, store account import, fixed `SUPER_ADMIN -> ADMIN -> USER` roles, Lv0-Lv5 organization tree administration through `ADMIN_ORG_TREE`, retired legacy Region/Area/SR/admin-store/self-select APIs, scoped MAP credential settings, hidden legacy feature codes, and tree-first admin user management                                                                                                                                                    | yes     | backend auth/user/feature tests         | mobile smoke                 | Android                                        | changed             | 2026-06-13: registration/login no longer self-selects SR; users without `organizationNodeId` get `assignmentPending=true` and are routed to `/assignment-pending`; `/users/me/select-store` returns `410 Gone`; admin user editing uses a searchable organization-node picker with no direct department/job-role rows; org-tree route/menu uses `ADMIN_ORG_TREE`; legacy `ADMIN_STORES`, `ADMIN_REGIONS`, and `ADMIN_PERSONNEL` are hidden from the feature picker with migration/backfill to `ADMIN_ORG_TREE`. Validation: `npx prisma validate`, `npx prisma generate`, backend `npm run build`, full backend `npm test -- --runInBand` (35 suites, 256 tests), `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded` (87 tests), and `git diff --check`. Gap: live staging smoke remains manual.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| PERSONNEL-001         | Personnel assignment keeps fixed system roles separate from department, job role, Lv0-Lv5 organization node placement, derived `NATIONAL -> REGION -> AREA -> STORE` compatibility scope, generated `JOBROLE_SR_AREA_REGION` personnel codes, and API-level feature gates                                                                                                                                                                                                                                                              | yes     | backend feature/user/auth tests         | no                           | admin UI smoke needed                          | changed             | 2026-06-04: added Region/Area catalogs, SR area assignment, scope fields `regionCode`/`areaCode`, virtual `CHATSALE`/`TELESALE` Region scopes, `STORE_MANAGER` operational job role, `ONLINE -> CHATSALE` migration, `MULTI_STORE` migration precheck/rejection, feature definitions/rules with backend guards, `/features/me`, admin feature UI, and removed bottom navigation in favor of Home feature grid. Validation in current patch: `npx prisma validate`, `npx prisma generate`, backend `npm run build`, focused auth/user/feature Jest, full `npm test -- --runInBand` (31 suites, 208 tests), `flutter analyze --no-pub`, and full `flutter test --no-pub --reporter expanded` (53 tests).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| UI-UX-001             | Android and Windows operational UI uses consistent auth density, desktop max-width layout contracts, shared form spacing, shared empty/loading/error/status states, and 16 KB Android native-library build readiness                                                                                                                                                                                                                                                                                                                   | yes     | no                                      | Windows smoke partial        | Android build and Windows smoke                | changed             | 2026-06-05: added the canonical UI/UX product contract at `docs/product/ui-ux.md`, centralized payment-monitor platform support through `AppPlatformCapabilities`, kept unsupported direct route access on a shared Windows-only state, made warranty details responsive with tokenized colors and download logging, and replaced targeted admin/FIFO/warranty/sort hard-coded colors with `AppColors` tokens. Validation: focused platform capability test, focused unsupported-screen widget test, `dart format --output=none --set-exit-if-changed`, `git diff --check`, `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded` (56 tests), `flutter build windows --debug --no-pub`, and `flutter build apk --debug --no-pub`. Gap: authenticated Android/Windows visual screenshot smoke with real warranty/admin/sort data remains manual. 2026-05-25: implemented `docs/ux-ui-audit-2026-05-25.md` follow-up pass; `git diff --check`, `flutter analyze`, `flutter test`, `flutter build apk --debug`, `zipalign -c -P 16 -v 4 build/app/outputs/flutter-apk/app-debug.apk`, Windows debug smoke. Follow-up form/layout consistency pass normalized auth/profile/retired branch-assignment/admin/FIFO/sort/warranty/feedback/VietQR/payment/FIFO scanner input spacing and responsive wrappers; re-ran `git diff --check`, `flutter analyze`, `flutter test`, and Windows debug smoke. Android device install was blocked by `INSTALL_FAILED_USER_RESTRICTED` without forced uninstall.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| SETTINGS-001          | Side menu opens app settings, and Windows users can toggle per-user startup with Windows through the current app executable registry entry                                                                                                                                                                                                                                                                                                                                                                                             | no      | no                                      | no                           | Windows startup smoke partial                  | changed             | 2026-05-27: added side-menu Settings route and Windows startup toggle backed by per-user `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` value `PhongVuOpsHub`; flow logs load, unsupported platform, toggle start, success, and failure through `AppLogger`. Validation: `flutter analyze --no-pub`, `flutter test --no-pub --reporter expanded`, `flutter build windows --release --no-pub --dart-define=API_BASE_URL=https://opshub.hoanghochoi.com/api`, and local reversible registry smoke confirmed the value can be written as a quoted path to the release exe and deleted back to missing. Gap: full UI click-through/restart login smoke remains manual.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| CLIENT-LOGS-001       | Authenticated clients upload one sanitized previous-day activity summary per day through the existing app-log pipeline without sending the raw log file                                                                                                                                                                                                                                                                                                                                                                                | yes     | no                                      | no                           | Windows runtime smoke needed                   | implemented         | 2026-05-30: added client daily log summary builder, sanitizer, authenticated once-per-day upload trigger, and story/docs. Validation: `flutter test --no-pub test/daily_activity_log_test.dart --reporter expanded`, `flutter analyze --no-pub`, `flutter test --no-pub --reporter expanded`, `git diff --check`. Gap: live Windows authenticated upload smoke remains manual.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| WINDOWS-DIST-001      | Windows releases require fail-closed Authenticode signing for the app executable and Inno installer with PFX/password, signer-pin and timestamp validation plus Defender scanning; runtime verifies HTTPS same-origin/type/size/SHA-256 without signer pin, and `/download` publishes EXE/ZIP/checksums                                                                                                                                                                                                                                | no      | no                                      | no                           | Windows package proof partial                  | changed             | 2026-06-04: added `/download` and `/downloads/latest.json` so staff can download the current Windows installer, portable ZIP, and checksum from a public landing page; manual `workflow_dispatch skip_client_build=true` refreshes only static download assets and manifest from live artifacts without rebuilding Windows packages. Validation: `git diff --check`, workflow YAML parse, `node --check scripts/download-manifest.mjs`, temp artifact manifest smoke, live artifact manifest smoke against the current public APK/EXE/ZIP/checksum, inline HTML JavaScript syntax check, and local static route smoke for `/download`, `/download/`, `/downloads/latest.json`, and icon. Gap: local Caddy validation unavailable because local `caddy` is missing and Docker daemon is not running; workflow now validates Caddyfile on the VPS with `caddy:2-alpine` before applying it; live skip-build dispatch remains pending. 2026-06-03: initially added conditional internal Windows signing in GitHub Actions (superseded on 2026-07-15 by mandatory fail-closed signing), signing helper script, post-signing SHA256 generation for direct Windows ZIP/installer downloads, bundled current-user certificate import in Inno when a signing certificate is available, and internal certificate rollout docs. Validation: `dart pub get --offline`, workflow YAML parse check, PowerShell parser check for `scripts\sign-windows-artifact.ps1`, `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded` (50 tests), `flutter build windows --release --no-pub --dart-define=API_BASE_URL=https://opshub.hoanghochoi.com/api`, Inno Setup 6.7.0 local compile of validation installers with and without `/DInternalCodeSigningCertPath`, local SHA256 file generation for validation ZIP/installer, and signing helper smoke with a temporary self-signed PFX on a copied EXE (`Get-AuthenticodeSignature` became non-`NotSigned`; status `UnknownError` because the temporary cert was not trusted). Historical gap at that time: signed GitHub Actions proof required real signing secrets; the current release now forbids missing signing inputs; target-PC warning smoke requires a managed PC with the public `.cer` installed in Trusted Root and Trusted Publishers.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| WINDOWS-INSTALL-001   | Windows installer bundles Microsoft Visual C++ Redistributable x64, installs it before app launch when the runtime is missing/old/incomplete, keeps Windows update metadata pointed at the setup EXE, and leaves the portable ZIP as manual/internal distribution                                                                                                                                                                                                                                                                      | no      | no                                      | installer smoke partial      | Windows installer build proof                  | changed             | 2026-06-03: installer now performs a non-blocking Windows audio preflight before install by checking `Audiosrv`, `AudioEndpointBuilder`, and WinMM `waveOutGetNumDevs`; interactive installs show a warning when audio service/device checks fail, while silent installs only log the warning and continue. Validation: Microsoft `vc_redist.x64.exe` downloaded with valid signature, `flutter build windows --release --no-pub --dart-define=API_BASE_URL=https://opshub.hoanghochoi.com/api`, Inno Setup 6.7.0 compile succeeded with the bundled redist and updated preflight code, `git diff --check`. Gap: clean-VM missing-service/no-output interactive warning smoke and missing-runtime/UAC path remain pending. 2026-05-27: installer now embeds official Microsoft `vc_redist.x64.exe`, checks registry version plus required DLLs, runs the prerequisite elevated with `/install /quiet /norestart /log`, accepts reboot-required outcomes, and skips postinstall launch when reboot is needed. Validation: redist downloaded with valid Microsoft signature, `git diff --check`, `flutter build windows --release --dart-define=API_BASE_URL=https://opshub.hoanghochoi.com/api`, Inno Setup 6.7.0 compile confirmed `vc_redist.x64.exe` included, and silent installer smoke exited 0 on a machine where runtime 14.44 was already present. Gap: missing-runtime/UAC path still needs clean Windows VM smoke before push.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| PLATFORM-001          | NestJS, Go realtime, PostgreSQL, Redis local stack health                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | partial | no                                      | no                           | health checks needed                           | existing_unverified | Product docs seeded from README/code inspection                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| UPDATE-001            | Mobile clients check backend version metadata and require APK updates when server build is newer or minimum supported build is raised; staff can use `/download` backed by `/downloads/latest.json` to download the latest APK, Windows installer, Windows ZIP, and checksum                                                                                                                                                                                                                                                           | yes     | no                                      | mobile/download smoke needed | Android, Windows, public web                   | changed             | 2026-06-05: fixed old Android/Windows clients losing the update prompt during startup redirects by keeping the update result in `AppUpdateGate` state and rendering a blocking modal overlay above the router instead of a transient navigator dialog; optional prompts dismiss only from `Äá»ƒ sau`, required prompts keep blocking and open the update URL. Validation: focused `flutter test --no-pub test/app_update_gate_test.dart --reporter expanded`, `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded` (59 tests), `flutter build windows --debug --no-pub`, `flutter build apk --debug --no-pub`, `git diff --check`. Gap: live old APK/Windows installer startup smoke against production metadata remains manual. 2026-06-04: added the public `/download` landing page, CI-generated `latest.json`, and manual `skip_client_build=true` static-only deploy path that does not change app-version metadata or rebuild APK/EXE/ZIP. Validation: `git diff --check`, workflow YAML parse, `node --check scripts/download-manifest.mjs`, temp artifact manifest smoke, live artifact manifest smoke against current public files (`2026.06.03.55+100055`), inline HTML JavaScript syntax check, and local static route smoke. Gap: local Caddy validation unavailable because local `caddy` is missing and Docker daemon is not running; live workflow dispatch smoke remains pending.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| HELP-001              | Public `/help` is a Flutter route readable when logged out, it renders runtime help from `/api/help-content/public`, serves markdown image assets from `/help/assets/*`, `/download` and `/login` link to it, the public screen has a reliable back action, the shell side menu opens the in-app route from `Cấu hình` with `AppLogger` coverage, runtime pages support `Nháp`/`Public`/`Private`, and Super Admin can manage runtime help plus upload public help images through `/admin/help-content` and `/api/help-content/public` | yes     | help-content service/controller tests   | route/runtime smoke pending  | Web, Android, Windows, Admin web               | changed             | 2026-07-04: cut public `/help` over to the Flutter route, added `HelpScreen`, public logged-out router allowlist coverage, in-app account-menu navigation, runtime docs auto-sync for docs-managed pages, deployed-environment `docs/help` mount for seed/restore, and production/staging workflow checks for `/api/help-content/public`. `help-content` static-only deploys now refresh `/help/assets/*` and sync `docs/help/*` into the live release as the runtime source/rollback path; admin-edited pages require `Khôi phục từ docs` to realign with branch content. Validation in this patch: `npx prisma validate`, `npx prisma generate`, backend `npm run build`, `npm test -- --runInBand src/help-content/help-content.service.spec.ts src/help-content/help-content.controller.spec.ts`, `node scripts/build-help-site.mjs`, `flutter analyze --no-pub`, `flutter test --no-pub --reporter expanded test/admin_menu_screen_test.dart test/app_shell_route_viewport_test.dart test/help_screen_test.dart`, `flutter build web --debug --no-pub`, and `git diff --check`. 2026-07-04 earlier batch: added the `HelpContentPage` runtime table plus Super Admin create/update/restore endpoints and editor. 2026-07-04 follow-up: login now exposes `Hướng dẫn`, Help has an explicit `Quay lại` fallback, and Super Admin can upload help images to `/uploads/help-content/...` through `POST /api/admin/help-content/assets`; validation reran backend `npm run build`, `npm test -- --runInBand src/help-content/help-content.service.spec.ts src/help-content/help-content.controller.spec.ts`, `flutter analyze --no-pub`, and `flutter test --no-pub --reporter expanded test/help_screen_test.dart test/app_shell_route_viewport_test.dart test/auth_pre_shell_redesign_test.dart test/admin_menu_screen_test.dart`. 2026-07-04 navigation follow-up: desktop/tablet side menu now shows `Vận hành` under `Tổng quan`, moves `Góp ý` and `Hướng dẫn` under `Cấu hình`, updates the brand slogan to `Kết nối nguồn lực. Đồng bộ vận hành.`, and adds footer developer/copyright metadata. 2026-07-04 visibility follow-up: runtime help now supports `Nháp`, `Public`, and `Private`; `Private` pages stay hidden from anonymous `/help` but appear after login, and authenticated `/help` now renders inside `AppShell` instead of taking over the full screen. Validation reran `npx prisma validate`, `npx prisma generate`, backend `npm test -- --runInBand src/help-content/help-content.service.spec.ts src/help-content/help-content.controller.spec.ts`, backend `npm run build`, `flutter analyze --no-pub`, `flutter test --no-pub --reporter expanded test/app_nav_model_test.dart test/app_shell_route_viewport_test.dart test/auth_pre_shell_redesign_test.dart test/help_screen_test.dart test/home_avatar_test.dart test/operations_screen_test.dart test/home_feedback_action_test.dart test/admin_menu_screen_test.dart`, `flutter build web --debug --no-pub`, and `git diff --check`. Gap: live staging/prod `/help` smoke plus runtime-editor smoke still need post-deploy verification; local Caddy validation remains unavailable because `caddy` is not installed.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| UPDATE-003            | Running Android, Windows, and web clients receive a public app-version WebSocket event after backend deploy, then re-read public `/app-version` metadata before showing the existing optional/required update prompt or web reload action                                                                                                                                                                                                                                                                                              | yes     | mocked Redis/WebSocket contracts        | widget flow verified         | Android, Windows, and web builds               | implemented         | 2026-07-03 Web smoke added `scripts/opshub-web-smoke-proxy.mjs` and proved the local same-origin Web build can open production `/ws/app-updates` without browser console errors. 2026-07-03 live staging smoke published `APP_VERSION_UPDATED` through staging Redis; raw public WebSocket received `APP_UPDATE` with `web.latestBuild=200083`, and Chrome CDP on deployed Flutter web saw `/ws/app-updates`, the smoke frame, and one follow-up `/api/app-version?platform=web` request with console/runtime errors at 0. 2026-06-30: web metadata uses `platform=web`, an empty update URL, `forceUpdate=false`, and reload-only UI so web does not inherit Android APK updates. 2026-06-24: NestJS publishes sanitized Android/Windows build metadata to Redis after startup, Go exposes public update-only `/ws/app-updates`, and Flutter reconnects with backoff then re-checks HTTP metadata on event, connection, resume, and metadata retry. Public clients cannot receive warranty/payment events. Validation: focused Flutter update-gate tests (7), full Flutter tests (139), Flutter analyze, Windows release build, Android production-debug APK build, focused NestJS app-version tests (5), full backend Jest (39 suites, 308 tests), NestJS build, Go tests, and live staging Redis/WebSocket/browser smoke. Live smoke reused current metadata to avoid forcing staff; visible forced-prompt UI remains covered by widget/local update-gate tests.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| UPDATE-004            | Android and Windows users update from the app prompt without downloading the package through a browser; the client downloads `packageUrl`, verifies SHA-256 and size, then hands off to Windows Inno Setup or Android Package Installer with platform safety checks                                                                                                                                                                                                                                                                    | partial | app-version + Flutter self-update tests | no                           | installed Android/Windows update smoke         | changed             | 2026-07-06: Added self-update package metadata (`packageUrl`, `packageSha256`, `packageSizeBytes`, `packageType`, Windows `installerArgs`) to `/app-version`, wired production/staging deploys to compute and verify it from published APK/EXE files, changed `AppUpdateGate` to run an in-app downloader/verifier instead of opening `updateUrl`, added Windows silent installer launch and Android FileProvider/native package/signature/version validation before opening Package Installer. Validation so far: focused Flutter update tests (16) and focused NestJS app-version tests (7). Gap: `flutter analyze`, platform builds, workflow parse, and manual installed-build Android/Windows update smoke remain pending.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |

## Recent Evidence

- UPDATE-004, 2026-07-09: Windows self-update now publishes
  `/OPSHUBRELAUNCH=1` in installer args and the Inno script only relaunches
  OpsHub during silent install when that flag is present. Validation:
  focused Flutter update tests (17), focused NestJS app-version tests (7),
  `flutter analyze --no-pub`, backend `npm run build`, Windows debug build,
  Inno Setup 6.7.0 compile-check, focused TS Prettier check, and
  `git diff --check`. Gap: live installed self-update smoke remains pending.
- UPDATE-004, 2026-07-10: Startup/realtime/resume update checks now auto-start
  the web reload or Android/Windows self-update flow without requiring the user
  to press `Cập nhật`; the overlay remains for progress and errors. Validation:
  focused Flutter update gate tests. Gap: live installed Android/Windows
  auto-update smoke remains pending.
- UI-UX-001, 2026-07-03: Redesign audit baseline now has a status addendum so
  the 30/06/2026 score is not mistaken for the current migration state. The
  addendum points acceptance tracking to the gap map and this matrix, records
  the current 70 route/viewport web visual smoke scope, and keeps remaining
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
  Follow-up physical acceptance on staging build `2026.07.03.98+200098`
  verified iOS Safari/PWA camera permission, live preview, and successful scan,
  plus QR, Code 128, and small Data Matrix callbacks across FIFO, Sort, BH/SC,
  VietQR, and Sales Report; VietQR/Sales Report preserved raw-code mode.
- UI-UX-001/QUICK-ACTIONS-001/FIFO-001/SALES-REPORT-001, 2026-07-15:
  customer QR now stays black on a pure-white square in dark mode. The shared
  camera scanner loads pinned ZXing `0.21.3` from the app origin so production
  CSP `script-src 'self'` cannot block camera initialization, exposes an
  explicit camera retry action, and reduces manual entry to one horizontal
  input plus a filled check icon with the accessible label `Hoàn thành`.
  Validation: focused scanner/Quick Actions widget suite (19 tests), focused
  design-system guard, full Flutter suite (471 passed, 2 skipped),
  `flutter analyze --no-pub`, `flutter build web --no-pub
--dart-define=APP_ENV=smoke`, packaged ZXing SHA-256
  `d7cc8f69dd70bdcf3ac00c9ae572bf2acb9f4132ba379c72df842e4db918652d`,
  and `git diff --check`. Gap: repeat camera permission, live preview, and scan
  smoke on physical iOS Safari/PWA after deploying this build.
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
  camera release after leaving the scanner. Follow-up physical acceptance on
  staging build `2026.07.03.98+200098` verified scanner decode/callback on
  real QR, Code 128, and small Data Matrix targets, including iOS Safari/PWA
  camera preview and scan.
- UI-UX-001, 2026-06-29: shared QR/barcode scanner now uses a smaller centered
  runtime `scanWindow` matching the visible frame, dims the outside area, keeps
  camera/manual/error copy Vietnamese, and logs scanner open/success/failure
  branches with sanitized context. Validation: focused scanner window unit test,
  `flutter analyze --no-pub`, full `flutter test --no-pub --reporter expanded`,
  and `git diff --check`. Follow-up physical scanner proof is covered by the
  staging build `2026.07.03.98+200098` acceptance above.
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
- PROFILE-ADMIN-001, 2026-07-06: changed `Quản lý người dùng` text search back
  to debounced server search through `GET /admin/users?q=...`, so results come
  from the scoped database query instead of only the users already rendered in
  Flutter. Backend `q` now covers email/name plus store, org-node, role, scope,
  and feature fields. Validation: focused Flutter admin-user widget test,
  focused backend user Jest, Flutter analyze, backend build, and `git diff
--check`.
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
  handoff remains manual. 2026-07-17: Caddy now exposes the stable
  `/seatalk-support` URL as a reversible 302 redirect while the client button
  remains unchanged until the next app action. Validation: focused Home support
  widget test, Caddyfile structure inspection, `flutter analyze --no-pub`, and
  `git diff --check`. Gap: the public redirect remains pending the production
  deploy action; the app-side short-link update is intentionally deferred.

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
  `data/payment-cue-prefix.wav` to the downloaded amount with a 150 ms gap, and
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
  Current OPS-11 policy: the production cue-to-amount gap is 150 ms; amount
  chunks trim stored guards fully and use a 45 ms join gap.
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
  `flutter analyze --no-pub`, and `git diff --check`. Follow-up physical
  acceptance on staging build `2026.07.03.98+200098` verified BH/SC picker and
  original-image upload for 1 image, 2-5 images, near-10 MB images, and
  over-10 MB client rejection copy.
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
--check`. Follow-up physical acceptance on staging build
  `2026.07.03.98+200098` verified authenticated BH/SC upload and detail
  image view/download.
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

## SECURITY-001 hardening evidence (2026-07-12)

- Realtime: one-time Redis ticket, session revocation, server audience,
  backpressure/deadline/ping-pong/readiness and no JWT query. Nest/Go/Flutter
  focused tests pass. Staging live smoke on 2026-07-13 proved first-use ticket
  acceptance, replay rejection, logout revocation closing active sockets,
  rejected ticket issuance after logout, and cross-store event isolation; all
  temporary sessions were removed. A live slow-client/load soak remains pending.
- Private media: opaque metadata, JWT + owner/feature/showroom authorization,
  traversal/size/checksum enforcement, decode/re-encode/pixel/aggregate upload
  limits, client credential-origin policy and migration/rollback tools. Focused
  tests pass; live backfill/public-route cutover remains manual.
- Auth/input/log: break-glass startup removed, emergency CLI audited, crypto OTP,
  compound throttling, enumeration-safe responses, CSV formula neutralization,
  app-log bounds/source/quota and PII/query redaction. Focused Nest/Flutter tests
  pass.
- Platform/supply chain: production npm audit 0, SheetJS CE 0.20.3, pinned image
  digests, Go 1.25.12 + quic-go 0.59.1, Redis auth, non-root/read-only/cap-drop,
  encrypted backup fail-closed, CI-only Windows signer pin and allowlisted
  SHA-256 runtime artifact. Config/syntax/security contract checks pass;
  Docker/live/signing/restore proof remains manual. Staging inspection on
  2026-07-13 confirmed API
  and realtime are non-root with read-only rootfs, `CapDrop=ALL`,
  `no-new-privileges`, and bounded Docker logs; Caddy non-root remediation is
  tracked in the Compose runtime configuration and requires post-deploy proof.
- Local validation: Flutter analyze, full test (515 pass, 1 skipped) and Web
  release/Android staging debug/Windows debug builds pass. Nest build passes;
  the 13/07/2026 follow-up full Jest run passes 59/59 suites and 586/586 tests
  after correcting two Sales Report fixtures to the strict-showroom contract.
  No runtime fallback was restored. Manual gates and exact commands are in
  `app-security-manual-actions-12072026.md`.
- Final proof 2026-07-15: local gate refreshed to Flutter 458 pass/2 skip,
  Nest 64/64 suites and 629/629 tests, Prisma Home scratch `90/90/90`, exact
  Go 1.25.12 builder test/vet/govulncheck/race, npm audit 0 and runtime artifact
  250 files/11,257,350 bytes. SHA `0a949268...` passed staging run
  `29356202412` and production run `29358234827`. Production runtime inspect
  confirmed non-root/read-only/cap-drop/log limits, Redis auth, 58 current
  migrations, HTTP 308 + HSTS/CSP, WS 101, anonymous media 401 and clean
  token/ticket log smoke. TrueNAS backup `20260715-012644` passed 6/6 checksum.
  Private-media strict audit and strict dry-run passed with 750 candidates and
  0 missing/rejected/error; apply/cutover remains a separate data-maintenance
  follow-up because 764 legacy upload files remain and Caddy has no access-log
  proof.
- Private-media post-audit hardening, 2026-07-20: the integrity verdict remains
  compatible with a pre-migration strict audit, while a separate aggregate
  `--fail-on-legacy` gate proves no database reference still depends on
  `/uploads` before route removal. Exact-origin/path and relative-path fixtures,
  fail-closed argument parsing, telemetry/batch regressions, and no-raw-value
  output passed 14/14 Node tests; the platform security contract also passed.
  Prisma generate, Nest build and reviewed runtime packaging (284 files,
  auditor/helper both present) passed. Staging run `29729119859` deployed exact
  SHA `bc9ca1c8...`; the first maintenance run exposed a stale service image,
  while `-T --build` with closed stdin loaded the new auditor and passed
  preflight/final/unknown-flag gates with zero leftover maintenance containers.
  Manual cutover now reads persistent and compressed rolled telemetry
  server-side instead of ephemeral Docker logs. CodeQL JavaScript/TypeScript and
  Go jobs passed; staging `/api/health` returned 200 while `/health` correctly
  redirected through Cloudflare Access. Live production post-batch proof
  remains pending.
  Backup proof `20260720-164144` now includes both `uploads` and `private-media`
  under v3 manifest, passes NAS checksum 6/6 with `.incoming=0`, and leaves all
  five production services running (four healthchecked). The earlier v2 backup
  was checksum-valid but omitted `private-media`; retention/ZFS expiry remains
  an explicit unapproved gap.

## QUICK-ACTIONS-001 — Thao tác nhanh v1 (2026-07-13)

- Backend unit: chức danh quản lý bắt buộc dù feature bị gán nhầm, URL chỉ
  http/https, showroom ngoài scope bị từ chối, upsert/xóa bốn link trong một
  transaction.
- Flutter widget/unit: đủ tám action đúng thứ tự, child shortcut kết hợp quyền
  gốc, route quản lý mã kết hợp chức danh + feature, regression shell giữ bốn
  mobile destinations.
- Static/build: `npx prisma validate`, Nest build, `flutter analyze --no-pub`,
  full Nest/Flutter tests và `git diff --check`.
- Manual pending: Windows Home placement/focus/Escape/USB scanner và điện thoại
  thật camera/horizontal scroll/customer QR scan.
- Regression 2026-07-14: scanner trả focus về đúng trường link; sau khi lưu,
  launcher force-refresh để Super Admin/user nhận QR action mới ngay.
- Performance regression 2026-07-15: launcher không gọi API mỗi lần mở. Client
  lưu persistent scope/danh sách QR 24 giờ và link từng showroom 7 ngày, seed
  showroom đơn từ bootstrap, dedupe request đang chạy, force-refresh sau lưu và
  cô lập cache theo user + scope + tập quyền. Cache sống qua lần khởi động app;
  API lỗi sau TTL fallback mã local. Unit/widget proof kiểm tra số lần repository,
  disk cache, TTL showroom, đổi quyền và mở menu từ cache.
- Cache invalidation regression 2026-07-17: lưu link phát v2-only
  `QUICK_ACTION_LINKS_UPDATED` theo showroom và feature `QUICK_ACTIONS`; gateway
  từ chối client ngoài scope. Client đúng scope xóa persistent cache scope + QR
  rồi tải lại đúng một lần; Windows ngoài Home hoãn tải tới lần Home kế tiếp.
  Event không chứa URL và luồng lưu không còn force-refresh lần hai trên máy
  quản lý. Validation: focused Nest/Flutter pass, full Nest 73 suites/724 tests,
  full Flutter pass, Go test pass, Prisma validate, Nest build, Flutter analyze
  và `git diff --check` pass.
- Mobile layout regression 2026-07-15: menu Thao tác nhanh dùng lưới tự xuống
  hàng thay cho một hàng cuộn ngang; widget proof kiểm tra đủ tám action, đúng
  hai hàng trên viewport 390px và không còn horizontal scroll view.
- Regression 2026-07-14: đổi chức năng `Khách hàng chưa mua` thành `Chăm sóc lại`
  với icon `support_agent_rounded`; thêm `QUICK_ACTION_FOLLOW_UP` ngay sau VietQR.
  Shortcut chỉ hiện khi child bật và user có `SALES_REPORT` hoặc
  `ADMIN_SALES_REPORTS`; migration backfill quyền node/user hiện hữu nhưng không
  ghi đè cấu hình shortcut đã có. Validation: `npx prisma validate`, 24 focused
  feature tests, Nest build, 16 focused Flutter tests, `flutter analyze --no-pub`
  và `git diff --check` đều pass.
- Regression 2026-07-14: `categories.csv` hoàn thiện `Type`/`clearance`; các dòng
  RAM dùng thống nhất canonical type `memory` để tham gia đúng phép tính PC ráp.
- Desktop data cards dùng `AppTwoAxisScrollView` với controller riêng từng trục,
  thumb/track hiện và interactive trên Windows. Home HVTC đổi nhãn thành
  `Tên nhân viên`; backend resolve mọi nhân viên active đúng showroom, không lọc
  chức danh SA, đồng thời fallback sang tên/email ERP của đơn hàng.
- Global UI regression 2026-07-14: `MaterialApp.builder` bọc route và overlay
  bằng `AppGlobalSelectionScope` để text tại screen/card/modal/dialog có thể
  chọn/copy; editable input tự cô lập vùng chọn. Dialog sạch đóng khi click ngoài,
  Back hoặc Escape; editor đã sửa dùng `AppDirtyFormGuard` để hỏi xác nhận hủy.
  Guard test cấm `barrierDismissible: false`; widget tests bao phủ đóng sạch,
  tiếp tục sửa, hủy bản nháp và lưu thành công không hỏi hủy. Validation toàn
  repo: `flutter analyze --no-pub` sạch, `flutter test --no-pub` pass 452 test
  với 2 platform skip có chủ đích; Nest focused pass 18 test và `npm run build`
  pass.

## Evidence Rules

## TEXT-INPUT-CONTEXT-MENU-001 — Paste menu theo nền tảng (2026-07-14)

- Mobile web keeps the browser-native context menu enabled and suppresses the
  Flutter editable toolbar, preventing duplicate `Paste` actions.
- Desktop web keeps one Flutter toolbar with the browser context menu disabled.
- Native Android/iOS keeps the Flutter platform toolbar and shared inputs are
  isolated from ancestor `SelectionArea` ownership so the paste menu does not
  dismiss immediately.
- Automated proof covers policy resolution, browser channel ownership and
  Android isolation from ancestor selection; the Chrome mobile-web regression
  test is added but the local Chrome harness opened without reconnecting and
  timed out. Validation passed: focused tests (18), full Flutter tests (444
  passed, 2 existing platform skips), `flutter analyze --no-pub`, web debug
  build, Android staging debug APK build, and `git diff --check`. Physical iOS
  Safari and Android device smoke remain required after staging deployment.
- Hardening 2026-07-16 applies the same single-owner paste policy and ancestor
  `SelectionArea` isolation to `AppCombobox`, which was the last runtime raw
  editable field outside the shared text-input wrappers. A repository guard now
  rejects future raw editable fields outside those shared primitives. Focused
  tests (39), `flutter analyze --no-pub`, the release web build, and a Playwright
  clipboard paste smoke on that build passed. The full Flutter run reached 532
  passed and 3 intentional skips before one unrelated realtime timing test
  failed; its isolated rerun passed. The Chrome widget-test harness still did
  not reconnect, so a physical iOS Safari smoke remains required after staging.

- `SALES-HOME-ORDERS-002`, 2026-07-16: Home sales KPI aggregation now marks
  pending-payment cache rows in `HomeSummaryOrderFact` and excludes them from
  `Giá trị bán`/`Đơn bán` and projection aggregates, while leaving the source
  cache row visible to the sales cockpit for later reporting. Canceled,
  returned-full, and zero-value rows remain excluded through the existing
  durable cache exclusion. API startup compares only GLOBAL aggregates for
  dates with pending-payment facts and requeues mismatches, closing the
  deploy race where the previous worker could consume the migration queue
  before the new aggregation logic starts without causing a restart-wide
  cache miss wave. Focused Nest tests passed (4 suites, 119 tests:
  ERP status/cache, Home summary, Home projection, and ERP normalization),
  together with `npx prisma generate`, `npx prisma validate`, `npm run build`,
  and `git diff --check`.

- Unit proof covers pure validators, service rules, and focused repositories.
- Integration proof covers API behavior, database persistence, Redis, BigQuery,
  uploads, and auth enforcement.
- E2E proof covers user-visible app flows.
- Platform proof covers mobile runtime, Docker services, deployment, health
  checks, and WebSocket behavior.

# Chăm sóc lại

| Luồng                                  | Proof tự động                                                                                              | Proof staging/manual                                                    |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| Grace 14 ngày hiển thị toàn bộ hồ sơ đúng scope | `sales-report-follow-ups.service.spec.ts`, `not_purchased_customers_test.dart` | Xác nhận mốc UTC được ghi một lần lúc deploy và không đổi sau restart/redeploy |
| Sau grace chỉ hiện hồ sơ có liên hệ hợp lệ | `sales-report-follow-ups.service.spec.ts`, `not_purchased_customers_test.dart` | Đối chiếu số 10 chữ số bắt đầu bằng `0`, các mã `PHONE`/`ZALO_PERSONAL`/`ZALO_OA` và dữ liệu rác đã được migration đưa về `null` sau mốc kết thúc |
| Scope và phân công cùng showroom       | NestJS service/controller guard test + build; `SUPER_ADMIN` không có showroom vẫn nhận scope toàn hệ thống | Đăng nhập Super Admin không gán showroom, Store Manager và quản lý node |
| Chăm sóc chưa mua/terminal/mở lại      | Flutter widget + API service test                                                                          | Thử đồng thời hai thiết bị và kiểm tra conflict                         |
| Comeback mua hàng                      | sales report service test + Flutter form test                                                              | Kiểm tra ERP `order.creator.email`, báo cáo gốc và báo cáo mua liên kết |
| Realtime                               | provider/channel test                                                                                      | Mở hai client và xác nhận danh sách tự tải lại                          |
| Nhập Excel dữ liệu lịch sử             | `sales-report-import-parser.service.spec.ts`, `sales-report-import.service.spec.ts`, `not_purchased_customers_test.dart` | Chạy migration, nhập file thật có ≤1.000 dòng; đối chiếu thống kê, scope SR, hồ sơ chưa phân công và thử nhập lại cùng file |

## AuthContext atomic-version proof

The access-version migration installs PostgreSQL triggers for direct user,
platform-session, assignment, policy/feature rule, personnel, store, and
organization-topology mutations. The trigger increments `User.accessVersion`
in the source transaction; `ACCESS_CHANGED` publication is post-commit only. Required
staging proof is migration smoke, cache invalidation, multi-replica sharing,
Redis outage behavior, and cleanup evidence.

Executed 2026-07-17: all required staging proof passed. The two-replica run
showed shared-cache hits, distributed-lease deduplication, version invalidation
and balanced public routing. With Redis stopped, bootstrap/scopes remained
`200` and the changed version produced a new ETag; Redis and API returned
healthy afterward. The `25 -> 50 -> 100 QPS` ladder completed 121,628 HTTP
requests with 100% success, p95 85.976 ms, p99 176.193 ms, zero unexpected
429/5xx/timeouts/dropped iterations and 60/60 WebSocket sessions. Cleanup
revoked 60 sessions, deleted 60 users, verified zero remaining references and
removed all raw artifacts.

## PAYMENT-SPEAKER realtime ticket parity proof

- Runtime diagnosis on 2026-07-17 found speaker-authorized clients that kept a
  healthy v2 socket and passed `/payment-notifications/ready`, but did not
  receive same-showroom `PAYMENT_SPEAKER_STREAM` events. Ticket issuance now
  reconciles `PAYMENT_SPEAKER` through the exact `canAccessFeature()` predicate
  used by ready/stream/ack endpoints. A stale cached grant is removed and a
  stale cached denial is repaired, so the gateway remains fail-closed without
  silently dropping an HTTP-authorized speaker client.
- Go audience regression proof requires v2 protocol, matching showroom, and
  the `PAYMENT_SPEAKER` feature claim. Wrong store, missing feature, and legacy
  protocol clients remain rejected. Flutter restores the metadata-only
  `/ready` safety interval to 5 seconds after realtime silence.
- Required local proof: focused realtime-ticket Jest, full Nest build/tests,
  `go test ./...`, focused payment-monitor Flutter test, Flutter analyze/tests,
  and `git diff --check`. Required runtime proof after release: at least 90% of
  newly played notifications use `triggerSource=realtime_stream`, with median
  `paidAt -> STREAM_STARTED` below 5 seconds; fallback traffic must remain the
  minority safety path.
