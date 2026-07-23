# MAP Vietin BigQuery export

OpsHub giữ PostgreSQL là nguồn giao dịch MAP Vietin. BigQuery là read model phục vụ truy vấn báo cáo; worker nhận snapshot whitelist từ outbox sau commit và không được làm chậm thao tác nhập/đối soát MAP.

Current view chỉ trả revision mới nhất của mỗi `transaction_id`; tombstone từ xóa giao dịch được giữ ở raw table để đồng bộ xóa nhưng bị ẩn khỏi view. Dữ liệu nhạy cảm không nằm trong payload export.
