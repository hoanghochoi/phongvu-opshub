# OpsHub Redesign Screen Inventory

Status: **Approved — OPS-25-2026-07-26**
Authority snapshot: `app_router.dart@3fe2e5cd`
Coverage target: **43 canonical visual owners across 45 current path
declarations**

## 1. Counting rules

- Một `path:` declaration là một inventory row, kể cả redirect/alias/detail.
- Route cùng render một screen vẫn có hai row nhưng chỉ một canonical design
  owner; không nhân đôi Figma screen nếu behavior/presentation giống nhau.
- Route guard/permission là protected behavior, không phải UI proposal.
- Global session-expired, permission-revoked, offline và app-update behavior do
  shell/shared runtime sở hữu; screen chỉ bổ sung local recovery state.
- `N/A` phải có lý do; không bỏ state chỉ vì happy path không dùng.

## 2. State profiles

| Code | Required design states |
| --- | --- |
| SYS | initializing, redirecting, recoverable bootstrap error, offline/session handoff |
| AUTH | idle, focused, validation, submitting, success handoff, recoverable error, keyboard, long Vietnamese text |
| HUB | loaded, permission-filtered content, no available destination, long labels, compact/expanded navigation |
| DATA | initial loading, refreshing, loaded, empty, filtered empty, error/retry, partial/offline, pagination/load-more |
| FLOW | idle, input/scan/search, validation, processing, result, no result, recoverable error, duplicate-submit protection |
| DETAIL | loading, loaded, missing/not-found, partial content, error/retry, long content/media, destructive confirmation if applicable |
| FORM | pristine, editing, validation, submitting, success, recoverable error, dirty-close protection, long content/keyboard |
| ADMIN | DATA + FORM + permission/action-disabled + destructive confirmation + audit-safe feedback |
| STATIC | loaded, action progress, action error, long content, keyboard/focus, platform variation |
| UNSUP | unsupported capability, reason in plain Vietnamese, supported alternative/next action |

## 3. Route inventory

| # | Route | Type / runtime surface | Access contract | State profile / special requirements | Responsive/shared owner | Wave |
| ---: | --- | --- | --- | --- | --- | --- |
| 1 | `/loading` | System / inline `Scaffold` bootstrap | App initialization | SYS; progress must not imply a completed login | Pre-shell; safe area and reduced motion | Foundation |
| 2 | `/login` | Auth / `EmailCheckScreen` | Public when signed out | AUTH; email check is the first login step | `AuthScreenShell`; compact + auth desktop | Pilot |
| 3 | `/register` | Auth / `RegisterScreen` | Public; may receive initial email | AUTH; preserve initial email and password rules | `AuthScreenShell`; keyboard-safe | Pilot |
| 4 | `/forgot-password` | Auth / `ForgotPasswordScreen` | Public | AUTH; resend/recovery feedback | `AuthScreenShell`; keyboard-safe | Pilot |
| 5 | `/assignment-pending` | Auth system / `AssignmentPendingScreen` | Authenticated user awaiting organization assignment | SYS + STATIC; pending/retry/logout | `AuthScreenShell`; compact + auth desktop | Pilot |
| 6 | `/help` | Dual public/auth / `HelpScreen` | Public or authenticated | DATA + STATIC; loading/error/empty, public back vs shell navigation | Standalone public or `AppShell`; shared state widgets | Long tail |
| 7 | `/home` | Dashboard / `HomeScreen` + summary widgets | Authenticated | DATA + HUB; permission-scoped cards, refresh, detail modals | `AppShell`, responsive content, shared modals | Pilot |
| 8 | `/profile` | Account / `ProfileScreen` | Authenticated | FORM + STATIC; identity, password/profile actions, dirty state | `AppShell`, responsive form | Long tail |
| 9 | `/operations` | Workspace hub / `OperationsScreen` | Authenticated; cards filtered by permission | HUB; empty when no operational destination | `AppShell`, `AppFeatureGrid` | Pilot |
| 10 | `/notifications` | Inbox / `NotificationsScreen` | Authenticated | DATA; unread/read, empty, action feedback | `AppShell`, notification shared widgets | Long tail |
| 11 | `/admin` | Admin hub / `AdminMenuScreen` | Any allowed admin/FIFO administration capability | HUB; permission-filtered empty, long labels | `AppShell`, `AppFeatureGrid` | Admin |
| 12 | `/admin/users` | Admin CRUD / `UserAdminScreen` | User-administration feature | ADMIN; create/edit/reset/disable and scoped permission states | Shared inputs/combobox/dialog/state/pagination | Admin |
| 13 | `/admin/roles` | Admin CRUD / `RoleAdminScreen` | Role-administration feature | ADMIN; role list, empty, error, edit confirmation | Shared responsive/data/form primitives | Admin |
| 14 | `/admin/organization` | Admin tree / `OrganizationTreeAdminScreen` | Organization-tree feature | ADMIN; hierarchy loading/empty/error, node select/edit | Shared responsive/state/dialog primitives | Admin |
| 15 | `/admin/policies` | Admin policy / `PolicyAdminScreen` | Policy-administration feature | ADMIN; list/detail/assignment and destructive confirmation | Shared responsive/data/form primitives | Admin |
| 16 | `/admin/features` | Admin feature config / `FeatureAdminScreen` | Feature-administration feature | ADMIN; list/assignment, loading/empty/error | Shared state, combobox, dialogs | Admin |
| 17 | `/admin/personnel` | Admin catalog / `PersonnelCatalogAdminScreen` | Personnel-catalog feature | ADMIN; department/job-role tabs, loading/empty/error | Shared responsive/state primitives | Admin |
| 18 | `/admin/sales-targets` | Admin targets / `SalesTargetAdminScreen` | Sales-target feature | ADMIN; period/context, responsive editor, empty/error | Shared responsive/form/state; remove local 600 ownership in implementation | Admin |
| 19 | `/admin/quick-action-links` | Admin config / `QuickActionLinksAdminScreen` | Quick-action feature plus approved manager/super-admin boundary | ADMIN; scan/link focus, loading/empty, save feedback | Shared scanner/input/state/dialog | Admin |
| 20 | `/admin/inventory-import` | Admin import / `InventoryImportScreen` | FIFO import feature | FLOW + ADMIN; file select/upload/validation/result/error | Canonical import screen; shared state/dialog | Admin |
| 21 | `/admin/feedback` | Admin feedback / `FeedbackAdminScreen` | Feedback-admin feature and current super-admin guard | ADMIN; list/detail/media loading, response actions | Shared responsive/state/dialog | Admin |
| 22 | `/admin/help-content` | Admin content / `HelpContentAdminScreen` | Current super-admin guard | ADMIN; page list/editor, loading/error/empty, dirty-close | Shared responsive/state/dialog | Admin |
| 23 | `/admin/sales-reports` | Admin report / `SalesReportAdminScreen` | Admin sales-report feature | DATA + ADMIN; filter/list/import, empty/error | Shared responsive/state/filter/pagination | Admin |
| 24 | `/fifo-menu` | Historical compatibility link (not a current `path:` declaration) | Legacy deep link redirects to `/operations` before rendering | No standalone Figma owner | Operations canonical owner | Compatibility |
| 25 | `/fifo-check` | Command/scan workflow / `FifoCheckScreen` | FIFO feature | FLOW + DATA; input and scan actions remain beside input | Shared scanner/input/state; one-hand compact layout | Pilot |
| 26 | `/fifo-history` | FIFO history / `FifoHistoryScreen` | FIFO feature | DATA; initial/load-more/empty/error | Selected under Admin; shared state/pagination pattern | Operational |
| 27 | `/fifo/inventory-import` | Alias surface / `InventoryImportScreen` | FIFO import feature | Same canonical FLOW as route #20; no duplicate design | Canonical owner: Inventory Import | Alias → Admin |
| 28 | `/sort` | FIFO sort workflow / `SortScreen` | FIFO feature | FLOW + DATA; search/group/result/error | Shared responsive/input/state | Operational |
| 29 | `/warranty-main` | Warranty hub / `WarrantyMainScreen` | Warranty feature | HUB; entry choices and permission-safe empty | Selected as Bảo hành workspace | Pilot |
| 30 | `/warranty` | Warranty capture/workflow / `WarrantyScreen` | Warranty feature | FORM + FLOW; camera/media/upload/progress/recovery | Shared responsive/form/dialog; platform media behavior | Operational |
| 31 | `/check-warranty` | Warranty lookup / `CheckWarrantyScreen` | Warranty feature | FLOW + DATA; query/loading/no result/error | Shared input/state; command actions beside input | Pilot |
| 32 | `/check-warranty/details/:receiptNumber` | Parameterized detail / `WarrantyDetailsScreen` | Warranty feature | DETAIL; invalid/missing receipt, images, long history, retry | Same Warranty workspace; media viewer modal | Pilot |
| 33 | `/vietqr` | Payment creation/workflow / `VietQrScreen` | VietQR feature | FLOW + DATA; form, QR, waiting/success/expired/error/history | Shared responsive/form/state; customer QR stays black on white | Operational |
| 34 | `/payment-monitor` | Transaction monitor / supported or unsupported screen | Payment Monitor feature; capability function currently returns supported | DATA + UNSUP; live/refresh/empty/error and explicit unsupported fallback | Shared responsive/state; Android/iOS/iPadOS/Windows speaker capability remains separate from Web list-only | Operational |
| 35 | `/bank-statement` | Data-heavy reconciliation / `BankStatementScreen` | Bank-statement capability; query parameters may auto-search | DATA + FLOW; filter, auto-search, refresh, details, pagination | Shared DateRangePicker/filter/state/two-axis scroll | Pilot |
| 36 | `/offset-adjustments` | Finance workflow / `OffsetAdjustmentScreen` | Offset-adjustment capability | DATA + FORM; list/filter/create/confirm/error | Shared responsive/state/dialog | Operational |
| 37 | `/feedback` | Submission form / `FeedbackScreen` | Feedback feature | FORM; attachment, upload progress, success/error | Shared responsive/form/dialog | Long tail |
| 38 | `/reports` | Legacy redirect → `/sales-reports` | Sales-report feature | Redirect only; no standalone Figma screen | Canonical owner: Sales Reports | Alias → Operational |
| 39 | `/sales-reports` | Report cockpit / `SalesReportScreen` | Sales-report feature | DATA + HUB; filters, list, empty/error, modal report flows | Shared DateRangePicker/state/pagination/modal model | Operational |
| 40 | `/contract-appendix` | Contract table/form / `ContractAppendixScreen` | Contract-appendix feature | FORM + DATA; products, copy, loading/empty/error, long tables | Shared responsive/state/two-axis scroll | Operational |
| 41 | `/sales-reports/purchased` | Report editor / purchased `SalesReportFormScreen` | Sales-report feature | FORM; order states, validation, submit, fixed context header | Same modal/page presentation contract as peer flow | Operational |
| 42 | `/sales-reports/not-purchased` | Report editor / not-purchased `SalesReportFormScreen` | Sales-report feature | FORM; validation, submit, fixed context header | Same canonical report editor family | Operational |
| 43 | `/sales-reports/follow-up-cases` | Follow-up data/workflow / `NotPurchasedCustomersScreen` | Sales report or admin sales-report feature | DATA + FLOW; import/filter/list/detail/error/pagination | Shared responsive/state/filter/modal | Operational |
| 44 | `/settings` | Settings / `SettingsScreen` | Authenticated | STATIC + FORM; theme/log actions, progress/error, platform options | `AppShell`, shared controls/state | Long tail |

## 4. Coverage proof

### 4.1 Current-router reconciliation (OPS-44)

The historical 44-row table above is retained as an OPS-25 snapshot. The
current router additionally declares these two admin surfaces, which are real
visual owners and must not be treated as aliases:

| Current route | Canonical runtime surface | Figma ownership |
| --- | --- | --- |
| `/admin/support-chats` | `SupportChatsAdminScreen` | Dedicated admin support-chats frame `1701:131495` |
| `/admin/api-connections` | `ApiConnectionsAdminScreen` | Dedicated admin API-connections frame `1704:134596` |

`/reports` remains redirect-only. `/fifo/inventory-import` is a route alias
for the same `InventoryImportScreen` used by `/admin/inventory-import`; it is
not the `/reports` flow and does not justify a second visual design.

| Classification | Count |
| --- | ---: |
| Current `path:` declarations | 45 |
| Canonical visual owners | 43 |
| Pre-shell paths | 5 |
| ShellRoute paths | 40 |
| Redirect-only paths | 1 |
| Parameterized detail paths | 1 |
| Navigation destinations | 19 |
| Historical inventory rows above | 44 |

`/help` nằm trong ShellRoute nhưng có presentation public riêng khi chưa đăng
nhập. `/reports` được tính là declared path nhưng không có screen riêng.

Desktop shell evidence is explicit rather than inferred: Web specimen
`1792:16338` (`/shell-topbar · Web · 1440 · Runtime actions`) retains the
existing Hỗ trợ, Thông báo and Tài khoản actions alongside route-specific
actions. It documents an existing runtime contract only; it creates no route,
permission, data or business-behavior authority.

Shared runtime-state evidence is also explicit: Web specimen `1793:16377`
(`OPS-44 / Shared Runtime States / Web`) instances the existing Foundation
State Panel variants for loading, filtered empty, retryable error and
permission. It is a composition of approved shared components, not a new
route-level state or product-policy decision.

## 5. Foundation component demand

Inventory trên yêu cầu Figma foundation tối thiểu có:

- App shell/sidebar/rail/bottom navigation và destination states;
- button/input/combobox/date range/scan command primitives;
- form label/help/error/dirty/loading patterns;
- table/list/card, pagination, two-axis overflow và row action patterns;
- loading/skeleton/empty/filtered-empty/error/offline/permission/unsupported;
- dialog, bottom sheet, toast/banner và fixed-context long editor;
- focus ring, tooltip, keyboard, semantics, touch target và reduced motion.

Không tạo Figma screen chỉ từ tên route. Mỗi screen issue phải link row, required
state profile, exact breakpoint set và product authority của flow đó.
