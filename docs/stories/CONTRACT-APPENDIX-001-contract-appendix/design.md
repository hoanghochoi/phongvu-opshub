# Design

- Backend module `contract-appendices` gọi `SalesReportErpService.lookupOrder`
  và adapter `ErpPpmProductService`; adapter PPM dùng `authorizedRequest` trên
  đúng token cache ERP hiện hữu, deduplicate toàn bộ SKU và chia batch 50. Tax
  lookup luôn live và không có memory/Redis tax cache.
- `POST /contract-appendices/preview` không ghi DB nhưng luôn refetch live thuế.
  `POST /contract-appendices` refetch lần nữa, kiểm tra fingerprint rồi ghi
  parent và items trong một nested transaction của Prisma.
- ERP normalization mang `uomName` vào order item; Contract Appendix dùng field
  này làm đơn vị ban đầu và không tự suy đoán một đơn vị mặc định.
- Parent/item lưu money bằng `BIGINT`, rate bằng basis points, nguồn thuế và
  snapshot các số đã tính. Không có PATCH/draft.
- Flutter dùng dedicated full page: desktop editor và preview cạnh nhau;
  mobile dùng item cards, preview bảng cuộn hai chiều. Lịch sử phân trang phía
  server.
- Rich clipboard ghi cùng lúc HTML đã escape và TSV fallback. Copy bị khóa khi
  editor dirty hoặc snapshot chưa được lưu.
