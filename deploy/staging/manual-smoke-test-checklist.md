# Checklist Smoke Test Staging OpsHub

Dùng checklist này cho bản staging tải tại:

- Trang tải: https://opshub.hoanghochoi.com/staging-download
- API staging: https://opshub-staging.hoanghochoi.com/api

Tài khoản staging có sẵn:

- `staging.admin@phongvu.vn` / `<STAGING_TEST_PASSWORD>`
- `staging.staff@phongvu.vn` / `<STAGING_TEST_PASSWORD>`
- `staging.acare@acaretek.vn` / `<STAGING_TEST_PASSWORD>`
- `admin@hoanghochoi.com` / `<BREAK_GLASS_PASSWORD>` cho smoke test quyền
  `SUPER_ADMIN` khi cần. Không ghi mật khẩu thật vào checklist hoặc issue.

Không commit mật khẩu staging thật. Lấy `STAGING_TEST_PASSWORD` từ người vận
hành staging hoặc từ env runtime trên server khi cần smoke test.

Lưu ý: DB staging hiện có thể là DB tối giản. Màn hình trống là chấp nhận được
nếu app không crash, không treo loading, không gọi nhầm production, và thông báo
rõ ràng.

## 0. Ghi Chú Lần Test

- Người test:
- Ngày giờ:
- Thiết bị/Hệ điều hành:
- Nền tảng app: Windows / Android
- Phiên bản/build app:
- Link hoặc nguồn build:
- Kết quả chung: Đạt / Không đạt / Bị chặn
- Ghi chú/ảnh lỗi:

## 1. Cài Đặt Và Định Danh App

- [x] Mở `https://opshub.hoanghochoi.com/staging-download`.
- [x] Trang tải hiển thị rõ `PhongVu OpsHub Staging`.
- [x] Tải được bộ cài Windows.
- [x] Cài Windows staging cạnh production, không ghi đè production.
- [x] Tên app, shortcut, thư mục cài đặt Windows là `PhongVu OpsHub Staging`.
- [x] Tải được APK Android.
- [x] Cài Android staging cạnh production, không ghi đè production.
- [x] Nhãn app Android là `PhongVu OpsHub Staging`.
- [x] Package Android là `com.example.phongvu_opshub.staging`.
- [x] Mở app staging không làm mất session hoặc dữ liệu của app production.

## 2. Endpoint Và Thông Tin Cập Nhật

- [x] App mở được, không báo lỗi kết nối API.
- [x] Nếu có prompt cập nhật, link cập nhật trỏ về `/staging-download/downloads/...`.
- [x] Không có link tải/cập nhật nào trỏ về `/download` production.
- [x] `https://opshub-staging.hoanghochoi.com/health` trả `ok`.
- [x] `https://opshub-staging.hoanghochoi.com/api/health` trả JSON health của backend.
- [x] `https://opshub-staging.hoanghochoi.com/api/app-version?platform=android` trỏ về `/staging-download/downloads/`.
- [x] `https://opshub-staging.hoanghochoi.com/api/app-version?platform=windows` trỏ về `/staging-download/downloads/`.
- [x] `https://opshub.hoanghochoi.com/staging-download/downloads/latest.json` chỉ chứa URL artifact staging.

## 3. Đăng Nhập, Session Và Đăng Xuất

- [x] Đăng nhập `admin@hoanghochoi.com` thành công dù email không thuộc cây domain vận hành.
- [x] `admin@hoanghochoi.com` có role `SUPER_ADMIN`, không bị ép chọn SR/showroom.
- [x] Đăng nhập `staging.admin@phongvu.vn` thành công.
- [x] Đăng xuất thành công và quay về màn hình đăng nhập.
- [x] Đăng nhập lại cùng tài khoản admin thành công.
- [x] Nhập sai mật khẩu thì app báo lỗi rõ ràng.
- [ ] Đăng nhập `staging.staff@phongvu.vn` thành công.
- [ ] User staff hiển thị store/scope `STG01` khi có thông tin store.
- [ ] Đăng nhập `staging.acare@acaretek.vn` thành công.
- [ ] User ACare vào được app, không bị ép vào luồng chọn store sai.
- [ ] Đăng nhập cùng một user trên Windows và Android không đá session sai nền tảng.
- [ ] Sau khi logout, nút back/navigation không mở lại màn hình đã đăng nhập.

## 4. Trang Chủ, Drawer, Hồ Sơ, Cài Đặt

- [ ] Trang chủ render đầy đủ card tính năng, không trắng màn hình, không vỡ layout.
- [ ] Drawer mở được và có `Thông tin cá nhân`, `Phản hồi`, `Cài đặt`, `Thông tin ứng dụng`.
- [ ] Màn hình hồ sơ tải được thông tin user.
- [ ] Upload avatar nhỏ thành công hoặc báo validation rõ ràng.
- [ ] Luồng đổi mật khẩu mở được. Nếu test đổi thật, đổi lại về `<STAGING_TEST_PASSWORD>`.
- [ ] Màn hình cài đặt mở được.
- [ ] Đổi giao diện sáng/tối/hệ thống hoạt động.
- [ ] Trên Windows, bật/tắt `Khởi động cùng Windows` hoạt động hoặc báo lỗi rõ ràng.
- [ ] Trên nền tảng không hỗ trợ, setting Windows-only báo không hỗ trợ hợp lý.

## 5. Quản Trị Và Phân Quyền

- [ ] `admin@hoanghochoi.com` thấy đầy đủ menu quản trị và không bị chặn feature.
- [ ] `staging.admin@phongvu.vn` thấy card/menu `Quản trị`.
- [ ] Danh sách người dùng tải được.
- [ ] Filter người dùng theo tên/email vẫn hoạt động.
- [ ] Filter người dùng theo domain hoạt động với `phongvu.vn` và `acaretek.vn`.
- [ ] Filter người dùng theo cơ cấu tổ chức hoạt động hoặc empty state rõ ràng.
- [ ] Filter người dùng theo màn hình/chức năng hoạt động hoặc empty state rõ ràng.
- [ ] Filter người dùng theo role và trạng thái hoạt động.
- [ ] Tạo user test tạm bằng email an toàn, ví dụ `smoke.user@phongvu.vn`.
- [ ] Sửa role/store/scope của user test và lưu được.
- [ ] Trong dialog sửa user, section `Chức năng được sử dụng` hiển thị dạng checkbox tree.
- [ ] Tick nhiều chức năng cho user test và lưu được.
- [ ] User test chỉ thấy/dùng được các màn hình đã tick sau khi đăng nhập lại.
- [ ] Bỏ tick một chức năng của user test, đăng nhập lại và xác nhận route/API tương ứng bị chặn rõ ràng.
- [ ] Reset mật khẩu user test từ màn admin.
- [ ] Màn hình `Cơ cấu tổ chức` tải được dạng tree.
- [ ] Root domain mặc định có `phongvu.vn` và `acaretek.vn`.
- [ ] Tạo subdomain test dưới `phongvu.vn`, ví dụ `smoke-staging.phongvu.vn`, rồi thấy node xuất hiện đúng cấp.
- [ ] Sửa tên/trạng thái node test và tải lại vẫn giữ dữ liệu.
- [ ] Tạo node con dưới subdomain test, ví dụ phòng ban/showroom/chức danh, rồi thấy đúng cấp tree.
- [ ] Xóa node đang có con hoặc có liên kết bị chặn hoặc chuyển inactive rõ ràng, không crash.
- [ ] Xóa node test rỗng thành công, hoặc inactive nếu backend phát hiện đã từng được dùng.
- [ ] Màn hình vai trò tải được.
- [ ] Màn hình SR/store tải được và có `STG01` hoặc dữ liệu store staging.
- [ ] Màn hình vùng/miền tải được.
- [ ] Màn hình phòng ban/chức danh tải được.
- [ ] Màn hình quản lý tính năng có các feature chính: `ADMIN`, `FIFO`, `WARRANTY`, `VIETQR`, `BANK_STATEMENTS`, `PAYMENT_MONITOR`, `FEEDBACK`.
- [ ] Màn hình policy tải được và có policy/rule mặc định.
- [ ] User không có quyền admin không thấy route admin, hoặc bị điều hướng ra ngoài.
- [ ] Admin ACare không quản lý được user ngoài phạm vi nếu code chặn, hoặc báo lỗi phân quyền rõ ràng.

## 6. FIFO Và Sắp Xếp

- [ ] Mở menu FIFO.
- [ ] Mở `Kiểm tra FIFO`.
- [ ] Tìm thử SKU staging như `SKU-SMOKE-001`.
- [ ] Nếu không có dữ liệu, app hiển thị empty/error rõ ràng và không crash.
- [ ] Tìm thử một serial staging bất kỳ.
- [ ] Mở `Sắp xếp FIFO`.
- [ ] Nhập SKU và số lượng hợp lệ rồi submit.
- [ ] Kết quả sắp xếp, empty state, hoặc lỗi validation hiển thị rõ ràng.
- [ ] Mở lịch sử FIFO.
- [ ] Lịch sử FIFO tải được log smoke mới hoặc empty state.
- [ ] Tuỳ chọn: import một file tồn kho nhỏ vào staging, rồi kiểm tra FIFO lại.

## 7. Bảo Hành / Sửa Chữa

- [ ] Mở `BH / SC`.
- [ ] Mở luồng tạo/upload bảo hành.
- [ ] Nhập mã phiếu hợp lệ, ví dụ `CP01-J12345678`.
- [ ] Đính kèm một ảnh nhỏ.
- [ ] Submit phiếu bảo hành.
- [ ] Thành công hoặc lỗi validation hiển thị rõ ràng; không bị treo loading.
- [ ] Mở màn tra cứu bảo hành.
- [ ] Tìm lại mã phiếu vừa dùng.
- [ ] Nếu upload ảnh thành công, URL ảnh load qua staging `/uploads/...`.
- [ ] File upload mới nằm dưới `/srv/opshub-staging/uploads`, không nằm ở storage production.

## 8. Phản Hồi Và App Logs

- [ ] Mở drawer -> `Phản hồi`.
- [ ] Gửi phản hồi chỉ có text, nội dung bắt đầu bằng `SMOKE STAGING`.
- [ ] Gửi phản hồi kèm một ảnh nhỏ.
- [ ] Trạng thái gửi thành công/lỗi hiển thị rõ ràng.
- [ ] Tạo một lỗi nhẹ an toàn, ví dụ FIFO không có dữ liệu hoặc login sai mật khẩu.
- [ ] Sau lỗi, app vẫn dùng bình thường.
- [ ] Tuỳ chọn kiểm tra server: `/app-logs` nhận log client hoặc API không log lỗi upload lặp liên tục.

## 9. VietQR, Sao Kê, Tiền Vào

- [ ] Mở `VietQR` nếu menu hiển thị.
- [ ] Nếu staging chưa cấu hình tài khoản chuyển khoản, app báo validation/error rõ ràng.
- [ ] Không có QR hoặc transfer URL nào dùng dữ liệu production.
- [ ] Mở `Sao kê` nếu menu hiển thị.
- [ ] Chạy một tìm kiếm đơn giản.
- [ ] Empty/no-data state hiển thị rõ ràng và không crash.
- [ ] Không chạy credentials MAP production trong staging.
- [ ] Trên Windows, mở `Tiền vào` nếu menu hiển thị.
- [ ] Toggle theo dõi/loa nếu có quyền.
- [ ] Trạng thái không có giao dịch được xử lý rõ ràng.
- [ ] Trên Android, payment monitor bị ẩn hoặc hiển thị màn không hỗ trợ.

## 10. Realtime Và Cách Ly Môi Trường

- [ ] Các màn cần realtime không reconnect liên tục.
- [ ] Tuỳ chọn kiểm tra server: container `realtime` của staging healthy.
- [ ] Tuỳ chọn kiểm tra server: `cloudflared-opshub-staging` đang active.
- [ ] Tuỳ chọn kiểm tra server: UFW không mở public `22`, `80`, `443`.
- [ ] File upload nằm dưới `/srv/opshub-staging/uploads`.
- [ ] Artifact tải app nằm dưới `/srv/opshub-staging/downloads`.
- [ ] Không có API call staging nào dùng `https://opshub.hoanghochoi.com/api`.
- [ ] Không có upload/download staging nào ghi vào `/srv/opshub` production.

## 11. Tiêu Chí Chấp Nhận Cuối

- [ ] Windows staging cài được và mở được cạnh production.
- [ ] Android staging cài được và mở được cạnh production.
- [ ] Cả ba tài khoản staging đăng nhập được.
- [ ] Bề mặt admin tải được.
- [ ] Gửi phản hồi hoạt động.
- [ ] Luồng upload bảo hành hoạt động hoặc lỗi validation staging rõ ràng.
- [ ] FIFO/sort không crash khi staging thiếu dữ liệu.
- [ ] App-version và download manifest trỏ về `/staging-download/downloads/`.
- [ ] Không đụng endpoint hoặc storage production trong lúc smoke test.
- [ ] Mọi lỗi được ghi lại kèm ảnh chụp, thời điểm, user, nền tảng và bước tái hiện.
