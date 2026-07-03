# UI/UX AUDIT & REFACTOR PLAN — PhongVu OpsHub
**Ngày Audit:** 03/07/2026
**Vai trò:** Principal Product Designer, UX Researcher & Senior Frontend Architect
**Đối tượng:** Ứng dụng PhongVu OpsHub (Flutter Web/Desktop/Mobile)

---

## 1. Executive Summary
OpsHub là hệ thống điều hành nội bộ dành cho nhân viên Phong Vũ (Showroom, Kho, Kế toán, Admin). Qua quá trình kiểm tra và phân tích toàn diện mã nguồn (`lib/features/` và `lib/app/`), hệ thống hiện tại đã có bộ khung Design System 2026 khá tốt. Tuy nhiên, giao diện vẫn gặp các lỗi nghiêm trọng về **Trùng lặp luồng điều hướng (Duplicate Navigation Surfaces)**, **Quá tải thông tin lặp (Information Redundancy)** ở các Header Card, và **Cognitive Load cao** do thiết kế Mobile-first chưa tối ưu tốt cho mật độ thông tin hiển thị trên Desktop/Tablet.

Kế hoạch này đề xuất tối giản hóa tối đa IA (Information Architecture), tinh gọn cấu trúc layout của từng màn hình, loại bỏ các thành phần dư thừa không phục vụ người dùng cuối để nâng cao năng suất vận hành.

---

## 2. Overall Assessment
*   **Information Architecture (5/10):** IA bị phân mảnh và trùng lặp. Việc tồn tại song song cả `HomeScreen` (grid các tính năng), `TasksScreen` (grid tương tự) và `DesktopSidebar` tạo ra 3 điểm truy cập trùng lặp cho cùng một tính năng.
*   **Information Hierarchy (4/10):** Sự phân bậc thông tin bị chồng chéo. Hầu hết các màn hình đều lạm dụng widget Header Card lặp lại nguyên văn tiêu đề và mô tả đã hiển thị trên TopBar/AppBar.
*   **Visual Design Consistency (7/10):** Thiết kế dùng chung bảng màu `AppColors` và typography `AppTextStyles` khá nhất quán, tuy nhiên selected contrast ở Sidebar và trạng thái hover/focus chưa tối ưu.
*   **UX & Cognitive Load (5/10):** Quá nhiều nút bấm, checkbox, và chip trạng thái hiển thị cùng lúc ngay cả khi chưa có dữ liệu (ví dụ ở FIFO Check), bắt người dùng đọc quá nhiều text rác.
*   **Responsive & Adaptability (7/10):** Đã hỗ trợ layout đa màn hình bằng `AppResponsiveContent`, nhưng một số chi tiết như Tablet Rail bị thiếu label mô tả trực quan và avatar trên Mobile quá to.

---

## 3. UI Problems

### Vấn đề 1: Trùng lặp màn hình điều hướng (HomeScreen vs TasksScreen)
*   **Vị trí:** `lib/app/navigation/tasks_screen.dart` và `lib/features/home/presentation/screens/home_screen.dart`
*   **Mức độ nghiêm trọng:** Critical
*   **Ảnh hưởng:** Người dùng bị bối rối vì cả Trang chủ và Tác vụ đều hiển thị danh sách grid các tính năng (`AppFeatureGrid`).
*   **Nguyên nhân:** Logic phân quyền `AppNavModel` cấu hình một số item hiển thị ở cả Sidebar, Tasks và MobileNav.
*   **Hướng xử lý:** Xóa bỏ hoàn toàn màn hình `TasksScreen` và route `/tasks`. Tập trung toàn bộ danh sách tính năng khả dụng tại `HomeScreen`.

### Vấn đề 2: Lạm dụng Header Card trên các màn hình chức năng
*   **Vị trí:** `_FifoMenuHeader` (trong `fifo_menu_screen.dart`), `_WarrantyMainHeader` (trong `warranty_main_screen.dart`), và các header tương tự.
*   **Mức độ nghiêm trọng:** High
*   **Ảnh hưởng:** Phí phạm không gian hiển thị hữu ích trên Desktop/Tablet. Người dùng phải đọc đi đọc lại định nghĩa tính năng mà họ đã biết rõ.
*   **Nguyên nhân:** Copy-paste pattern "Hero Card" từ trang chủ vào tất cả các menu nghiệp vụ con.
*   **Hướng xử lý:** Loại bỏ toàn bộ các Header Card màu mè có mô tả dài dòng ở các màn hình con. Chỉ hiển thị trực tiếp danh sách công việc/bảng dữ liệu.

### Vấn đề 3: Trạng thái highlight của Desktop Sidebar thiếu tương phản
*   **Vị trí:** `_SidebarItem` trong `lib/app/navigation/app_shell.dart`
*   **Mức độ nghiêm trọng:** Medium
*   **Ảnh hưởng:** Text selected vẫn giữ màu trắng hoặc xanh nhạt trên nền sidebar tối (`0xFF101828`), rất khó nhận diện mục nào đang được chọn đối với người có thị lực kém.
*   **Nguyên nhân:** Màu `sidebarSelected` và cách phối màu text chưa tạo đủ độ tương phản cần thiết (WCAG AA).
*   **Hướng xử lý:** Thiết kế lại selected state: Sử dụng một thanh chỉ thị màu xanh thương hiệu ở cạnh trái (indicator border-left) thay vì tô màu nền của cả block menu.

---

## 4. UX Problems

### Vấn đề 1: Thiếu cơ chế lưu lịch sử tìm kiếm nhanh (Recent Searches)
*   **Vị trí:** `lib/features/fifo/presentation/screens/fifo_check_screen.dart` và `lib/features/sort/presentation/screens/sort_screen.dart`
*   **Mức độ nghiêm trọng:** Medium
*   **Ảnh hưởng:** Nhân viên kho phải quét hoặc gõ lại SKU/Serial nhiều lần trong ngày, tốn thời gian và thao tác lặp lại.
*   **Nguyên nhân:** Giao diện tìm kiếm chỉ có ô nhập thô, chưa tích hợp local storage để cache các từ khóa tìm kiếm gần nhất.
*   **Hướng xử lý:** Bổ sung dropdown gợi ý danh sách 5 SKU/Serial tìm kiếm gần nhất ngay khi trỏ chuột/focus vào ô tìm kiếm.

### Vấn đề 2: Đăng xuất đột ngột không qua xác nhận
*   **Vị trí:** `_AccountMenuButton` trong `lib/app/navigation/app_shell.dart`
*   **Mức độ nghiêm trọng:** Medium
*   **Ảnh hưởng:** Người dùng click nhầm nút Đăng xuất sẽ bị đá văng ra màn hình Login lập tức, làm mất phiên làm việc hiện tại và gây ức chế.
*   **Nguyên nhân:** Sự kiện chọn item `_AccountAction.logout` gọi trực tiếp `authProvider.logout()` mà không qua hộp thoại xác nhận.
*   **Hướng xử lý:** Bổ sung `showDialog` xác nhận: *"Bạn có chắc chắn muốn đăng xuất khỏi OpsHub?"* trước khi thực hiện hành động.
*   **Trạng thái:** Batch 4B hoàn thành ngày 03/07/2026: AppShell account menu
    và Profile session card đều hiển thị hộp thoại `Xác nhận đăng xuất`, nhánh
    ở lại không gọi `AuthProvider.logout()`, nhánh xác nhận mới hủy phiên và
    các nhánh requested/cancelled/confirmed/succeeded/failed đều có AppLogger.
    Validation: changed-file `dart format`, formatter check
    `dart format --output=none --set-exit-if-changed`, `git diff --check`,
    `flutter analyze --no-pub`, focused AppShell/Profile/Button tests (9 tests), và full
    `flutter test --no-pub --reporter compact` (321 tests).

---

## 5. Information Architecture Problems
Cấu trúc cây thư mục và luồng điều hướng hiện tại đang bị "phẳng hóa" quá mức, khiến người dùng không cảm nhận được mối liên hệ nghiệp vụ giữa các tính năng.

### Luồng IA Hiện Tại (Flat & Trùng Lặp)
```
[User Login]
  ├── Sidebar (Desktop) -> Home, Admin, FIFO, BH/SC, VietQR, Tiền vào, Sao kê, Cấn trừ, Báo cáo...
  ├── HomeScreen -> Grid chứa toàn bộ các icon trên
  └── TasksScreen -> Grid tương tự HomeScreen (Trùng lặp 90%)
```

### Đề xuất IA Mới (Tập trung & Phân nhóm)
```
[User Login]
  └── App Shell
        ├── Desktop Sidebar (Phân nhóm rõ ràng):
        │     ├── Nhóm I: VẬN HÀNH (Trang chủ)
        │     ├── Nhóm II: NGHIỆP VỤ KHO (Kiểm tra FIFO, Sắp xếp, Bảo hành)
        │     ├── Nhóm III: TÀI CHÍNH & THANH TOÁN (VietQR, Tiền vào, Sao kê, Cấn trừ)
        │     └── Nhóm IV: HỆ THỐNG (Quản trị, Góp ý, Cài đặt)
        └── Mobile Bottom Nav (Tối giản 3 Tab):
              ├── Tab 1: Trang chủ (Grid chứa các shortcut nghiệp vụ)
              ├── Tab 2: Thông báo (Hộp thư đến)
              └── Tab 3: Cá nhân (Thông tin & Cài đặt)
```

---

## 6. Information Hierarchy Problems

### Màn hình: `HomeScreen`
*   **Current Hierarchy:**
    1.  TopBar: "Trang chủ"
    2.  `_HomeCommandPanel` (Card lớn): Chào mừng "Trang chủ vận hành" + Avatar + Tên + Showroom.
    3.  Section Title: "Không gian làm việc"
    4.  Grid Action Tiles.
*   **Vấn đề:** Card thông tin người dùng chiếm quá nhiều diện tích dọc trên Mobile, đẩy Grid tính năng xuống dưới nếp gấp màn hình (below the fold).
*   **Recommended Hierarchy:**
    1.  TopBar tích hợp avatar nhỏ và tên Showroom ở góc phải.
    2.  Chào mừng dạng inline text ngắn gọn không dùng Card: *"Chào em, Nguyễn Văn A (Showroom Hà Nội)"*.
    3.  Hiển thị trực tiếp Grid Action Tiles lên trên cùng để nhấn chọn nhanh nhất.

### Màn hình: `FifoCheckScreen`
*   **Current Hierarchy:**
    1.  Header Card: "Kiểm tra FIFO" + Mô tả chi tiết cách dùng + 4 Chips trạng thái trống.
    2.  Command Card: Ô nhập liệu SKU/Serial + Nút Quét + Nút Tìm kiếm + Toggle hiển thị đã xuất kho.
    3.  Result Panel: Empty State (văn bản hướng dẫn) hoặc Danh sách sản phẩm.
*   **Vấn đề:** 4 Chips ở Header hiển thị "Chưa kiểm tra", "0 sản phẩm",... khi chưa search gây nhiễu thị giác cực kỳ lớn.
*   **Recommended Hierarchy:**
    1.  Ô tìm kiếm và nút quét đặt ở đầu trang (Command Bar tối giản).
    2.  Khu vực kết quả hiển thị trung tâm.
    3.  Các chip trạng thái chỉ xuất hiện khi đã có kết quả tìm kiếm thực tế để bổ trợ thông tin.

---

## 7. Duplicate Content

| Vị trí phát hiện | Nội dung trùng lặp | Nguyên nhân | Đề xuất giải pháp |
| :--- | :--- | :--- | :--- |
| **TopBar & Header Card** | Chữ "FIFO" và mô tả tính năng xuất hiện cùng lúc ở cả tiêu đề thanh điều hướng và thẻ mô tả bên dưới. | Thiết kế rập khuôn cho mọi trang con. | Xóa Header Card ở màn hình con. Chỉ giữ tiêu đề ngắn trên TopBar. |
| **HomeScreen & TasksScreen** | Toàn bộ danh sách Grid `AppFeatureTile` bị lặp lại ở cả hai màn hình. | Phân loại nhầm vai trò của hai màn hình. | Xóa bỏ hoàn toàn màn hình `TasksScreen`. |
| **Desktop Sidebar Item** | Chevron icon (`chevron_right`) xuất hiện ở tất cả các dòng menu bên phải. | Dùng chung code với menu phân tầng. | Xóa icon Chevron vì đây là điều hướng phẳng, click là chuyển trang. |

---

## 8. Internal Information Exposed

| Vị trí giao diện | Nội dung kỹ thuật lộ ra | Ảnh hưởng đến người dùng cuối | Đề xuất sửa đổi |
| :--- | :--- | :--- | :--- |
| **Support Dialog** | Raw Seatalk group link dài dòng có chứa token `invite_id=IkaYSK...` | Nhìn rối rắm, mang tính kỹ thuật, người dùng khó copy bằng tay trên điện thoại. | Ẩn link thô đi. Thay bằng nút bấm "Mở Group Seatalk" và nút "Sao chép liên kết". |
| **HomeScreen StoreInfo** | Chuỗi text mặc định `"Chưa có SR được gán"` | Viết tắt thuật ngữ nội bộ "SR" (Showroom) khó hiểu. | Đổi thành `"Chưa gán Showroom làm việc"`. |
| **VietQR Screen** | Các trạng thái lỗi thô từ API như `MISSING_MATCH_FIELDS`, `MULTIPLE_MATCHES` | Người dùng showroom không hiểu các mã lỗi lập trình này. | Map các mã lỗi này sang câu thông báo thân thiện: *"Thiếu thông tin đối chiếu"* hoặc *"Giao dịch trùng khớp nhiều đơn hàng, cần kiểm tra thủ công"*. |

---

## 9. Visual Design Problems
*   **Typography:** Phông chữ hệ thống `SF Pro Display` không được bundle kèm ứng dụng trên Android/Windows, dẫn đến việc chữ hiển thị bị nhảy font không đồng đều trên các thiết bị khác nhau.
*   **Mật độ Spacing:** Button height mặc định đang là `52px` cho mọi màn hình. Chiều cao này tối ưu cho touch target của mobile nhưng lại quá to và thô trên giao diện web/desktop của máy tính.
*   **Skeleton Loading:** Widget `_SkeletonBlock` chỉ sử dụng một dải màu gradient tĩnh đứng im, trông giống như một khối màu bị lỗi chứ không tạo cảm giác ứng dụng đang xử lý dữ liệu.

---

## 10. Component Audit

### Components nên loại bỏ hoặc gộp (Remove & Merge)
*   **`TasksScreen` (`tasks_screen.dart`):** Loại bỏ hoàn toàn.
*   **`_TasksHeader`:** Xóa bỏ cùng màn hình Tasks.
*   **`_FifoMenuHeader` & `_WarrantyMainHeader`:** Xóa bỏ để giải phóng không gian màn hình con.
*   **Chevron Icons** ở Sidebar: Xóa bỏ để tinh gọn giao diện.

### Components cần thiết kế lại (Redesign)
*   **`_SkeletonBlock`:** Cần bổ sung animation chạy mượt (shimmer effect) bằng cách xoay chuyển tọa độ của gradient theo thời gian.
*   **`_HomeCommandPanel`:** Thu nhỏ kích thước avatar từ `104px` xuống `40px` trên mobile, biến chiếc thẻ (Card) cồng kềnh thành một dải chào mừng (Welcome Strip) gọn gàng nằm ngay dưới appBar.
*   **`_AccountMenuButton`:** Cần hiển thị rõ ràng focus border khi người dùng dùng bàn phím để điều hướng (Accessibility).

---

## 11. Screen-by-Screen Audit

### Màn hình: Trang chủ (`/home`)
*   **Cấu trúc hiện tại:**
    ```
    TopBar -> HomeCommandPanel (Card to) -> Toggle đọc loa -> Section "Không gian làm việc" -> Grid các tiles.
    ```
*   **Cấu trúc đề xuất:**
    ```
    TopBar (chứa avatar & showroom) -> Toggle đọc loa -> Grid các tiles nghiệp vụ.
    ```
*   **Lý do:** Tối đa hóa diện tích hiển thị của các nút tính năng để nhân viên showroom có thể ấn ngay khi vừa mở app.

### Màn hình: FIFO Menu (`/fifo-menu`)
*   **Cấu trúc hiện tại:**
    ```
    TopBar -> FifoMenuHeader (Card to) -> Section "Chức năng FIFO" -> Grid 4 tiles con.
    ```
*   **Cấu trúc đề xuất:**
    ```
    TopBar -> Grid 4 tiles con (Kiểm tra FIFO, Sắp xếp FIFO, Cập nhật tồn kho, Lịch sử FIFO).
    ```
*   **Lý do:** Người dùng đã nhấn vào "FIFO" từ menu chính thì không cần đọc lại định nghĩa FIFO là gì nữa.

### Màn hình: Kiểm tra FIFO (`/fifo-check`)
*   **Cấu trúc hiện tại:**
    ```
    TopBar -> FifoHeader (Card to có 4 status chips) -> Command Card (Input + Scan + Search) -> Result Panel.
    ```
*   **Cấu trúc đề xuất:**
    ```
    TopBar -> Command Bar (Input + Scan + Search) -> Result Panel (Chứa các chip trạng thái và danh sách sản phẩm).
    ```
*   **Lý do:** Dọn dẹp header rác, chỉ tập trung vào ô nhập liệu và kết quả thực tế.

---

## 12. Responsive Audit
*   **Desktop (>= 1200px):** Button size quá lớn (52px), cần cấu hình responsive button height (40px trên desktop, 52px trên mobile).
*   **Tablet (900px - 1200px):** Rail Navigation ở cạnh trái chỉ hiển thị Icon và hiển thị tooltip khi hover. Trên màn hình cảm ứng của Tablet (không có con trỏ chuột hover), người dùng sẽ không biết nút đó là gì nếu không có text label nhỏ đi kèm dưới icon.
*   **Mobile (< 600px):** Khoảng trống (padding) rìa ngoài của màn hình đang bị cấu hình cứng ở một số thẻ card làm cho bề ngang hiển thị của form nhập liệu bị thu hẹp quá mức, dễ gây tràn chữ trên các dòng máy nhỏ như iPhone SE.

---

## 13. Accessibility Audit
*   **Tương phản màu (Color Contrast):** Sidebar item khi được chọn (Selected state) cần tăng độ tương phản rõ rệt. Đề xuất dùng highlight border hoặc thay đổi hoàn toàn màu icon sang xanh đậm.
*   **Mục tiêu chạm (Touch Target):** Các nút bấm thu nhỏ/đóng dialog, các checkbox nhỏ cần có padding vô hình xung quanh tối thiểu `44x44px` để nhân viên kho đeo găng tay vẫn có thể bấm trúng dễ dàng trên điện thoại.
*   **Hỗ trợ bàn phím (Keyboard Navigation):** Hiện tại phím `Tab` điều hướng trên trình duyệt web chưa focus chuẩn vào các ô nhập liệu của form tạo VietQR và form điều chỉnh cấn trừ.

---

## 14. Simplification Proposal
Tập trung thực hiện 3 đề xuất tối giản lớn sau để tái cấu trúc toàn diện app:
1.  **Hợp nhất HomeScreen và TasksScreen**: Giữ lại duy nhất màn hình Home làm trung tâm điều hướng nghiệp vụ.
2.  **Lược bỏ Hero Headers**: Tất cả các trang con nghiệp vụ khi được mở ra sẽ hiển thị trực tiếp khu vực làm việc (Workspace), không sử dụng thẻ Header giới thiệu nữa.
3.  **Tối giản hóa thông tin cá nhân**: Di chuyển thông tin người dùng lên thanh TopBar/AppBar để giải phóng màn hình chính.

---

## 15. Component Removal Plan

| Tên Component | File chứa code | Hành động | Lý do |
| :--- | :--- | :--- | :--- |
| **`TasksScreen`** | `tasks_screen.dart` | **XÓA BỎ** | Trùng lặp hoàn toàn chức năng của HomeScreen. |
| **`_TasksHeader`** | `tasks_screen.dart` | **XÓA BỎ** | Đi kèm màn hình Tasks bị xóa. |
| **`_FifoMenuHeader`** | `fifo_menu_screen.dart` | **XÓA BỎ** | Header card rườm rà, lặp thông tin. |
| **`_WarrantyMainHeader`** | `warranty_main_screen.dart` | **XÓA BỎ** | Không cần thiết cho màn hình chỉ có 2 nút bấm. |
| **Chevron Icon** | `app_shell.dart` | **LOẠI BỎ** | Xóa khỏi dòng menu Sidebar để sửa lỗi sai UX affordance. |

---

## 16. Information Cleanup Plan

| Vị trí | Nội dung hiển thị hiện tại | Vấn đề phát hiện | Hướng xử lý đề xuất |
| :--- | :--- | :--- | :--- |
| **Support Dialog** | `https://link.seatalk.io/...invite_id=...` | Lộ link Seatalk nội bộ dài dòng và không thẩm mỹ. | Ẩn link thô, chỉ hiển thị nút bấm hành động. |
| **HomeScreen** | `"Chưa có SR được gán"` | Thuật ngữ viết tắt nội bộ `"SR"` gây khó hiểu. | Đổi thành `"Chưa được gán Showroom"`. |
| **FIFO Check Header** | Các chip `"Chưa kiểm tra"`, `"0 sản phẩm"` | Hiện lên khi chưa có kết quả gây nhiễu giao diện. | Chỉ hiển thị các chip này khi tìm kiếm thành công. |
| **TopBar Title** | Lặp lại nguyên văn mô tả với thẻ Card con. | Lãng phí dòng đọc của mắt. | Giữ mô tả trên TopBar, xóa thẻ Card mô tả con phía dưới. |

---

## 17. Detailed Refactor Roadmap

```mermaid
grid
  Phase1[Phase 1: Quick Wins]
  Phase2[Phase 2: IA & Nav Route]
  Phase3[Phase 3: Clean Headers]
  Phase4[Phase 4: Responsive & Components]
```

### Phase 1: Quick Wins (Thời gian: 3 ngày)
*   **Mục tiêu:** Sửa các lỗi UI nhỏ, tăng tính chuyên nghiệp tức thì.
*   **Công việc:**
    1.  [x] Xóa bỏ chevron icon khỏi các item điều hướng trên Sidebar.
    2.  [x] Ẩn link thô Seatalk trong support dialog, thay bằng nút sao chép link sạch sẽ.
    3.  [x] Ẩn các chip trạng thái trống ở màn hình FIFO Check khi chưa thực hiện search.
    4.  [x] Thay đổi text `"Chưa có SR được gán"` sang `"Chưa được gán Showroom"`.
*   **Trạng thái:** Hoàn thành batch 1 ngày 03/07/2026. Validation:
    `dart format --output=none --set-exit-if-changed`, `git diff --check`,
    `flutter analyze --no-pub`, focused widget tests Home/FIFO/Profile/Cấn trừ
    (13 tests), và full `flutter test --no-pub --reporter compact` (316 tests).
*   **Rủi ro:** Rất thấp. Không ảnh hưởng đến logic nghiệp vụ.

### Phase 2: Information Architecture & Navigation (Thời gian: 5 ngày)
*   **Mục tiêu:** Hợp nhất luồng điều hướng, xóa bỏ màn hình thừa.
*   **Công việc:**
    1.  [x] Xóa file `tasks_screen.dart` và gỡ bỏ màn hình `/tasks` khỏi `app_router.dart`.
    2.  [x] Cấu hình lại `AppNavModel` để xóa bỏ hoàn toàn thuộc tính `showInTasks`.
    3.  [x] Cập nhật lại thanh điều hướng dưới của Mobile (Bottom Navigation Bar) để chỉ chứa các tab thiết yếu: Home, Thông báo, Tài khoản. Batch 4G thêm tab `Thông báo` mobile-only và tái dùng panel thông báo toàn cục; chưa tạo inbox route riêng khi chưa có yêu cầu sản phẩm cho màn hộp thư độc lập.
*   **Trạng thái:** Batch 4A hoàn thành ngày 03/07/2026 cho phần retire
    màn Tasks dư thừa: xóa `TasksScreen`, xóa `showInTasks`, chuyển Home sang
    danh sách workspace permission-aware, gỡ `Tác vụ` khỏi bottom nav, và
    chuyển deep link cũ `/tasks` về `/home`. Validation: changed-file
    `dart format`, `dart format --output=none --set-exit-if-changed`,
    `node --check scripts\opshub-web-visual-smoke.mjs`, `git diff --check`,
    `flutter analyze --no-pub`, focused nav/shell/guard/Home tests (32 tests),
    và full `flutter test --no-pub --reporter compact` (319 tests).
    Batch 4C hoàn thành cùng ngày cho Desktop Sidebar: nhóm rõ các mục thành
    `Tổng quan`, `Nghiệp vụ`, `Cấu hình`, giữ selected indicator cạnh trái và
    không khôi phục chevron. Validation: changed-file `dart format`, formatter
    check `dart format --output=none --set-exit-if-changed`, `git diff --check`,
    `flutter analyze --no-pub`, focused AppShell test (5 tests), và full
    `flutter test --no-pub --reporter compact` (321 tests).
    Batch 4G hoàn thành ngày 04/07/2026 cho Mobile Bottom Nav: thanh dưới còn
    đúng `Trang chủ`, `Thông báo`, `Tài khoản`; tab `Thông báo` mở lại panel
    thông báo toàn cục dạng bottom sheet, có log start/success/failure/skip
    qua `AppLogger`, không thêm route inbox giả.
*   **Rủi ro:** Trung bình. Cần kiểm tra kỹ các liên kết sâu (deep link) từ thông báo đẩy để hướng người dùng về trang chủ thay vì trang tác vụ cũ.

### Phase 3: Layout Simplification & Header Clean (Thời gian: 6 ngày)
*   **Mục tiêu:** Dọn sạch các Header Card trùng lặp, mở rộng diện tích thao tác nghiệp vụ.
*   **Công việc:**
    1.  [x] Gỡ bỏ `_FifoMenuHeader` khỏi `fifo_menu_screen.dart`.
    2.  [x] Gỡ bỏ `_WarrantyMainHeader` khỏi `warranty_main_screen.dart`.
    3.  [x] Thu gọn `_HomeCommandPanel` trên Trang chủ thành dạng dải chào hỏi (Welcome Strip) nằm sát TopBar.
    4.  [x] Rà soát và tinh gọn các thẻ card giới thiệu ở các màn hình con khác như: Tiền vào, Cấn trừ, Sao kê.
*   **Trạng thái:** Batch 2A hoàn thành ngày 03/07/2026 cho FIFO hub và BH/SC
    hub. Validation: `dart format --output=none --set-exit-if-changed`,
    `git diff --check`, `flutter analyze --no-pub`, focused widget/router
    tests route viewport + FIFO hub + BH/SC hub (9 tests), và full
    `flutter test --no-pub --reporter compact` (316 tests). Batch 2B hoàn
    thành cùng ngày cho Home welcome strip, giữ avatar/tên/showroom và log
    `Home command center resolved`. Validation: focused Home/AppShell tests
    (14 tests), `flutter analyze --no-pub`, và full Flutter suite (316 tests).
    Batch 2C hoàn thành cùng ngày cho Tiền vào, Cấn trừ, Sao kê bằng compact
    title/status strips; giữ các chip trạng thái, refresh Cấn trừ và log runtime
    hiện có. Validation: focused finance workspace tests (6 tests),
    `flutter analyze --no-pub`, và full Flutter suite (316 tests).
    Batch 4E hoàn thành cùng ngày cho duplicate title cleanup: TopBar tiếp tục
    sở hữu destination title, còn các header nội dung đổi sang heading theo
    tác vụ/trạng thái như `Công cụ theo quyền`, `Giao dịch cần rà soát`,
    `Yêu cầu xử lý`, `Chia sẻ phản hồi`, `Tùy chọn thiết bị`, `Lối vào báo cáo`
    và `Đơn cần báo cáo`. Guard test mới chặn feature screen dùng lại exact
    shell destination label làm heading/card title. Validation: changed-file
    `dart format`, formatter check
    `dart format --output=none --set-exit-if-changed`, focused UI/guard tests
    (44 tests), `git diff --check`, `flutter analyze --no-pub`, và full
    `flutter test --no-pub --reporter compact`.
*   **Rủi ro:** Thấp. Cần kiểm duyệt thiết kế visual để đảm bảo sau khi xóa card, bố cục trang con vẫn cân đối.

### Phase 4: Component Polish & Accessibility (Thời gian: 5 ngày)
*   **Mục tiêu:** Cải thiện chất lượng chuyển động và trải nghiệm người dùng đặc biệt.
*   **Công việc:**
    1.  [x] Viết thêm animation chạy sáng (shimmer) cho widget `_SkeletonBlock` khi đang tải dữ liệu.
    2.  [x] Thiết kế lại selected highlight của Desktop Sidebar bằng thanh chỉ thị cạnh trái (left border indicator).
    3.  [x] Tích hợp lưu trữ local cache để lưu 5 từ khóa tra cứu gần nhất trong màn hình FIFO Check.
    4.  [x] Khóa layout màn hình con trên Desktop bằng shared responsive wrappers và `contentMaxWidth`.
*   **Trạng thái:** Batch 3A hoàn thành ngày 03/07/2026 cho shared
    `AppListSkeleton`: shimmer gradient chạy theo animation và tôn trọng
    `MediaQuery.disableAnimations`. Validation: focused shared-widget test
    (6 tests), `flutter analyze --no-pub`, và full Flutter suite (317 tests).
    Batch 3B hoàn thành cùng ngày cho Desktop Sidebar: selected state dùng
    indicator cạnh trái 4x28, giữ block menu trong suốt và thêm semantic
    selected. Validation: focused AppShell route test (3 tests),
    `flutter analyze --no-pub`, và full Flutter suite (318 tests).
    Batch 3C hoàn thành cùng ngày cho FIFO Check: lưu tối đa 5 SKU/serial gần
    nhất bằng local cache theo môi trường, chỉ hiện chip khi focus input và log
    cache bằng count/queryLength đã sanitize. Validation: focused FIFO Check
    test (3 tests), `flutter analyze --no-pub`, và full Flutter suite
    (319 tests).
    Batch 4D hoàn thành cùng ngày cho desktop content width: thêm token
    `AppLayoutTokens.contentMaxWidth`, đặt default cho `AppResponsiveContent`
    và `AppResponsiveScrollView`, bổ sung widget test đo constraints desktop,
    và guard để feature screen mới không bỏ shared responsive wrapper.
    Validation: changed-file `dart format`, formatter check
    `dart format --output=none --set-exit-if-changed`, focused
    `flutter test --no-pub --reporter expanded test\app_layout_test.dart test\design_system_migration_guard_test.dart`,
    `git diff --check`, `flutter analyze --no-pub`, và full
    `flutter test --no-pub --reporter compact`.
    Batch 4F hoàn thành cùng ngày cho copy nội bộ/chữ viết tắt: điều hướng và
    màn bảo hành bỏ `BH/SC`, các bộ lọc/chip/dòng trạng thái dùng `showroom`
    thay cho `SR`, báo cáo sale không hiển thị `ERP`, và các màn admin đổi
    `policy/rule/node/internal/Key/JSON` thành nhãn tiếng Việt thân thiện.
    Guard test mới chỉ soi UI copy có khả năng hiển thị để chặn các cụm nội bộ
    lộ lại trong `presentation/screens` và `presentation/widgets`.
*   **Rủi ro:** Thấp. Cần đảm bảo hiệu năng mượt mà của shimmer effect trên các dòng máy Android đời cũ.

---

## 18. Priority Matrix

```
   Cao  │ ┌─────────────────────────┐  ┌─────────────────────────┐
        │ │     PHASE 2: IA & NAV   │  │  PHASE 3: CLEAN HEADERS │
        │ │ (Xóa Tasks Screen,...)  │  │ (Loại bỏ Header Cards)  │
M       │ └─────────────────────────┘  └─────────────────────────┘
Ứ       │
C       │ ┌─────────────────────────┐  ┌─────────────────────────┐
        │ │   PHASE 1: QUICK WINS   │  │   PHASE 4: COMPONENTS   │
Đ       │ │ (Xóa chevron, ẩn URL...)│  │   (Shimmer, selected...)│
Ộ       │ └─────────────────────────┘  └─────────────────────────┘
   Thấp └─────────────────────────────────────────────────────────
                       Thấp                   Cao
                              MỨC ĐỘ PHỨC TẠP
```

---

## 19. Acceptance Checklist
*   [x] Ứng dụng không còn màn hình `TasksScreen` dư thừa.
*   [x] Không còn tiêu đề lặp lại giữa TopBar và nội dung màn hình con.
*   [x] Link mời Seatalk thô đã được ẩn hoàn toàn khỏi hộp thoại Hỗ trợ.
*   [x] Toàn bộ chữ viết tắt mang tính lập trình hoặc viết tắt nội bộ khó hiểu đã được việt hóa thân thiện.
*   [x] Sidebar được chia nhóm nghiệp vụ rõ ràng, không còn chứa icon Chevron điều hướng phẳng.
*   [x] Trạng thái selected trên menu Sidebar có contrast rõ ràng, dễ nhận biết.
*   [x] Khu vực FIFO Check không hiển thị các chip trạng thái rác trước khi người dùng thực hiện quét hoặc tìm kiếm sản phẩm.
*   [x] Bổ sung hộp thoại hỏi ý kiến xác nhận đăng xuất trước khi hủy phiên hoạt động của người dùng.
*   [x] Layout của màn hình con trên Desktop được co giãn theo chiều ngang tối ưu, không bị dãn rộng toàn màn hình.

---

## 20. Estimated Effort
*   **Tổng thời gian dự kiến:** 18 - 20 ngày làm việc (khoảng 2 Sprints vận hành).
*   **Nguồn lực đề xuất:** 01 UI/UX Designer (hỗ trợ kiểm duyệt visual) và 01 Flutter Frontend Developer (thực hiện code refactor).

---

## 21. Risks & Mitigation
*   **Rủi ro 1: Người dùng cũ bị bỡ ngỡ khi mất màn hình Tác vụ (`TasksScreen`).**
    *   *Giảm thiểu:* Tích hợp một tooltip hướng dẫn ngắn ở lần đầu tiên đăng nhập sau khi cập nhật: *"Tất cả tác vụ của bạn hiện đã được đưa ra Trang chủ tiện lợi hơn!"*.
*   **Rủi ro 2: Shimmer animation làm chậm ứng dụng trên thiết bị cấu hình yếu.**
    *   *Giảm thiểu:* Sử dụng `RepaintBoundary` bọc ngoài widget skeleton loading để tránh render lại toàn bộ màn hình khi gradient di chuyển.

---

## 22. Final Recommendation
Em đề xuất Đại ca cho phép triển khai **Phase 1 (Quick Wins)** ngay lập tức để giải quyết nhanh các hạt sạn khó chịu trên giao diện mà không ảnh hưởng tới vận hành chung.

Sau đó, lên kế hoạch cho **Phase 2 và Phase 3** vào kỳ Sprint tiếp theo để tối ưu hóa triệt để cấu trúc ứng dụng theo tiêu chuẩn của các sản phẩm quản trị doanh nghiệp cao cấp (như Stripe, Vercel Dashboard). Giao diện tối giản sẽ giúp nhân viên giảm mỏi mắt, tăng tốc độ xử lý đơn hàng và hạn chế sai sót khi thao tác.
