# OpsHub Redesign Foundation Pack

Status: **Approved — Đại Ca duyệt ngày 26/07/2026**
Issue: **OPS-25**
Baseline: `staging@3fe2e5cd9a7b14813399e68f522e266bd0c958f5`
Ngày audit: **26/07/2026**

Closeout: **Historical Foundation/Figma snapshot — handed off to OPS-34 on
29/07/2026**. Live Figma structure and shared redesign workflow are now owned
by OPS-34; this pack remains the approved input snapshot, not a current node
inventory.

Foundation Pack này là đầu vào đã duyệt của Figma foundation và screen rollout.
Pack không tự thay đổi runtime; Figma draft chỉ trở thành implementation target
sau khi Đại Ca duyệt đúng frame/revision của scope cần triển khai.

## Artifact map

| Artifact | Vai trò | Trạng thái |
| --- | --- | --- |
| `brief.md` | Mục tiêu, người dùng, scope, nguyên tắc và success metrics | Approved |
| `audit-2026-07-26.md` | Audit mới dựa trên baseline hiện tại | Approved |
| `screen-inventory.md` | Inventory đủ 44 route và state/responsive contract | Approved |
| `design-tokens.md` | Exact token proposal và handoff rules | Approved |
| `design-tokens.json` | Token manifest máy đọc được, gần W3C DTCG | Approved |

## Authority và cách đọc

1. Product/business/API/permission/platform/security contracts vẫn do
   `AGENTS.md`, `docs/product/`, code và tests hiện hành kiểm soát.
2. Pack này đề xuất design foundation; chỉ trở thành design direction sau khi
   Đại Ca duyệt đúng revision.
3. Pack approval đã mở bước tạo **Figma foundations/variables/components**.
4. Sau khi foundation revision được duyệt theo từng visual component, Đại Ca đã
   cho phép tự triển khai toàn bộ screen inventory và review lại sau.
5. Screen draft không tự mở Flutter implementation. Mỗi implementation scope
   vẫn cần exact approved frame/revision và các gate của repository.

## Review matrix

| Hạng mục | Trạng thái review | Ý nghĩa |
| --- | --- | --- |
| Brief và protected behavior | Pass | Đã cross-review |
| Route/screen coverage | Pass | Reconcile đúng 44/44 route |
| Exact token values và aliases | Pass | JSON parse + alias check pass |
| Critical color contrast | Pass | 24 pair pass: 22 text + 2 control boundary |
| Be Vietnam Pro license | Pass | Google Fonts ghi nhận SIL Open Font License 1.1 |
| Be Vietnam Pro local assets/hashes | Blocked | Repo chưa có asset hoặc provenance manifest |
| Android/Windows/web font rendering | Blocked | Chỉ chạy sau khi có local assets và runtime issue |
| Authenticated live visual audit | Needs evidence | Không có authenticated runtime capture mới trong task này |
| Đại Ca approval | Pass | Duyệt revision `OPS-25-2026-07-26` ngày 26/07/2026 |
| OPS-25 design closeout | Pass | Đại Ca duyệt closeout ngày 29/07/2026; implementation vẫn cần exact scope riêng |
| Live five-page Figma reconciliation | Handed off | OPS-34 sở hữu cấu trúc hiện hành và proof mới |

Nguồn license: [Google Fonts — Be Vietnam Pro OFL.txt](https://github.com/google/fonts/blob/main/ofl/bevietnampro/OFL.txt).
Khi đưa font vào repo, phải commit cùng copyright/license file, provenance,
version/hash và proof offline trên từng platform.

## Historical Figma completion snapshot và handoff

- File: `https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll`
- Snapshot dưới đây phản ánh OPS-25 vào ngày 27/07/2026, trước khi OPS-34 tái
  cấu trúc file thành năm page canonical.
- Foundation: variables, styles và shared components đã được dựng từ exact
  tokens; visual foundation được duyệt tuần tự trong OPS-25.
- Screen inventory: **44/44 route rows** đã có ledger entry.
- Canonical screen owners: **42/42** có ít nhất một top-level Figma frame.
- Alias/redirect: `/fifo/inventory-import` dùng canonical
  `/admin/inventory-import`; `/reports` redirect sang `/sales-reports` và không
  có screen riêng.
- Narrative QA recorded **222** top-level screen/state roots; the frozen local
  ledger contains **220** route-root references. This historical discrepancy is
  retained explicitly and is not current live-file proof.
- QA ngày 27/07/2026: không duplicate root name, không font ngoài
  Be Vietnam Pro/Material Icons Round, không invalid text geometry và không còn
  generated text box cao 1px.

Trạng thái OPS-25 screen rollout: **Historical design closeout complete — đã
handoff sang OPS-34 ngày 29/07/2026**. Các count và node ID trên không mô tả
live five-page file sau handoff. Mọi Flutter implementation vẫn phải dùng exact
frame/revision do issue hiện hành phê duyệt; closeout này không cấp blanket
runtime authority.

Ledger cục bộ `dsb-state-opshub-ops25.json` được đóng băng như historical
snapshot với SHA-256
`5171D9AAFD7EF44738D988C2A80E8F5DD65F6B97EF913494CDF4F078B782A0A6`.
Ledger giữ taxonomy 28 page và các reference trước cleanup, nên không được dùng
để audit hoặc ghi đè live file hiện do OPS-34 sở hữu.

## OPS-44 live handoff addendum (2026-08-03)

Read-only audit of live Figma file `mFzSmQzlapSe3RSmUhvzll` found eight pages
before OPS-44 consolidation: Cover, Foundation and six platform screen pages.
The current router has 45 `path:` declarations and 43 canonical visual owners.
`/reports` redirects to `/sales-reports`; `/fifo/inventory-import` and
`/admin/inventory-import` enter the same `InventoryImportScreen` flow. These
aliases do not collapse distinct product screens, and no duplicate Figma frame
should be invented. On 2026-08-04 OPS-44 moved all 68 Web top-level nodes into
`Screens — Desktop · Windows + Web` (`693:17492`). The empty archive page
`1174:4` was deleted after explicit unified-revision approval and final
seven-page inventory readback. The consolidated Desktop + Web page contains
Dark coverage board `1874:35444` with 121 route/state owners using explicit
semantic/component Dark modes. The historical OPS-25 counts above remain
frozen; OPS-44 owns live reconciliation.

## Không được suy diễn từ pack

- Token proposal không tự động đổi `AppColors`, `AppTheme` hay Flutter widgets.
- Screen inventory không cấp thêm route, dữ liệu hoặc quyền.
- Priority wave không thay thế product priority hoặc release decision.
- `Pass` về source/test không đồng nghĩa live visual parity.
