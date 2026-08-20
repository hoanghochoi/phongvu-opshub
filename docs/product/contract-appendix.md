# Phụ lục hợp đồng

## Intent

Nhân viên tập hợp một hoặc nhiều mã đơn ERP để tạo bảng hàng hóa phụ lục hợp
đồng, lưu lịch sử cá nhân 30 ngày và sao chép bảng có định dạng trực tiếp vào
Microsoft Word.

## Source of Truth

- Chi tiết đơn luôn đi qua `SalesReportErpService.lookupOrder()` hiện hữu. Mọi
  tính năng ERP phải dùng chung tài khoản, login, token cache và cơ chế refresh
  đang có; không tạo luồng xác thực ERP song song.
- SKU, số lượng, tên gợi ý và `uomName` lấy từ `orderCaptureLineItems` của từng
  đơn ERP. `finalSellPrice` và `rowTotal` phải lấy từ cùng item shipment khớp
  bằng khóa ổn định. `finalSellPrice` là giá mỗi đơn vị đã gồm VAT; `rowTotal`
  là tổng dòng đã gồm VAT và là nguồn duy nhất cho `lineAfterVat`. Khi shipment
  thiếu, không khớp, khớp mơ hồ hoặc một trong hai số không hợp lệ, dừng toàn bộ
  batch; không fallback sang giá capture, `sellPrice`, capture `rowTotal` hay
  giá PPM.
- Thuế lấy từ PPM `POST /products`, field `taxOutAmount`, với terminal cố định
  `49180_PRICE_0001`. Mỗi preview và save đều deduplicate toàn bộ SKU của các đơn,
  gọi PPM live theo batch tối đa 50 SKU và không đọc/ghi memory hoặc Redis tax
  cache. PPM không phải nguồn giá; token xác thực ERP dùng chung vẫn được cache.
- VAT `0%` và hàng không chịu thuế được phân biệt bằng `taxCode/taxLabel`;
  mã KCT hợp lệ được giữ nguyên trên snapshot dù cùng có số tiền thuế bằng 0.
- Thuế ERP hợp lệ bị khóa. Khi PPM thiếu hoặc lỗi, user phải chọn tay một trong
  `0%`, `5%`, `8%`, `10%`; snapshot lưu cờ `MANUAL`.

## Money Contract

Mọi phép tính dùng số nguyên VND và basis points:

```text
grossUnit = shipment.finalSellPrice
netUnit = roundHalfUp(grossUnit * 10000 / (10000 + vatRateBps))
lineBeforeVat = netUnit * quantity
lineAfterVat = shipment.rowTotal
lineVat = lineAfterVat - lineBeforeVat
```

Khi các dòng tương thích được gộp, `quantity` và `rowTotal` được cộng; chỉ gộp
cùng SKU, gross unit, tax semantics và đơn vị ERP. Footer luôn thỏa `Tổng cộng +
Thuế GTGT = Tổng giá trị hợp đồng`; `totalAfterVat` và tiền bằng chữ được sinh
từ tổng shipment `rowTotal` và kết thúc bằng `đồng chẵn.`.

## User Flow

1. User có feature `CONTRACT_APPENDIX` mở `/contract-appendix`.
2. Nhập mã đơn, bấm `Thêm đơn` để tạo danh sách tối đa 10 đơn, rồi bấm
   `Lấy thông tin (N đơn)`. Enter trong ô nhập chỉ thêm đơn, không gọi ERP.
   Mã rỗng, trùng hoặc vượt giới hạn bị chặn trước khi gọi API.
3. Trong lúc lấy dữ liệu, danh sách bị khóa. Một đơn lỗi làm toàn batch thất bại
   và thông báo mã đơn cần sửa; không hiển thị bảng một phần. Sau khi thành công,
   tập đơn bị khóa; `Chọn lại đơn hàng` phải xác nhận trước khi reset preview.
4. App hiển thị SKU, số lượng và giá ERP ở trạng thái khóa; đơn vị tính khởi tạo
   từ `uomName`; tên hàng và đơn vị tính hiển thị dạng chỉ đọc, khóa theo dữ liệu
   ERP. Tên hàng tự xuống dòng khi thiếu chiều rộng. Không mặc định cứng đơn vị
   tính khi ERP thiếu dữ liệu. Thuế nhập tay chỉ xuất hiện ở dòng chưa có thuế ERP.
5. Editor và preview luôn xếp thành một cột để giữ đủ chiều rộng; desktop dùng
   bảng Word preview, mobile dùng item card. Preview Word dùng đúng sáu cột
   `STT / Tên hàng hóa / ĐVT / SL / Đơn giá / Thành tiền`; không hiển thị SKU/Mã
   hàng. Cột cuối là `Thành tiền (VNĐ) (đã bao gồm VAT)` và hiển thị
   `lineAfterVat`. Preview phải có cùng ba dòng tổng và `Bằng chữ` như payload
   clipboard.
6. Preview và `Lưu phụ lục` đều buộc backend refetch live thuế, so
   `quoteVersion`, tính lại và lưu
   snapshot bất biến. Nếu nguồn đổi, user phải xem lại preview.
7. `Sao chép bảng` chỉ dùng snapshot đã lưu, ghi HTML và plain-text TSV vào
   clipboard; không gọi API trong clipboard handler. HTML Word đặt Times New
   Roman 12pt trực tiếp trên từng text run, header, các cột định danh và cột
   tiền căn giữa, tên hàng căn trái. Web dùng native `navigator.clipboard.write`
   với `ClipboardItem` gồm `text/html` và `text/plain`; Windows/native tiếp tục
   dùng `super_clipboard`. Payload là HTML fragment thuần, không lồng thêm
   `html/body` hoặc fragment marker. Sáu cột được khóa theo tỷ lệ
   `6/48/8/8/15/15`; hàng đầu vẫn là `tbody/tr/td`, không dùng `thead`/`th`,
   nên không bị đánh dấu lặp tiêu đề khi qua trang. Preview desktop có ba dòng
   tổng và `Bằng chữ` trong cùng bề mặt Word preview.

## History and Access

- Chỉ lưu phụ lục đã hoàn tất; không lưu draft. Snapshot lưu danh sách source
  orders và provenance của dòng gộp nhưng không lưu PII khách hàng.
- Lịch sử là cá nhân, chỉ creator đọc được. Bản của người khác và bản hết hạn
  cùng trả `404`.
- `expiresAt = createdAt + 30 * 24 giờ` theo UTC. Read path lọc hết hạn ngay cả
  khi cron chưa chạy; cron xóa vật lý mỗi giờ.
- Không lưu tên, điện thoại hoặc địa chỉ khách hàng.

## Operational Requirements

- Backend log start/success/failure, order/source/grouped item/batch/missing/manual
  counts và duration; Flutter dùng `AppLogger` cho add/remove/validation, batch
  lookup, reset, save, history và copy.
- Không log token, credential, raw ERP payload, tên hàng, PII hoặc mã đơn thô;
  lỗi UI được phép nêu mã đơn đang nhập cho user sửa.
- SKU test tích hợp chuẩn: `220909037` tại terminal cố định phải trả `0%` và
  `250902982` phải trả `8%`.
