# Design

- Backend module `contract-appendices` gọi
  `SalesReportErpService.lookupContractAppendixOrder` và adapter
  `ErpPpmProductService`; lookup này thay `finalSellPrice` và `rowTotal` của
  capture bằng cặp giá shipment khớp duy nhất theo khóa ổn định, fail-closed
  khi thiếu/mơ hồ và không đổi contract `lookupOrder` của Sales Report. Adapter PPM dùng `authorizedRequest` trên
  đúng token cache ERP hiện hữu, deduplicate toàn bộ SKU và chia batch 50. Tax
  lookup luôn live và không có memory/Redis tax cache.
- `POST /contract-appendices/preview` không ghi DB nhưng luôn refetch live thuế.
  `POST /contract-appendices` refetch lần nữa, kiểm tra fingerprint rồi ghi
  parent và items trong một nested transaction của Prisma.
- ERP normalization mang `uomName` vào order item; Contract Appendix dùng field
  này làm đơn vị ban đầu và không tự suy đoán một đơn vị mặc định.
- Parent/item lưu money bằng `BIGINT`, rate bằng basis points, nguồn thuế,
  shipment row total và snapshot các số đã tính. Parent có source-order rows;
  grouped item giữ source-order provenance. Không có PATCH/draft.
- Preview/create nhận tối đa 10 mã đơn, lookup atomic và giữ thứ tự user nhập.
  Group chỉ khi SKU, gross unit, tax semantics và đơn vị giống nhau.
- Flutter dùng dedicated full page: desktop editor và preview cạnh nhau;
  mobile dùng item cards, preview bảng cuộn hai chiều. Lịch sử phân trang phía
  server.
- Rich clipboard ghi cùng lúc HTML đã escape và TSV fallback. Web ghi native
  `ClipboardItem` (`text/html` + `text/plain`) để Word nhận được bảng; native
  Windows tiếp tục dùng `super_clipboard`. Copy bị khóa khi editor dirty hoặc
  snapshot chưa được lưu.
- Preview Word dùng sáu cột `STT / Tên hàng hóa / ĐVT / SL / Đơn giá / Thành
  tiền`, không có SKU/Mã hàng. Tên hàng và ĐVT là dữ liệu ERP chỉ đọc; tên hàng
  tự wrap trong ô/card. Preview hiển thị cùng ba dòng tổng và tiền bằng chữ với
  clipboard.
