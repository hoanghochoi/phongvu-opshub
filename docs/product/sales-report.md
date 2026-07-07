# Báo cáo bán hàng Contract

## Intent

Sale ghi nhận hành vi tư vấn và kết quả mua/chưa mua ngay trong OpsHub, thay
cho Google Form, đồng thời lưu dữ liệu đủ chuẩn để dashboard dùng lại.

## Current Shape

- Tab `Vận hành` hiển thị trực tiếp ô `Báo cáo bán hàng` dẫn tới
  `/sales-reports` khi user có feature `SALES_REPORT`; không còn màn trung gian
  `/reports`. User chỉ có `ADMIN_SALES_REPORTS` truy cập danh sách qua menu
  `Quản trị`. `Trang chủ` không còn là catalog tác vụ; thay vào đó
  nó hiển thị dashboard tổng quan theo scope lấy dữ liệu từ fact tables riêng
  của Home Summary. Dashboard tách hai khu vực dùng chung bộ chọn ngày và
  scope; khi mở `Trang chủ`, khoảng ngày mặc định là hôm nay và user đổi
  thủ công nếu cần xem ngày/khoảng khác. Khu vực `Bán hàng` chia thành nhóm
  `Doanh số` và `Hành vi then chốt`. Nhóm `Doanh số` hiển thị doanh số tổng
  từ cache đơn hàng sau khi loại đơn 0 VND, đơn hủy/trả toàn bộ và trừ giá trị
  trả một phần, số đơn bán, trung bình đơn hàng, doanh số hoàn thành, pending và
  `Tỉ lệ chuyển đổi = tổng số đơn / tổng số báo cáo`. Nhóm
  `Hành vi then chốt` hiển thị số khách chưa mua, số đơn chưa báo cáo,
  `Tỉ lệ báo cáo = số đơn đã báo cáo / tổng số đơn`, cùng các tỉ lệ
  `Có`/tổng báo cáo cho tư vấn 3 giải pháp, trải nghiệm, Zalo OA và tải App;
  không còn card `Tổng số báo cáo hợp lệ` riêng.
- Quyền hiển thị hai khu vực dashboard là hai tính năng riêng trong cây tổ
  chức: `Dashboard - Bán hàng` và `Dashboard - Tài chính`. Super Admin bật/tắt
  từng tính năng tại node; backend và app cùng ẩn khu vực không được cấp.
- Các vị trí SA, Kỹ thuật, Kho và Thu ngân luôn mặc định ở `Phạm vi cá nhân`,
  đồng thời được chọn từng showroom gắn với node được phân công để theo dõi
  tiến độ showroom. Các vị trí này không được chọn vùng, miền hoặc toàn hệ
  thống. Vị trí quản lý tiếp tục dùng phạm vi node được gán; Super Admin mặc
  định xem toàn hệ thống và có thể chọn từng node active có showroom bên dưới
  như Miền, Vùng hoặc Showroom.
- Màn hình `Báo cáo bán hàng` là cockpit đơn hàng theo khoảng ngày: cột trái là đơn chưa báo
  cáo, cột phải là đơn đã báo cáo. Phần card, nút thao tác và filter giữ cố
  định trong viewport; chỉ vùng danh sách của từng cột được cuộn độc lập. Mỗi
  cột hiển thị 20 đơn/trang và có bộ chuyển trang riêng dạng compact chỉ gồm
  hai mũi tên; số lượng ở header là total đếm từ DB
  theo scope hiện tại. Card đơn chỉ hiển thị mã SR và tên nhân viên bán hàng;
  không lặp tên pháp nhân hoặc chuỗi `Địa điểm kinh doanh` dài từ ERP. User thường chỉ thấy dữ liệu của mình theo email từ
  `data.orders.creator.email`, fallback về consultant/seller/source-user
  snapshot nếu ERP không trả creator. User có vị trí quản lý như
  `STORE_MANAGER`, hoặc có `ADMIN_SALES_REPORTS`, xem trong phạm vi node tổ chức
  được gán, gồm các showroom/node con; Super Admin xem toàn bộ cache/report
  trong DB.
- Cockpit dùng daterange chung `Ngày` cùng `SR`/`Nhân viên`/`Tải lại` và giữ hai
  thao tác nghiệp vụ nằm ngang nhau: `Báo cáo mua thủ công` mở form mua hàng để
  sale tự nhập/quét mã đơn, còn `Báo cáo chưa mua` mở form khách chưa mua; không
  lặp lại nút xuất file hay lối vào danh sách. Khi mở cockpit, bộ lọc `Ngày` mặc
  định chọn ngày hiện tại và request đầu tiên gửi cùng ngày bắt đầu/kết thúc,
  đồng bộ với Trang chủ. Bộ lọc `SR`/`Nhân viên` chỉ hiện với scope quản lý,
  lấy option từ cache/report trong phạm vi user được phép xem.
- Backend tự đồng bộ danh sách đơn từ staff-bff ERP mỗi 3 phút và khi service
  khởi động, map `creator.email` sang user nội bộ cùng showroom/node tổ chức
  được gán, rồi upsert snapshot rút gọn vào bảng cache riêng. Mapping này diễn
  ra ngay trong sync nền, không phụ thuộc sale bấm kiểm tra đơn; lần sync thiếu
  dữ liệu cũng không được xóa mapping user/showroom đã lưu. Nếu cache cũ đã có
  user nhưng thiếu showroom/node, lần sync sau sẽ bổ sung lại showroom/node từ
  user nội bộ rồi phát sự kiện realtime. Flutter không kích hoạt ERP sync;
  client đọc dữ liệu từ cache DB khi mở màn hình hoặc bấm `Tải lại`, và tự
  refresh qua WebSocket khi backend báo có đơn mới hoặc mapping cache vừa được
  bổ sung trong scope liên quan.
- Khi sale bấm một đơn chưa báo cáo, app mở form báo cáo mua hàng trong dialog,
  tự kiểm tra lại mã đơn qua luồng `check-order` hiện tại rồi fill tên khách,
  nhu cầu, loại khách, ngành hàng và thông tin đơn cần thiết.
- Nếu sale dùng `Báo cáo mua thủ công` và nhập trùng `orderCode` đang nằm trong
  cache cockpit hiện tại, backend vẫn match theo mã đơn để chuyển đơn đó sang đã
  báo cáo, không phụ thuộc metadata ngày/showroom của report thủ công.
- Đơn ERP có `grandTotal <= 0` là đơn vận hành nội bộ, không cần sale báo cáo.
  Backend gắn exclusion bền vững cho cache/report cùng mã đơn, cockpit không
  trả các đơn này ở cột chưa báo cáo hoặc đã báo cáo, và các KPI báo cáo/doanh
  số không tính chúng.
- Menu `Quản trị` hiển thị `Danh sách báo cáo bán hàng` khi user có
  `ADMIN_SALES_REPORTS`; đây là nơi duy nhất lọc danh sách và xuất file.
- Màn hình danh sách báo cáo bán hàng của admin lọc danh sách và CSV theo loại
  báo cáo và khoảng `Từ ngày` / `Đến ngày` dựa trên thời điểm gửi báo cáo
  (`submittedAt`). Khi mở màn hình, bộ lọc ngày mặc định là ngày hiện tại giống
  Trang chủ/cockpit. Người dùng chọn `Chọn khoảng ngày` để chọn cả hai mốc trong
  một range picker rồi áp dụng một lần; nếu chủ động chọn `Tất cả ngày`, app vẫn
  mặc định truy vấn/xuất 30 ngày gần nhất và hiện dòng nhắc nhỏ để tránh hiểu
  nhầm.
  Admin xuất được 3 file tiếng Việt: `HVTC` là mỗi dòng một báo cáo mua/chưa
  mua; `Doanh số` là một dòng tổng hợp doanh thu, nhu cầu trả góp, trả góp
  thành công và số lượng theo type ngành hàng;
  `Trả góp` chỉ lấy báo cáo có `installmentNeed = true`.
- `Mua hàng` bắt buộc nhập hoặc quét QR/barcode `Mã đơn hàng` và bấm
  `Kiểm tra đơn hàng` trước khi mở phần form còn lại. Sau khi đã kiểm tra, sale
  có nút `Kiểm tra đơn khác` để nhập/quét lại đơn mới. Backend kiểm tra ERP
  thật qua server, rồi submit vẫn re-check ERP trước khi lưu.
- Nếu ERP trả `confirmationStatus` hoặc `fulfillmentStatus` là `cancelled`
  không phân biệt hoa/thường, app báo `Đơn đã bị hủy.` và không load thông tin
  đơn hàng về form. Backend đồng thời persist trạng thái loại trừ bền vững cho
  `orderCode` đó trong cache ERP và đánh dấu mọi report mua hàng cùng mã đơn là
  không còn hợp lệ để các flow sau fail-closed: cockpit không trả lại ở cột
  chưa/đã báo cáo, admin list/export không tính tiếp, và các lần
  `Kiểm tra đơn hàng` hoặc submit sau đó bị chặn ngay cả khi chưa gọi lại ERP.
- Mỗi lần sale kiểm tra đơn và mỗi lần submit, backend lấy order detail cùng
  return request rồi lưu trạng thái chuẩn `PENDING`, `COMPLETED`,
  `COMPLETED_PARTIAL_RETURN`, `CANCELLED` hoặc `RETURNED_FULL`. Đơn pending vẫn
  được báo cáo nhưng chưa cộng doanh số; đơn trả toàn bộ bị chặn bằng thông báo
  tiếng Việt; đơn trả một phần giữ report và trừ
  `returnedQuantity × unitAfterTaxPrice` của request đã hoàn tất.
- Job danh sách đơn ERP chạy mỗi 1 phút và khi service khởi động, mặc định lấy
  100 đơn/ngày gần nhất (có thể cấu hình tối đa 200). List sync chỉ cập nhật
  snapshot nhanh; đơn `PENDING` từ list không được tự coi là đã xác minh trạng
  thái chi tiết.
- Job trạng thái chạy mỗi 20 phút, mặc định tối đa 80 đơn/lượt với concurrency
  2 và Redis lease. Job rà cả đơn `PENDING` trong cache chưa báo cáo lẫn đơn
  `Mua hàng` đã báo cáo, ưu tiên pending, vẫn dành quota xoay vòng cho đơn hoàn
  thành 30 ngày gần nhất để bắt hoàn trả muộn. Để không gây tải quá nhiều lên
  ERP, job có backoff theo failure count, giới hạn số đơn mỗi showroom/lượt và
  chỉ re-check pending sau khoảng cấu hình mặc định 20 phút; lỗi một đơn chỉ
  tăng failure count và thử lại ở lượt sau.
- Doanh số tổng trên dashboard lấy `grandTotal` từ cache đơn hàng theo
  ngày/scope, bỏ đơn 0 VND, đơn hủy/trả toàn bộ và trừ
  `returnedAfterTaxAmount` khi có trả một phần. Doanh số hoàn thành chỉ cộng báo
  cáo mua hàng có trạng thái ERP hoàn thành, cũng trừ `returnedAfterTaxAmount`
  khi có trả một phần. Riêng tiến độ chỉ tiêu dùng giá trị trước VAT theo công thức
  `round(max(grandTotal - returnedAfterTaxAmount, 0) / 1.08)`. Home hiển thị
  hai card tiến độ: `Tổng quan cá nhân` cho user/SA đang chọn và
  `Tổng quan Miền/Vùng/Cửa hàng` cho toàn bộ scope quản lý hiện tại. Store
  manager/tài khoản quản lý theo node chỉ được chọn SA thuộc scope đang xem để
  xem card cá nhân; nếu danh sách SA lớn hơn 10, picker có ô tìm kiếm theo tên,
  email hoặc mã nhân viên tư vấn. Menu `Quản trị` có `Quản lý doanh số` theo
  feature `ADMIN_SALES_TARGETS`; chỉ tiêu lưu theo SR/tháng ở giá trị trước VAT.
- ERP/Listing chỉ được tự điền ngành hàng khi map được về nhóm ngành OpsHub:
  chỉ lấy `result.products[].categories[]` có `level = 1` và dùng đúng `code`
  khớp `Cat group ID` trong `data/categories.csv`. Không dùng category level
  2/3, `productGroup`, `productType` hoặc tên sản phẩm để suy đoán ngành hàng;
  nếu Listing không có code level 1 thì sale phải chọn tay. Một báo cáo có thể
  chọn nhiều ngành hàng vì một đơn/khách có thể có
  nhiều nhu cầu; ngành đầu tiên được lưu làm ngành chính để filter/list cũ còn
  tương thích, toàn bộ ngành được lưu trong bảng selection và xuất CSV. Nếu
  không map được ngành hàng về nhóm ngành OpsHub thì sale bắt buộc chọn trước
  khi gửi báo cáo.
  Tên nhóm gốc ngắn như `PC` chỉ được match khi ERP/Listing trả đúng giá trị
  đó, không được match substring trong tên sản phẩm/dịch vụ như `... PC miễn
  phí`.
- Nhu cầu khách hàng và các câu hỏi hành vi tư vấn/trải nghiệm/Zalo/App đều là
  trường bắt buộc. `Tên khách hàng` là trường bắt buộc trên cả 2 báo cáo; với
  báo cáo mua hàng app tự điền nếu ERP trả về tên khách, sale vẫn có thể nhập
  khi ERP không có dữ liệu. Các câu hỏi hành vi mặc định là chưa chọn, không tự
  mặc định `Có`.
- Các lựa chọn dạng danh sách trên form báo cáo hiển thị bằng checkbox, không
  dùng dropdown. Những nhóm chỉ được chọn một đáp án vẫn dùng checkbox theo kiểu
  chọn độc quyền để nhân viên thao tác nhất quán.
- Loại khách hàng gồm `Doanh nghiệp`, `Cá nhân`; `Học sinh - Sinh viên` là
  checkbox con của `Cá nhân`. Khi tick `Học sinh - Sinh viên`, app tự tick
  `Cá nhân`; khi chọn `Doanh nghiệp`, app khóa và bỏ chọn `Cá nhân` /
  `Học sinh - Sinh viên`. Với báo cáo mua hàng, app tự fill `Doanh nghiệp` khi
  ERP trả `billingInfo.customerType = BUSINESS` hoặc
  `billingInfo.taxCode` có giá trị; nếu cả hai không thể hiện doanh nghiệp thì
  xem là `Cá nhân`.
  Với báo cáo chưa mua, sale chọn loại khách thủ công. DB lưu bằng
  `customerType` và flag riêng `customerIsStudent`.
- `CTKM áp dụng` là nhóm checkbox gồm `Đổi điểm thi`,
  `Học sinh - Sinh viên`, và `CTKM khác`.
- Cả `Mua hàng` và `Chưa mua hàng` có tick `Có nhu cầu trả góp`. Khi tick, sale
  chọn một hoặc nhiều đối tác trong danh sách cố định: `VNPAY - POS`,
  `PAYOO - POS`, `HomeCredit - CTTC`, `Shinhan - CTTC`, `HDSaison - CTTC`,
  `AEON Finance - CTTC`, `Mirae Asset`, `MPOS`; ghi nhận hồ sơ có được duyệt hay
  không, số tiền vay nếu có, và chọn `Lý do không trả góp`. Lý do này dùng cho
  cả 2 báo cáo vì khách có thể được duyệt nhưng không trả góp, hoặc không được
  duyệt nhưng vẫn mua bằng phương thức khác. Danh sách lý do gồm:
  `Khách chốt trả góp bình thường (Không có lý do)`,
  `Rớt hồ sơ: Tín dụng xấu (Nợ cũ, CIC...)`,
  `Rớt hồ sơ: Lỗi thẩm định/Thông tin`,
  `Khách từ chối: Lãi suất/Phí trả góp cao`,
  `Khách từ chối: Không đủ điều kiện giấy tờ/thẻ`,
  `Khách từ chối: Giá cao/So sánh đối thủ (TGDĐ, FPT, CPS...)`,
  `Khách từ chối: Chỉ tham khảo/Hẹn quay lại`.
- Mọi số tiền hiển thị/nhập trong UI sales-report dùng dấu phân cách hàng ngàn
  theo chuẩn `vi_VN`, ví dụ `5.000.000 VND`; payload gửi backend vẫn là số
  nguyên không có dấu phân cách.
- Riêng các KPI/card tổng quan có chiều ngang hẹp được phép rút gọn số tiền dài
  bằng hậu tố `M`/`B`, ví dụ `179,4M VND` hoặc `1,3B VND`, để không phá layout;
  màn chi tiết, form nhập và file export vẫn dùng định dạng đầy đủ.
- Khi lấy đơn hàng từ ERP, backend lưu loại khách hàng, phương thức thanh toán,
  snapshot đơn hàng đã sanitize, và từng sản phẩm trong bảng
  `SalesReportOrderItem`. Với từng sản phẩm, backend đọc `categories` trong
  payload Listing, ưu tiên level cao nhất để map `Type` trong
  `data/categories.csv`, rồi lưu `categoryType` để file Doanh số tính laptop,
  PC, PC ráp, Apple, màn hình, máy in, phụ kiện và dịch vụ bảo hiểm.
- File `HVTC` xuất một dòng cho mỗi báo cáo với các cột tiếng Việt: ngày báo
  cáo, email người báo cáo, mã nhân viên tư vấn ERP, tên/số điện thoại/nhu cầu
  khách hàng, các câu trả lời hành vi, loại báo cáo, lý do chưa mua và showroom.
- File `Doanh số` xuất một dòng tổng hợp theo bộ lọc hiện tại: số đơn hàng duy
  nhất, doanh thu doanh nghiệp/cá nhân, tổng số báo cáo có tick
  `Có nhu cầu trả góp`, số đơn trả góp thành công theo payment method ERP,
  số lượng laptop,
  PC, PC ráp, Apple chỉ tính Macbook/iPhone/iPad, màn hình, máy in, phụ kiện,
  dịch vụ bảo hiểm; các lý do khách không trả góp nằm ở cột cuối cùng.
- File `Trả góp` xuất một dòng cho mỗi báo cáo có nhu cầu trả góp, gồm:
  `Ngày báo cáo`, `Email người báo cáo`, `Số tiền vay trả góp`,
  `Đối tác trả góp`, `Kết quả duyệt hồ sơ`, `Loại báo cáo`,
  `Phương thức thanh toán cuối cùng`, `Lý do không trả góp`.
  `Phương thức thanh toán cuối cùng` đọc từ `erpPaymentMethods`: có payment
  method installment thì ghi `Trả góp`, không có thì ghi `Trả thẳng`.
- Giá trị trong CSV không bọc dấu nháy kép; dấu phẩy trong nội dung được đổi
  thành dấu chấm phẩy và xuống dòng được đổi thành khoảng trắng để không vỡ cột.
- `orderCode` là unique trên bảng `SalesReport`; một đơn mua hàng chỉ được báo
  cáo một lần.
- Không có field nhập `MSNV`; backend lấy user, email, tên, mã nhân viên suy ra,
  showroom và organization node từ token/user hiện tại.
- `ADMIN_SALES_REPORTS` được gán bằng feature theo node tổ chức. Super Admin có
  quyền toàn app theo feature resolver hiện tại.
- OpsHub đồng bộ dữ liệu `Báo cáo bán hàng` sang BigQuery để Looker Studio đọc
  trực tiếp từ BigQuery thay vì gọi runtime API. Sync được bật bằng
  `SALES_REPORT_BIGQUERY_SYNC_ENABLED=true`, dùng service-account JSON nằm ngoài
  git, full-refresh bốn bảng: report fact, revenue-by-store fact, order item
  fact và payment fact. Bảng doanh số BigQuery chỉ sync từng dòng theo cửa
  hàng/showroom, không sync một dòng tổng toàn hệ thống. Các bảng giữ label
  tiếng Việt tương ứng với export admin hiện tại, đồng thời giữ code gốc để
  lọc/đối soát. Dataset BigQuery phải tồn tại sẵn và service
  account cần quyền chạy load job/tạo hoặc replace bảng trong dataset đó. Khi
  bật sync, backend chạy lịch cố định 07:00 hằng ngày theo giờ Việt Nam (UTC+7).
  Admin có `ADMIN_SALES_REPORTS` có thể gọi
  `POST /api/sales-reports/admin/bigquery-sync` để chạy sync thủ công.

## Data Contract

- `SalesReport` lưu report type, tên/số điện thoại/nhu cầu khách hàng, hành vi
  tư vấn/trải nghiệm/Zalo/App, lý do chưa mua, loại khách hàng, cờ học sinh -
  sinh viên, CTKM áp dụng, category
  snapshot chính, các ngành hàng đã chọn, reporter snapshot, showroom/org
  snapshot, trạng thái/tổng tiền/phương thức thanh toán đơn ERP, nhu cầu trả
  góp, hồ sơ duyệt/chưa duyệt, số tiền vay, lý do không trả góp, đối tác trả
  góp và sanitized ERP snapshot.
- `SalesReportCategorySelection` lưu toàn bộ ngành hàng được chọn theo từng
  báo cáo, gồm snapshot code/tên gốc/tên Việt.
- `SalesReportOrderItem` lưu từng sản phẩm trong đơn hàng thành từng row riêng,
  gồm SKU, seller SKU, tên sản phẩm, thương hiệu, nhóm hàng, số lượng, giá bán,
  giá sau giảm, thành tiền dòng, `categoryType` map từ `data/categories.csv` và
  raw snapshot đã sanitize.
- `SalesReportPayment` lưu phương thức thanh toán, số tiền, thời điểm thanh
  toán và mã giao dịch khi ERP trả về.
- `SalesReportErpOrderCache` lưu snapshot rút gọn của đơn ERP trong ngày để
  cockpit tách đơn chưa/đã báo cáo mà không phụ thuộc sale nhớ tự mở form. Dữ
  liệu gồm mã đơn, ngày tạo, trạng thái, showroom/node, mã SR ưu tiên tách từ
  `data.orders.createdFromSiteDisplayName` dạng `[CP01] ...` hoặc
  `[CH1001] ...`,
  `creator.email` từ `data.orders.creator.email`, người tư vấn/người bán nếu
  ERP trả về, tổng tiền, phương thức thanh toán, metadata lần sync nền và
  snapshot đã sanitize. Nếu ERP xác nhận order hủy, trả toàn bộ, hoặc có
  `grandTotal <= 0`, cache row được gắn `excludedAt`/`exclusionReason`
  tương ứng (`ERP_ORDER_CANCELLED`, `ERP_ORDER_RETURNED_FULL`,
  `ERP_ORDER_ZERO_VALUE_INTERNAL`); mọi report mua hàng cùng `orderCode` cũng
  được gắn `erpExcludedAt`/`erpExclusionReason` để loại khỏi các query báo cáo
  phía sau mà không cần suy luận lại từ ERP theo từng màn.
  API cockpit đếm total chưa báo cáo trực tiếp trên cache DB, loại trừ các
  `orderCode` đã có báo cáo mua hàng hoặc được match từ report thủ công trong
  cache cockpit hiện tại, cùng các row đã bị exclude bền vững, rồi trả từng
  trang 20 đơn cho client. Backend publish sự kiện
  `SALES_REPORT_ORDERS_UPDATED` qua Redis/WebSocket sau sync khi có đơn mới
  hoặc cache cũ vừa được backfill user/showroom/node; payload chỉ chứa ngày,
  số lượng, user/SR liên quan để client tự lọc và gọi lại API scoped, không đẩy
  chi tiết đơn hàng qua websocket.
- `SalesReportCategoryGroup` đồng bộ từ `data/categories.csv`, dùng `Cat group
  ID` làm code, `Cat group name` làm tên gốc và `catGroupNameVi` làm nhãn tiếng
  Việt.
- Snapshot report lưu cả code, tên gốc và tên Việt để dữ liệu lịch sử không bị
  lệch nếu CSV đổi sau này.
- BigQuery sync tạo bốn bảng theo table prefix mặc định:
  `opshub_sales_report_reports`,
  `opshub_sales_report_revenue_by_store`, `opshub_sales_report_items` và
  `opshub_sales_report_payments`. Có thể override bằng
  `SALES_REPORT_BIGQUERY_REPORT_TABLE_ID`,
  `SALES_REPORT_BIGQUERY_REVENUE_TABLE_ID`,
  `SALES_REPORT_BIGQUERY_ITEM_TABLE_ID` và
  `SALES_REPORT_BIGQUERY_PAYMENT_TABLE_ID`.

## Expected Proof

- Backend: Prisma validate/generate, Nest build, tests cho category sync,
  duplicate `orderCode`, purchased re-check ERP, not-purchased no ERP call,
  scheduled ERP cache sync, durable canceled-order exclusion trên cache/report
  rows, order cockpit cache-only list, feature guard, export CSV và BigQuery
  sync mapping.
- Flutter: Home/Report hub entry theo feature, route guard, order check before
  submit, cockpit 2 cột chưa/đã báo cáo, lọc ngày/SR/user, phân trang 20
  đơn/cột, realtime WebSocket refresh từ cache DB, QR/barcode scan mã
  đơn, auto-fill nhiều category/need/customer type từ mock ERP, checkbox
  selectors, installment partner/approval/reason validation, không gửi `MSNV`,
  form validation và export CSV.
- Manual smoke sau deploy: cấu hình ERP env trên VPS, check một mã đơn thật,
  gửi một báo cáo mua hàng và xác nhận duplicate bị chặn.
