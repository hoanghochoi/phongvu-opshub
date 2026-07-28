# MAP Vietin BigQuery export

OPS-36 bổ sung `order_tracking_status` vào raw row và payload schema v2. Giá trị
hợp lệ là `FOLLOWING` hoặc `UNFOLLOWED`; mapper schema v2 fail-closed với giá trị
khác. Event schema v1 không có field này được đọc tương thích là `FOLLOWING`, và
current view dùng cùng fallback cho raw row cũ/null. Đổi trạng thái theo dõi là
thay đổi canonical export snapshot nên tăng revision; cột BigQuery được tạo
nullable trước khi backend phát event v2 và được giữ lại khi rollback.

OpsHub giữ PostgreSQL là nguồn giao dịch MAP Vietin. BigQuery là read model phục vụ truy vấn báo cáo; worker nhận snapshot whitelist từ outbox sau commit và không được làm chậm thao tác nhập/đối soát MAP.

Current view chỉ trả revision mới nhất của mỗi `transaction_id`; tombstone từ xóa giao dịch được giữ ở raw table để đồng bộ xóa nhưng bị ẩn khỏi view. Dữ liệu nhạy cảm không nằm trong payload export.

MAP và eFAST có thể biểu diễn cùng trạng thái thành công hoặc nguồn provider
khác nhau. Outbox chuẩn hóa các biểu diễn tương đương sau khi giao dịch đã được
dedupe vào PostgreSQL; replay cùng giao dịch không tạo revision mới. Mã đơn,
statement identifier và các trường báo cáo thực sự thay đổi vẫn tạo event mới.

Revision được quyết định bằng canonical export snapshot, không phải bằng các
trường persistence thô. Vì vậy `transactionNumber` hoặc provider metadata có
thể thay đổi khi MAP/eFAST replay nhưng không tạo event nếu statement number và
toàn bộ dữ liệu báo cáo xuất ra vẫn giữ nguyên. Thay đổi canonical statement,
mã đơn, amount, store, status, paid time, income type hoặc tombstone vẫn tạo một
revision mới.
