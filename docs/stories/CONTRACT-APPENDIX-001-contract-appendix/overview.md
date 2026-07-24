# CONTRACT-APPENDIX-001 Phụ lục hợp đồng

## Intent

Tạo phụ lục hàng hóa từ đơn ERP nhanh, đúng giá/thuế, có thể paste vào Word và
mở lại trong 30 ngày mà không lưu dữ liệu khách hàng không cần thiết.

## Acceptance Criteria

- Order lookup tái sử dụng tài khoản/token và `SalesReportErpService` hiện hữu.
- Chỉ `finalSellPrice` được dùng làm giá đã VAT; SKU tra thuế PPM terminal
  `49180_PRICE_0001`.
- Preview và save đều tra live toàn bộ SKU duy nhất theo batch, không dùng tax
  cache memory/Redis; ERP login/token cache vẫn giữ nguyên.
- Đơn vị tính ban đầu lấy từ ERP `uomName`, không hard-code `Cái`.
- Công thức số nguyên reconcile tuyệt đối; tổng đã VAT có số tiền bằng chữ.
- Thiếu thuế không được mặc định; chỉ tiếp tục bằng lựa chọn tay có cờ.
- Save refetch nguồn, phát hiện thay đổi bằng `quoteVersion`, lưu snapshot cá
  nhân bất biến và hết hạn sau đúng 30 ngày.
- Windows Word paste giữ bảng 7 cột, border, header, summary và Unicode.

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
