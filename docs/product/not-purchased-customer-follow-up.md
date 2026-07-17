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
- Sau mốc trên, chỉ hiển thị hồ sơ có ô số điện thoại đúng 10 chữ số hoặc marker
  `0zalo`. Zalo cá nhân riêng không thay thế điều kiện này; mọi nội dung khác
  trong ô số điện thoại không làm hồ sơ xuất hiện.
- Báo cáo chưa mua vẫn được lưu bình thường khi thiếu cả hai thông tin; hồ sơ
  chỉ bị ẩn khỏi màn hình này sau khi thời gian rà soát kết thúc.
- Zalo cá nhân là trường liên hệ độc lập với câu trả lời về Zalo OA.
- Danh sách chính chỉ hiển thị hồ sơ `OPEN`; `PURCHASED_ELSEWHERE` và
  `NO_LONGER_INTERESTED` nằm trong mục `Đã ẩn`; hồ sơ `PURCHASED` không hiện lại.

## Phạm vi và phân công

- Nhân viên xem và cập nhật hồ sơ đang được phân công cho mình.
- Store/Area/Region Manager xem các hồ sơ trong showroom/node được gán và có thể
  chăm sóc thay. Super Admin xem toàn bộ hồ sơ, không phụ thuộc showroom/node
  được gán.
- Quản lý chỉ được phân công cho nhân viên bán hàng đang hoạt động trong cùng
  showroom.
- Sau khi phân công, người nhận mới là người phụ trách hồ sơ.

## Thứ tự và cảnh báo

- Hồ sơ chưa từng chăm sóc xếp trước; sau đó xếp từ lần chăm sóc cũ nhất.
- Số ngày được tính từ lần chăm sóc gần nhất, hoặc lần tiếp xúc đầu nếu chưa có
  lần chăm sóc: xanh 0-1 ngày, vàng 2-3 ngày, đỏ trên 3 ngày.

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

- Mobile: chạm số điện thoại để chọn gọi hoặc mở Zalo theo số đó.
- Desktop/web: sao chép số điện thoại; nếu không có số thì sao chép Zalo cá nhân.
- Không ghi số điện thoại/Zalo đầy đủ vào log; log chỉ ghi id, trạng thái và cờ
  có/không có thông tin liên hệ.
