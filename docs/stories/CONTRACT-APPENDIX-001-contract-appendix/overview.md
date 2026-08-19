# CONTRACT-APPENDIX-001 Phụ lục hợp đồng

OPS-209 extends this story with shipment row-total accuracy and atomic
multi-order input.

## Intent

Tạo phụ lục hàng hóa từ đơn ERP nhanh, đúng giá/thuế, có thể paste vào Word và
mở lại trong 30 ngày mà không lưu dữ liệu khách hàng không cần thiết.

## Acceptance Criteria

- Order lookup tái sử dụng tài khoản/token và `SalesReportErpService` hiện hữu;
  Contract Appendix dùng đường lookup riêng để không đổi giá của Sales Report.
- `finalSellPrice` và `rowTotal` của cùng shipment line khớp duy nhất bằng khóa
  ổn định. `finalSellPrice` là giá đơn vị gross; `rowTotal` là `lineAfterVat`.
  Thiếu, mơ hồ hoặc một trong hai số không hợp lệ phải dừng, không fallback về
  capture/`sellPrice`/PPM; SKU tra thuế PPM terminal `49180_PRICE_0001`.
- Preview/create nhận `orderCodes[]` tối đa 10 mã và tối đa 200 source lines,
  lookup atomic; vẫn đọc request singleton `orderCode` cũ.
- Dòng chỉ gộp khi cùng SKU, giá gross, tax semantics và đơn vị; cộng quantity
  và rowTotal, giữ source provenance và thứ tự xuất hiện đầu tiên.
- Preview và save đều tra live toàn bộ SKU duy nhất theo batch, không dùng tax
  cache memory/Redis; ERP login/token cache vẫn giữ nguyên.
- Đơn vị tính ban đầu lấy từ ERP `uomName`, không hard-code `Cái`.
- Công thức số nguyên reconcile tuyệt đối với tổng shipment `rowTotal`; tổng đã
  VAT có số tiền bằng chữ.
- Thiếu thuế không được mặc định; chỉ tiếp tục bằng lựa chọn tay có cờ.
- Save refetch nguồn, phát hiện thay đổi bằng `quoteVersion`, lưu snapshot cá
  nhân bất biến và hết hạn sau đúng 30 ngày.
- Windows Word paste giữ bảng 7 cột `STT / Tên hàng hóa / Mã hàng / ĐVT / SL /
  Đơn giá / Thành tiền`, border, header, summary và Unicode; cột cuối dùng
  `lineAfterVat` với nhãn `Thành tiền (VNĐ) (đã bao gồm VAT)`.

## Affected Runtime Contract

Path contracts:

- `backend-nest/src/erp/erp-ppm-product.service.ts`
- `backend-nest/src/erp/erp.types.ts`
- `backend-nest/src/sales-reports/sales-report-erp.service.ts`
- `backend-nest/src/contract-appendices/**`
- `lib/features/contract_appendix/**`
- `test/contract_appendix_*_test.dart`

Affected verify command: `bash scripts/validate-contract-appendix.sh`.

Protected consumers: ERP authorized request/token refresh, Sales Report order
lookup, Contract Appendix preview/save/quote conflict/history/access, mobile and
desktop layout, and Word HTML/TSV clipboard.
