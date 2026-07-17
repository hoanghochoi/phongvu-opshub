# Phụ lục hợp đồng

## Intent

Nhân viên nhập mã đơn ERP để tạo bảng hàng hóa phụ lục hợp đồng, lưu lịch sử
cá nhân 30 ngày và sao chép bảng có định dạng trực tiếp vào Microsoft Word.

## Source of Truth

- Chi tiết đơn luôn đi qua `SalesReportErpService.lookupOrder()` hiện hữu. Mọi
  tính năng ERP phải dùng chung tài khoản, login, token cache và cơ chế refresh
  đang có; không tạo luồng xác thực ERP song song.
- SKU, số lượng, tên gợi ý và `finalSellPrice` lấy từ item của đơn ERP.
  `finalSellPrice` là giá mỗi đơn vị đã gồm VAT và là nguồn giá duy nhất; không
  fallback sang `sellPrice`, `rowTotal` hay giá PPM.
- Thuế lấy từ PPM `POST /products`, field `taxOutAmount`, với terminal cố định
  `49180_PRICE_0001`. PPM không phải nguồn giá.
- VAT `0%` và hàng không chịu thuế được phân biệt bằng `taxCode/taxLabel`;
  mã KCT hợp lệ được giữ nguyên trên snapshot dù cùng có số tiền thuế bằng 0.
- Thuế ERP hợp lệ bị khóa. Khi PPM thiếu hoặc lỗi, user phải chọn tay một trong
  `0%`, `5%`, `8%`, `10%`; snapshot lưu cờ `MANUAL`.

## Money Contract

Mọi phép tính dùng số nguyên VND và basis points:

```text
grossUnit = finalSellPrice
netUnit = roundHalfUp(grossUnit * 10000 / (10000 + vatRateBps))
lineBeforeVat = netUnit * quantity
lineAfterVat = grossUnit * quantity
lineVat = lineAfterVat - lineBeforeVat
```

Footer luôn thỏa `Tổng cộng + Thuế GTGT = Tổng giá trị hợp đồng`. Tiền bằng
chữ được sinh phía server từ tổng đã VAT và kết thúc bằng `đồng chẵn.`.

## User Flow

1. User có feature `CONTRACT_APPENDIX` mở `/contract-appendix`.
2. Nhập mã đơn và bấm `Lấy thông tin` trên cùng một hàng.
3. App hiển thị SKU, số lượng và giá ERP ở trạng thái khóa; tên hàng và đơn vị
   tính được sửa. Thuế nhập tay chỉ xuất hiện ở dòng chưa có thuế ERP.
4. Editor và preview luôn xếp thành một cột để giữ đủ chiều rộng; desktop dùng
   bảng editor, mobile dùng item card. Preview dùng bảng 7 cột, cột cuối là
   `Thành tiền (VNĐ) - Chưa VAT`.
5. `Lưu phụ lục` buộc backend refetch thuế, so `quoteVersion`, tính lại và lưu
   snapshot bất biến. Nếu nguồn đổi, user phải xem lại preview.
6. `Sao chép bảng` chỉ dùng snapshot đã lưu, ghi HTML và plain-text TSV vào
   clipboard; không gọi API trong clipboard handler. HTML Word đặt Times New
   Roman 12pt trực tiếp trên từng ô, header, các cột định danh và cột tiền căn
   giữa, tên hàng căn trái. Preview desktop dùng bề rộng 960px để bảng thoáng
   hơn; `Bằng chữ` là đoạn riêng nằm ngoài bảng.

## History and Access

- Chỉ lưu phụ lục đã hoàn tất; không lưu draft.
- Lịch sử là cá nhân, chỉ creator đọc được. Bản của người khác và bản hết hạn
  cùng trả `404`.
- `expiresAt = createdAt + 30 * 24 giờ` theo UTC. Read path lọc hết hạn ngay cả
  khi cron chưa chạy; cron xóa vật lý mỗi giờ.
- Không lưu tên, điện thoại hoặc địa chỉ khách hàng.

## Operational Requirements

- Backend log start/success/failure, item/batch/missing/manual counts và
  duration; Flutter dùng `AppLogger` cho lookup, save, history và copy.
- Không log token, credential, raw ERP payload, tên hàng hoặc mã đơn thô.
- SKU test tích hợp chuẩn: `250902982` tại terminal cố định phải trả `8%`.
