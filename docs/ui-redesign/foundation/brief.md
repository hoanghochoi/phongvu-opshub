# OpsHub Redesign Brief

Status: **Approved — OPS-25-2026-07-26**
Owner: OPS-25
Baseline: `3fe2e5cd9a7b14813399e68f522e266bd0c958f5`

## 1. Outcome

Redesign OpsHub thành một workspace vận hành nội bộ rõ, nhanh, nhất quán và ít
sai sót hơn trên Android và Windows; web tiếp tục là surface được hỗ trợ. Đợt
redesign được phép thay visual hierarchy và interaction presentation, nhưng
không được tự ý thay nghiệp vụ, dữ liệu, quyền hoặc capability theo platform.

## 2. Người dùng và jobs-to-be-done

| Nhóm người dùng | Nhu cầu chính | Điều cần tránh |
| --- | --- | --- |
| Nhân viên cửa hàng | Tìm đúng công cụ, scan/search/submit nhanh, biết kết quả và bước tiếp theo | Menu rối, nút chính xa input, lỗi kỹ thuật |
| Quản lý cửa hàng/khu vực | Theo dõi trạng thái, duyệt cấu hình được cấp quyền, xử lý ngoại lệ | Không rõ phạm vi dữ liệu/quyền |
| Nhân sự kho/kỹ thuật | FIFO, tra cứu và xử lý bảo hành theo trình tự | Mất context khi scan/chuyển bước |
| Nhân sự tài chính/vận hành | Rà soát giao dịch, sao kê, cấn trừ và báo cáo dữ liệu dày | Bảng khó quét, filter không nhất quán |
| Quản trị viên được phân quyền | Quản lý tài khoản, tổ chức, chính sách và feature | Lộ mã role/policy hoặc thao tác nguy hiểm thiếu cảnh báo |

## 3. Platform priority

1. **Android:** touch-first, thao tác một tay, scanner/keyboard/safe-area rõ.
2. **Windows:** keyboard/mouse-first, bảng dữ liệu, multi-column và scrollbars.
3. **Web:** giữ route, responsive, selection/paste và authenticated shell
   contracts; không xem web là bản desktop co giãn tùy ý.
4. iOS/macOS/Linux phải không bị phá vỡ nếu build hiện tại vẫn hỗ trợ, nhưng
   không phải primary proof surface của redesign phase đầu.

## 4. Scope

Được phép thiết kế lại sau khi qua đúng approval gate:

- visual hierarchy, typography, spacing, radius, elevation và density;
- shell/navigation presentation trong giới hạn route/permission hiện tại;
- form, table/list, filter, feedback/data states và component appearance;
- responsive composition cho compact, medium, expanded và wide desktop;
- motion phục vụ state/continuity/confirmation và có reduced-motion mode.

Protected behavior không được tự thay:

- authentication, organization assignment và session redirects;
- route, API/data contract, permission/feature guard và platform capability;
- DateRangePicker dùng chung, command-input cùng hàng với primary actions,
  related-flow modal consistency và fixed context header của long modal;
- global selection/paste, dialog dismissal, scanner helper, pagination,
  AppLogger và Vietnamese-first copy;
- behavior của screen chưa migrate.

## 5. Non-goals

- Không rewrite toàn app trong một phase hoặc một PR.
- Không phát minh dashboard metric, workflow, route, role hay backend action.
- Không đổi information architecture chỉ để “trông mới”.
- Không tạo design system song song với shared Flutter layer hiện có.
- Không dùng card/gradient/motion làm trang trí nếu không cải thiện hierarchy.
- Không dùng pack này làm bằng chứng rằng runtime đã migrate.

## 6. Design principles

1. **Task first:** primary job và trạng thái hiện tại phải đọc được trong vài
   giây; decoration đứng sau thông tin và hành động.
2. **Calm density:** dữ liệu dày nhưng có nhịp, grouping và progressive
   disclosure; tránh card lồng card.
3. **One shared language:** cùng action/state dùng cùng token, component và copy.
4. **Permission without jargon:** chỉ hiện action được phép; blocker giải thích
   bằng tiếng Việt cho staff, mã kỹ thuật chỉ nằm trong logs/config.
5. **Responsive by composition:** đổi bố cục theo available width, không thu nhỏ
   desktop screen thành mobile.
6. **Accessible by default:** WCAG 2.2 AA target, focus rõ, keyboard, semantics,
   text scaling, reduced motion và màu không phải tín hiệu duy nhất.
7. **Reversible migration:** shared foundation trước, representative screens
   sau; unmigrated consumers tiếp tục chạy.

## 7. Representative design waves

| Wave | Mục đích | Candidate surfaces |
| --- | --- | --- |
| Foundation | Khóa variables, type, spacing, states và core components | Không có screen |
| Pilot | Kiểm chứng form, dashboard, command/scan, data-heavy, list/detail | Login, Home, FIFO Check, Bank Statement, Warranty Check/Detail |
| Operational | Migrate workflow có tần suất/ảnh hưởng cao | VietQR, Payment Monitor, Sales Reports, Offset Adjustment |
| Administration | Migrate surfaces quyền cao và CRUD dày | Admin menu và các admin routes |
| Long tail | Hoàn tất settings/help/feedback và alias/special states | Settings, Help, Feedback, unsupported/system states |

Wave chỉ là đề xuất dependency; priority sản phẩm cuối cùng vẫn cần Đại Ca duyệt.

## 8. Success metrics

### Foundation/QA gates — bắt buộc

- 44/44 route được inventory hoặc phân loại redirect/alias/detail rõ.
- 100% critical text/control color pairs đạt mục tiêu contrast đã khai báo.
- Không còn token để ngỏ, alias hỏng hoặc tên khác nhau giữa Markdown/JSON/Figma handoff.
- 0 route/API/permission/platform behavior bị thay bởi design-only scope.
- 0 critical overflow, inaccessible primary action hoặc keyboard trap trên
  representative compact/medium/expanded/wide viewports.
- Tất cả representative screens có required loading/empty/error/long-content/
  text-scale states hoặc lý do `N/A` được duyệt.

### Product outcome — cần baseline trước implementation

- Task success của representative usability test đạt ít nhất 90%.
- Median time-to-complete của ba tác vụ tần suất cao giảm ít nhất 15% so với
  baseline cùng fixture.
- User-error/retry rate của scan/search/submit flows giảm ít nhất 20%.
- Ít nhất 90% người tham gia tìm đúng workspace mà không cần trợ giúp.

Các target product trên là acceptance proposal, chưa phải số đo hiện tại. Trước
pilot implementation phải chốt task fixture, participant mix và baseline.

## 9. Approval boundaries

- Đại Ca duyệt pack/revision, không duyệt bằng status hoặc im lặng.
- Pack approval mở Figma foundation work, chưa mở Figma screens.
- Figma foundation approval mở screen-design scope cụ thể.
- Screen approval mở Flutter implementation đúng frame/revision đó.
- Mọi thay đổi visual sau approval cần revision và re-approval.
