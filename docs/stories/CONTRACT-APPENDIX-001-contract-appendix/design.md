# Design

- Backend module `contract-appendices` gọi `SalesReportErpService.lookupOrder`
  và adapter `ErpPpmProductService`; adapter PPM dùng `authorizedRequest` trên
  đúng token cache ERP hiện hữu, chia batch 50 và cache Redis 5 phút.
- `POST /contract-appendices/preview` không ghi DB. `POST
  /contract-appendices` force-refresh thuế, kiểm tra fingerprint rồi ghi parent
  và items trong một nested transaction của Prisma.
- Parent/item lưu money bằng `BIGINT`, rate bằng basis points, nguồn thuế và
  snapshot các số đã tính. Không có PATCH/draft.
- Flutter dùng dedicated full page: desktop editor và preview cạnh nhau;
  mobile dùng item cards, preview bảng cuộn hai chiều. Lịch sử phân trang phía
  server.
- Rich clipboard ghi cùng lúc HTML đã escape và TSV fallback. Copy bị khóa khi
  editor dirty hoặc snapshot chưa được lưu.
