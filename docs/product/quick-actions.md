# Thao tác nhanh

## Mục tiêu v1

Thao tác nhanh cung cấp một launcher nhất quán cho các tác vụ thường dùng mà
không thay đổi quyền truy cập các màn hình gốc. Mobile compact hiển thị nút tia
sét ở giữa thanh điều hướng và menu dạng lưới tự xuống hàng, không cuộn ngang;
Windows native chỉ hiển thị tại
`/home`, cách mép phải và dưới 24px, với menu dọc bung lên.

Thứ tự cố định: Kiểm tra FIFO, VietQR, Chăm sóc lại, Báo cáo bán hàng, Tải app,
Check-in, Zalo OA và GG Map. Card `Công cụ nhanh` cũ trên Home không còn hiển thị.
Client lưu bền vững scope/danh sách QR và link QR trên máy theo user + showroom.
Mở menu dùng cache ngay, không chờ API; scope được đồng bộ nền tối đa một lần mỗi
24 giờ. Link QR có TTL 7 ngày vì cấu hình từng showroom rất ít thay đổi: showroom
đơn được lưu ngay từ bootstrap, showroom nhiều chỉ gọi API ở lần chọn đầu hoặc
sau TTL rồi tiếp tục dùng qua các lần tắt/mở app. Sau khi quản lý lưu link, client
force-refresh đúng một lần để action/mã QR mới xuất hiện ngay. Đổi user, scope tổ
chức hoặc tập quyền không dùng lại cache của phiên quyền cũ. Nếu API tạm lỗi sau
TTL, client fallback mã đã lưu thay vì hiển thị QR rỗng.

## Quyền

- `QUICK_ACTIONS` là quyền gốc; từng action có một child feature riêng.
- FIFO, VietQR, Chăm sóc lại và Báo cáo bán hàng chỉ hiện khi cả child shortcut và feature
  nghiệp vụ gốc đều bật. Tắt shortcut không làm mất quyền vào màn hình từ nơi
  khác.
- `Chăm sóc lại` yêu cầu `QUICK_ACTION_FOLLOW_UP` và ít nhất một trong hai quyền
  mở màn hình hiện hữu: `SALES_REPORT` hoặc `ADMIN_SALES_REPORTS`.
- Bốn action QR chỉ hiện khi child feature bật và ít nhất một showroom trong
  scope có link tương ứng.
- `ADMIN_QUICK_ACTION_CODES` nằm dưới `ADMIN`. API cấu hình yêu cầu đồng thời
  feature này, chức danh Store/Area/Region Manager (kể cả alias
  `REGIONAL_MANAGER`) và showroom trong scope. `SUPER_ADMIN` luôn được phép.

## Dữ liệu và API

Mỗi cấu hình là một dòng `showroom + actionCode`, URL tối đa 2.048 ký tự và chỉ
nhận `http/https`; giá trị trống xóa dòng. Không kế thừa và không fallback sang
showroom khác.

- `GET /quick-actions?storeCode=`: showroom trong scope, action QR khả dụng và
  link của showroom đã chọn.
- `GET /admin/quick-action-links/stores`: showroom được quản lý.
- `GET /admin/quick-action-links?storeCode=`: bốn trường link.
- `PUT /admin/quick-action-links/:storeCode`: upsert/xóa cả bốn trường trong
  một transaction.

## Hành vi QR và cấu hình

Một showroom mở QR trực tiếp; nhiều showroom yêu cầu chọn trước. Link thiếu hoặc
lỗi không tạo QR rỗng. Modal chỉ hiển thị QR cho khách quét, không tự mở link.
Vùng mã luôn dùng nền trắng thuần và nét đen, kể cả khi ứng dụng ở dark mode, để
camera khách hàng đọc ổn định.

`Quản trị > Quản lý mã` có selector và bốn trường URL. Mobile, web và macOS dùng
camera scanner với `parsePhongVuSku: false`; Windows tập trung input để nhận máy
quét USB dạng keyboard-wedge, đồng thời vẫn cho nhập hoặc dán tay.

Log `AppLogger` chỉ ghi action code, showroom, số lượng, trạng thái, thời gian và
độ dài URL; không ghi URL đầy đủ.
