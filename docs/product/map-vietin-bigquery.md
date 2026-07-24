# MAP Vietin BigQuery export

OpsHub giữ PostgreSQL là nguồn giao dịch MAP Vietin. BigQuery là read model phục vụ truy vấn báo cáo; worker nhận snapshot whitelist từ outbox sau commit và không được làm chậm thao tác nhập/đối soát MAP.

Current view chỉ trả revision mới nhất của mỗi `transaction_id`; tombstone từ xóa giao dịch được giữ ở raw table để đồng bộ xóa nhưng bị ẩn khỏi view. Dữ liệu nhạy cảm không nằm trong payload export.

MAP và eFAST có thể biểu diễn cùng trạng thái thành công hoặc nguồn provider
khác nhau. Outbox chuẩn hóa các biểu diễn tương đương sau khi giao dịch đã được
dedupe vào PostgreSQL; replay cùng giao dịch không tạo revision mới. Mã đơn,
statement identifier và các trường báo cáo thực sự thay đổi vẫn tạo event mới.
