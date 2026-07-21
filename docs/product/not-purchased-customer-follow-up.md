# Chăm sóc lại

## Mục tiêu

Cho phép nhân viên bán hàng theo dõi và chăm sóc lại từng lượt báo cáo
`NOT_PURCHASED`. Mỗi báo cáo gốc tạo một hồ sơ riêng; không gộp khách theo số
điện thoại.

## Điều kiện hiển thị

- Trong 14 ngày đầu kể từ lần triển khai đầu tiên có thay đổi này trên từng môi
  trường, tạm hiển thị toàn bộ hồ sơ khách chưa mua trong đúng scope để nhân
  viên rà soát và bổ sung thông tin liên hệ.
- Workflow triển khai ghi mốc UTC
  `SALES_REPORT_FOLLOW_UP_CONTACT_GRACE_UNTIL` một lần và không gia hạn khi
  backend restart hoặc có lần triển khai tiếp theo. Nếu mốc thiếu/không hợp lệ,
  hệ thống dùng ngay bộ lọc chặt để tránh mở rộng dữ liệu ngoài chủ đích.
- Sau mốc trên, chỉ hiển thị hồ sơ có số điện thoại đúng `0` + 9 chữ số hoặc có
  ít nhất một kênh liên hệ chuẩn trong `customerContactChannels`: `PHONE`,
  `ZALO_PERSONAL`, `ZALO_OA`. Nội dung rác và marker `0zalo` cũ được migration
  chuyển sang dữ liệu chuẩn rồi xóa khỏi cột số điện thoại.
- Báo cáo chưa mua vẫn được lưu bình thường khi thiếu cả hai thông tin; hồ sơ
  chỉ bị ẩn khỏi màn hình này sau khi thời gian rà soát kết thúc.
- `ZALO_PERSONAL` và `ZALO_OA` là hai cờ liên hệ độc lập, có thể cùng được chọn;
  chúng cũng độc lập với câu trả lời hành vi sale về việc khách quét Zalo OA.
- Danh sách chính chỉ hiển thị hồ sơ `OPEN`; `PURCHASED_ELSEWHERE` và
  `NO_LONGER_INTERESTED` nằm trong mục `Đã ẩn`; hồ sơ `PURCHASED` không hiện lại.
- Tab `Lịch sử chăm sóc` nằm giữa `Cần chăm sóc` và `Đã ẩn`, vẫn dùng dạng card
  như danh sách chính. Tab này hiển thị mọi trạng thái có `followUpCount > 0`,
  sắp lần chăm sóc gần nhất trước; mở card để xem đầy đủ các lần chăm sóc.

## Phạm vi và phân công

- Nhân viên xem và cập nhật hồ sơ đang được phân công cho mình.
- Store/Area/Region Manager xem các hồ sơ trong showroom/node được gán và có thể
  chăm sóc thay. Super Admin xem toàn bộ hồ sơ, không phụ thuộc showroom/node
  được gán.
- Quản lý chỉ được phân công cho nhân viên bán hàng đang hoạt động trong cùng
  showroom.
- Sau khi phân công, người nhận mới là người phụ trách hồ sơ.
- Super Admin có thể lọc danh sách theo `Mã SR / Showroom`; mặc định là tất cả
  showroom trong phạm vi toàn hệ thống. Khi đổi SR, danh sách và phân trang tải
  lại theo `storeCode` đã chọn; các vai trò khác không thấy bộ lọc toàn hệ thống.

## Thứ tự và cảnh báo

- Hồ sơ chưa từng chăm sóc xếp trước; sau đó xếp từ lần chăm sóc cũ nhất.
- Số ngày được tính từ lần chăm sóc gần nhất, hoặc lần tiếp xúc đầu nếu chưa có
  lần chăm sóc: xanh 0-1 ngày, vàng 2-3 ngày, đỏ trên 3 ngày.

## Nhập dữ liệu lịch sử từ Excel

- Tài khoản có quyền quản lý báo cáo bán hàng mở `Nhập Excel` ngay trong màn
  hình Chăm sóc lại. Nhân viên bán hàng thông thường không thấy thao tác này.
- Hỗ trợ `.xlsx`/`.xls`, tối đa 5 MB và 1.000 dòng dữ liệu mỗi lần. File phải
  giữ các cột nguồn: Timestamp, Email Address, MSNV bán hàng, Họ & Tên Khách
  Hàng, SDT Khách Hàng, Ngành hàng, sản phẩm khách tìm, Chốt đơn thành công?,
  Lí/Lý do không mua, SR ID và Kênh liên lạc; cột trống dư được bỏ qua.
- Luồng bắt buộc xem trước rồi mới xác nhận. Kết quả tách rõ dòng hợp lệ, đã
  mua, trùng, không hợp lệ và chưa phân công; chỉ dòng chưa mua hợp lệ được
  nhập. File thay đổi sau lúc xem trước bị chặn bằng checksum.
- Phone được chuẩn hóa về `0` + 9 chữ số; `+84` và chuỗi 9 chữ số được quy đổi.
  Marker `0zalo` chỉ tạo kênh `ZALO_PERSONAL`, không lưu vào số điện thoại.
  Kênh liên lạc hỗ trợ `PHONE`, `ZALO_PERSONAL`, `ZALO_OA`.
- Ngành hàng được đối chiếu theo mã/tên Việt/tên Anh trong danh mục hiện hành;
  nếu tên lịch sử lệch cách ghi, backend tự ghép vào ngành hàng hiện hành gần
  nhất và ghi cảnh báo trong bản xem trước. Giá trị trống hoặc không đủ gần vẫn
  bị đánh dấu lỗi để tránh gán nhầm. SR phải tồn tại và nằm trong scope của
  người nhập; Super Admin được nhập cho mọi SR.
- Email nhân viên active đúng SR được gán làm owner/assignee. Nếu chưa khớp,
  hồ sơ vẫn được nhập ở trạng thái chưa phân công, đồng thời giữ Email Address
  và `sourceSalespersonCode` để quản lý xử lý sau.
- Báo cáo lịch sử dùng `entrySource=HISTORICAL_IMPORT`; bốn câu hỏi hành vi chưa
  có trong file được lưu `NOT_CAPTURED` và hiển thị `Không có dữ liệu lịch sử`,
  không giả lập câu trả lời của khách hoặc nhân viên.
- Mỗi dòng có fingerprint duy nhất. Nhập lại cùng dữ liệu chỉ tăng thống kê
  trùng, không ghi đè báo cáo hay lịch sử chăm sóc đã có. Batch audit chỉ lưu
  checksum, tên file, actor và số lượng; không lưu nguyên file hoặc payload PII.

## Đồng bộ BigQuery

- Job BigQuery báo cáo bán hàng chạy theo lịch hiện có lúc 07:00 giờ Việt Nam
  và đồng bộ thêm bảng lịch sử chăm sóc khi
  `SALES_REPORT_BIGQUERY_SYNC_ENABLED=true`; thao tác đồng bộ thủ công của quản
  lý báo cáo cũng bao gồm bảng này.
- Bảng mặc định là `opshub_sales_report_follow_up_history`, có thể đổi bằng
  `SALES_REPORT_BIGQUERY_FOLLOW_UP_TABLE_ID`. Mỗi hồ sơ khách hàng là một dòng;
  mỗi lần chăm sóc là một cột RECORD `follow_up_1`, `follow_up_2`, ... chứa kết
  quả, lý do, người và thời gian chăm sóc. Full refresh giữ đúng một dòng cho
  mỗi `follow_up_case_id` và tự mở rộng schema khi phát sinh số lần mới.

## Luồng modal

- Header ngữ cảnh khách hàng cố định; nội dung lịch sử và form cuộn bên dưới.
- Hiển thị thông tin liên hệ, ngành hàng, showroom, người/thời gian tiếp xúc đầu,
  lý do chưa mua lần đầu và mọi lần chăm sóc.
- Lần chăm sóc mới tự đánh số kế tiếp và có bốn kết quả loại trừ nhau:
  `PURCHASED`, `NOT_PURCHASED`, `PURCHASED_ELSEWHERE`,
  `NO_LONGER_INTERESTED`.
- `PURCHASED` dùng lại đầy đủ form báo cáo mua hàng. Báo cáo mua mới có
  `entrySource=COMEBACK`, liên kết hồ sơ gốc và không thay đổi báo cáo
  `NOT_PURCHASED` ban đầu.
- Người được ghi nhận doanh số là `order.creator.email` từ ERP. Không có email
  này thì chặn lưu bằng thông báo tiếng Việt; người thực hiện thao tác được lưu
  riêng để audit.
- Người đang được phân công có thể mở lại hồ sơ đã mua nơi khác/hết nhu cầu.

## Liên hệ

- Mobile: chạm số điện thoại để gọi; chỉ hiện hành động mở Zalo theo số khi báo
  cáo có kênh `ZALO_PERSONAL`. Kênh `ZALO_OA` hướng dẫn sale liên hệ qua OA của
  showroom.
- Desktop/web: sao chép số điện thoại hoặc dữ liệu Zalo cá nhân lịch sử. Nếu chỉ
  có cờ kênh liên hệ, hiển thị hướng dẫn theo kênh thay vì sao chép chuỗi rỗng.
- Không ghi số điện thoại/Zalo đầy đủ vào log; log chỉ ghi id, trạng thái và cờ
  có/không có thông tin liên hệ.
