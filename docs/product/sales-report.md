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
  thủ công nếu cần xem ngày/khoảng khác. `Tổng quan cá nhân` mặc định là
  `Chưa chọn SA`; khi chưa chọn thủ công, các KPI `Bán hàng` và
  `Hành vi then chốt` vẫn giữ toàn bộ scope showroom/node ở header. Khi tài
  khoản quản lý chọn SA trong `Tổng quan cá nhân`, các KPI này mới dùng scope
  cá nhân của SA đó, định danh SA bằng email và không dùng mã nhân viên/generated
  code để lọc; `Tổng quan Cửa hàng` và `Tài chính` vẫn giữ theo
  showroom/node đang chọn ở header. Khu vực `Bán hàng` chia thành nhóm
  `Doanh số`, `KPI chính` và `Hành vi then chốt`. Nhóm `Doanh số` hiển thị
  doanh số tổng từ cache đơn hàng theo ngày bán ERP (`orderCreatedAt`) sau khi
  loại đơn 0 VND, đơn hủy/trả toàn bộ và trừ giá trị trả một phần, số đơn bán,
  trung bình đơn hàng, doanh số hoàn thành, pending và
  `Tỉ lệ chuyển đổi = tổng số đơn / tổng số báo cáo`. Nhóm `KPI chính`
  hiển thị doanh số khách hàng doanh nghiệp, doanh số khách hàng cá nhân,
  số lượng CTKM đổi điểm thi, CTKM học sinh - sinh viên, nhu cầu trả góp,
  trả góp thành công, bảo hiểm mở rộng, laptop, PC bộ, PC ráp,
  Apple (iPhone, MacBook, iPad), màn hình, máy in và phụ kiện. Nhóm
  `Hành vi then chốt` hiển thị số khách chưa mua, số đơn chưa báo cáo,
  báo cáo đã mua, `Tỉ lệ báo cáo = số đơn đã báo cáo / tổng số đơn`, cùng các tỉ lệ
  `Có`/tổng báo cáo cho tư vấn 3 giải pháp, trải nghiệm, Zalo OA và tải App;
  không còn card `Tổng số báo cáo hợp lệ` riêng. Bấm phần chữ của card
  `Số khách chưa mua` hoặc `Số đơn chưa báo cáo` mở modal chi tiết theo cùng
  ngày/scope/SA đang chọn; bảng hỗ trợ cuộn dọc và ngang trên màn nhỏ. Bảng
  khách chưa mua gồm Mã showroom, Tên SA, Tên khách hàng, Loại khách hàng, Ngành hàng
  và Lý do không mua. Bảng đơn chưa báo cáo gồm Mã showroom, Tên SA, Mã đơn hàng và
  Thời gian bán.
  Card `Báo cáo đã mua` chỉ mở route `/admin/sales-reports` khi user có quyền
  `ADMIN_SALES_REPORTS` như Store Manager trở lên; user không có quyền chỉ xem
  số liệu. Card `Số lượng nhu cầu trả góp` mở modal chi tiết gồm SR, Tên SA,
  Đối tác trả góp, Thành công và Ghi chú; Thành công dùng trạng thái trả góp do
  bán hàng báo cáo (`installmentStatus = SUCCESS`, fallback dữ liệu cũ
  `NORMAL_INSTALLMENT`), không suy từ ERP payment method. Ghi chú là mã đơn
  hàng nếu thành công hoặc lý do thất bại/không trả góp nếu chưa thành công.
  Các card có route hoặc modal hiển thị icon detail nhỏ ở góc trên bên phải
  nhưng vẫn giữ layout card.
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
  thao tác nghiệp vụ nằm ngang nhau: `Báo cáo mua thủ công` mở modal form mua
  hàng để sale tự nhập/quét mã đơn, còn `Báo cáo chưa mua` mở modal form khách
  chưa mua; bấm đơn chưa báo cáo cũng mở cùng modal form mua hàng. Cả ba luồng
  dùng chung presentation model, không điều hướng sang trang riêng. Modal dài
  cố định header card chứa tên báo cáo, trạng thái và nút quay lại; chỉ phần
  thân form cuộn. Cockpit không lặp lại nút xuất file hay lối vào danh sách. Khi
  mở cockpit, bộ lọc `Ngày` mặc
  định chọn ngày hiện tại và request đầu tiên gửi cùng ngày bắt đầu/kết thúc,
  đồng bộ với Trang chủ. Bộ lọc `SR`/`Nhân viên` chỉ hiện với scope quản lý,
  lấy option từ cache/report trong phạm vi user được phép xem.
- Backend tự đồng bộ danh sách đơn từ staff-bff ERP mỗi 1 phút và khi service
  khởi động, mặc định lấy 50 đơn/ngày gần nhất theo giới hạn hiện tại của ERP list. `createdFromSiteDisplayName`
  trong payload ERP dạng `[CP58] ...` là nguồn showroom duy nhất để ghi
  `storeCode` ngay trong lần sync/list hoặc lookup đầu tiên; nếu field này rỗng
  thì đơn không được map vào SR nào, dù payload còn `siteDisplayName`, terminal,
  context user hay owner. Backend vẫn
  map `creator.email` sang user nội bộ cùng showroom/node tổ chức được gán, rồi
  upsert snapshot rút gọn vào bảng cache riêng. Mapping này diễn ra ngay trong
  sync nền, không phụ thuộc sale bấm kiểm tra đơn; lần sync thiếu dữ liệu cũng
  không được xóa mapping user/showroom đã lưu. Nếu cache cũ đã có user nhưng
  thiếu showroom/node, lần sync sau sẽ bổ sung lại showroom/node từ user nội bộ
  rồi phát sự kiện realtime. Flutter không kích hoạt ERP sync;
  client đọc dữ liệu từ cache DB khi mở màn hình hoặc bấm `Tải lại`, và tự
  refresh qua WebSocket khi backend báo có đơn mới hoặc mapping cache vừa được
  bổ sung trong scope liên quan.
- Khi sale bấm một đơn chưa báo cáo, app mở form báo cáo mua hàng trong dialog,
  tự kiểm tra lại mã đơn qua luồng `check-order` hiện tại rồi fill tên khách,
  nhu cầu, loại khách, ngành hàng và thông tin đơn cần thiết.
- Nếu sale dùng `Báo cáo mua thủ công` và nhập trùng `orderCode` đang nằm trong
  cache cockpit hiện tại, backend vẫn match theo mã đơn để chuyển đơn đó sang đã
  báo cáo, không phụ thuộc metadata ngày/showroom của report thủ công.
- Khi gửi báo cáo mua hàng, app gửi metadata nguồn thao tác: `MANUAL_ENTRY` cho
  nút `Báo cáo mua thủ công`, `SYNC_LIST` cho đơn mở từ danh sách cockpit đã
  sync. Backend log source này cùng report id, showroom và định danh mã đơn đã
  sanitize, đồng thời lưu vào `rawResponses.entrySource` để truy vết sau này mà
  không cần suy luận bằng timestamp cache.
- Đơn ERP có `grandTotal <= 0` là đơn vận hành nội bộ, không cần sale báo cáo.
  Backend gắn exclusion bền vững cho cache/report cùng mã đơn, cockpit không
  trả các đơn này ở cột chưa báo cáo hoặc đã báo cáo, và các KPI báo cáo/doanh
  số không tính chúng.
- Menu `Quản trị` hiển thị `Danh sách báo cáo bán hàng` khi user có
  `ADMIN_SALES_REPORTS`; đây là nơi duy nhất lọc danh sách và xuất file.
- Màn hình danh sách báo cáo bán hàng của admin lọc danh sách và file Excel
  `.xlsx` theo loại báo cáo, SR và khoảng `Từ ngày` / `Đến ngày` dựa trên thời
  điểm gửi báo cáo (`submittedAt`). Khi user được gán nhiều SR, bộ lọc `SR` cho
  chọn từng showroom hoặc `Tất cả SR`; trạng thái `Tất cả SR` gửi query trong
  phạm vi được gán, còn chọn một SR thì gửi `storeIds` tương ứng. Khi mở màn
  hình, bộ lọc ngày mặc định là ngày hiện tại giống Trang chủ/cockpit. Người
  dùng chọn `Chọn khoảng ngày` để chọn cả hai mốc trong một range picker rồi áp
  dụng một lần; nếu chủ động chọn `Tất cả ngày`, app vẫn mặc định truy vấn/xuất
  30 ngày gần nhất và hiện dòng nhắc nhỏ để tránh hiểu nhầm.
  Admin xuất được 3 file Excel `.xlsx` tiếng Việt: `HVTC` là mỗi dòng một báo
  cáo mua/chưa mua; `Doanh số` là một dòng tổng hợp doanh thu, nhu cầu trả góp,
  trả góp thành công theo trạng thái báo cáo bán hàng và số lượng theo type
  ngành hàng;
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
  50 đơn/ngày gần nhất (đây cũng là giới hạn cấu hình tối đa theo ERP list hiện tại). List sync chỉ cập nhật
  snapshot nhanh; đơn `PENDING` từ list không được tự coi là đã xác minh trạng
  thái chi tiết.
- Job trạng thái chạy mỗi 5 phút, mặc định tối đa 80 đơn/lượt với concurrency
  2 và Redis lease. Job rà cả đơn `PENDING` trong cache chưa báo cáo lẫn đơn
  `Mua hàng` đã báo cáo, ưu tiên pending, vẫn dành quota xoay vòng cho đơn hoàn
  thành để bắt hoàn trả muộn. Theo ngày Việt Nam, background sync gọi tối đa 5
  lần cho mỗi đơn `PENDING` và tối đa 1 lần cho mỗi đơn `COMPLETED` hoặc
  `COMPLETED_PARTIAL_RETURN`; đơn hoàn thành quá 10 ngày kể từ ngày bán ERP
  không được gọi lại. Nếu pending chuyển sang completed ở bất kỳ lượt nào thì
  lượt đó đồng thời dùng quota completed của ngày và background không gọi lại
  trong cùng ngày. Job vẫn có backoff pending mặc định 5 phút và quota theo
  showroom; gọi lỗi cũng tiêu một lượt trong ngày nhưng không khóa đơn ở ngày
  kế tiếp.
- Quota trên chỉ áp dụng cho background sync. Mỗi lần sale kiểm tra đơn hoặc
  submit báo cáo, backend vẫn gọi ERP detail; nếu kết quả mới là hủy, trả toàn
  bộ hoặc trả một phần thì cache/report phải lưu trạng thái mới nhất. Kết quả
  completed/hủy/trả từ thao tác user được đánh dấu là đã kiểm tra trong ngày để
  background không gọi lại vô ích cùng ngày.
- Doanh số tổng trên dashboard lấy `grandTotal` từ cache đơn hàng theo
  ngày bán ERP (`orderCreatedAt`)/scope, bỏ đơn 0 VND, đơn hủy/trả toàn bộ và trừ
  `returnedAfterTaxAmount` khi có trả một phần. Doanh số hoàn thành chỉ cộng báo
  cáo mua hàng có trạng thái ERP hoàn thành, cũng trừ `returnedAfterTaxAmount`
  khi có trả một phần. Riêng tiến độ chỉ tiêu dùng giá trị trước VAT theo công thức
  `round(max(grandTotal - returnedAfterTaxAmount, 0) / 1.08)`. Home hiển thị
  hai card tiến độ: `Tổng quan cá nhân` cho user/SA đang chọn và
  `Tổng quan Miền/Vùng/Cửa hàng` cho toàn bộ scope quản lý hiện tại. Với tài
  khoản quản lý, card cá nhân cho phép trạng thái chưa chọn SA, hiển thị
  `Chưa chọn SA` và hướng dẫn `Chọn SA để hiển thị chỉ số`; scope toàn hệ thống
  vẫn hiển thị card cá nhân ở trạng thái này. Trên desktop đủ rộng, bốn card
  tổng quan nằm trên một hàng, trong đó `Tiến độ báo cáo` + `Tiến độ sao kê`
  gộp bằng một phần ba chiều ngang, hai card doanh số mỗi card một phần ba.
  Card `Tổng quan Cửa hàng` luôn giữ scope showroom/node, giống nhau cho các
  user trong cùng SR và không đổi khi dropdown SA thay đổi. Store
  manager/tài khoản quản lý theo node chỉ được chọn SA thuộc scope đang xem để
  xem card cá nhân; tiến độ SA chỉ cộng đơn ERP đã hoàn thành từ báo cáo mua
  hàng, không lấy doanh số cache. Danh sách SA dùng combobox chung có search
  realtime theo tên hoặc email. Trên mobile, kéo mạnh xuống ở Trang chủ tải
  lại dashboard theo bộ lọc hiện tại. Menu `Quản trị` có `Quản lý doanh số` theo
  feature `ADMIN_SALES_TARGETS`; chỉ tiêu lưu theo SR/tháng ở giá trị trước VAT.
- ERP/Listing chỉ được tự điền ngành hàng khi map được về nhóm ngành OpsHub:
  với từng sản phẩm, chỉ lấy node có `level` lớn nhất trong
  `result.products[].categories[]`, exact-match `code`/`name` của node đó với
  dòng `Subcat ID lowest level` hoặc `Subcat 2 ID` tương ứng trong
  `data/categories.csv`, rồi dùng `Cat group ID` và `Type` từ chính dòng đã
  match. Không dùng Listing category `NHxx` level 1, không tụt về category cha,
  và không fallback qua `productGroup`, `productType` hoặc tên sản phẩm. Nếu
  Listing không trả level rõ ràng hoặc node sâu nhất không map được thì sale
  phải chọn tay; sản phẩm có `Type = gift` không tự chọn ngành hàng. Một báo cáo có thể
  chọn nhiều ngành hàng vì một đơn/khách có thể có
  nhiều nhu cầu; ngành đầu tiên được lưu làm ngành chính để filter/list cũ còn
  tương thích, toàn bộ ngành được lưu trong bảng selection và xuất Excel. Nếu
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
  xem là `Cá nhân`, gồm cả payload ERP
  `billingInfo.customerType = INDIVIDUAL`.
  Với báo cáo chưa mua, sale chọn loại khách thủ công. DB lưu bằng
  `customerType` và flag riêng `customerIsStudent`.
- `CTKM áp dụng` là nhóm checkbox gồm `Đổi điểm thi`,
  `Học sinh - Sinh viên`, và `CTKM khác`; đây là trường bắt buộc của báo cáo
  mua hàng. Backend re-check ERP và tự fill theo thứ tự nguồn: mọi
  `payments[].partnerTransactionCode` bắt đầu bằng `PVDD` thêm `Đổi điểm thi`;
  mọi `priceSummary[].tags` bắt đầu bằng `PVHSSV` thêm
  `Học sinh - Sinh viên`; nếu không khớp hai nhóm trên thì fill `CTKM khác`.
  Khi khớp `PVDD` hoặc `PVHSSV`, loại khách được fill `Cá nhân` cùng cờ
  `Học sinh - Sinh viên`, kể cả payload loại khách ERP trước đó khác.
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
- Với báo cáo mua hàng, nếu bất kỳ `payments[].paymentMethod` nào chứa
  `installment` không phân biệt hoa/thường, app tự tick `Có nhu cầu trả góp`.
  Tổng các `amount` dương của các payment installment được tự điền vào
  `Số tiền vay`; sale vẫn hoàn tất đối tác, kết quả duyệt và lý do theo contract
  trả góp hiện tại trước khi gửi.
- Mọi số tiền hiển thị/nhập trong UI sales-report dùng dấu phân cách hàng ngàn
  theo chuẩn `vi_VN`, ví dụ `5.000.000 VND`; payload gửi backend vẫn là số
  nguyên không có dấu phân cách.
- Riêng các KPI/card tổng quan có chiều ngang hẹp được phép rút gọn số tiền dài
  bằng hậu tố `M`/`B`, ví dụ `179,4M VND` hoặc `1,3B VND`, để không phá layout;
  màn chi tiết, form nhập và file export vẫn dùng định dạng đầy đủ.
- Khi lấy đơn hàng từ ERP, backend lưu loại khách hàng, phương thức thanh toán,
  snapshot đơn hàng đã sanitize, và từng sản phẩm trong bảng
  `SalesReportOrderItem`. Với từng sản phẩm, backend đọc `categories` trong
  payload Listing, chỉ dùng level sâu nhất để map `Type` trong
  `data/categories.csv`, rồi lưu `categoryType` để file Doanh số tính laptop,
  PC, PC ráp, Apple, màn hình, máy in, phụ kiện và dịch vụ bảo hiểm. Item
  `categoryType = gift` vẫn được lưu để đối soát nhưng không tự chọn ngành hàng
  theo category cha của quà tặng.
- File `HVTC` xuất một dòng cho mỗi báo cáo với các cột tiếng Việt: ngày báo
  cáo, email người báo cáo, mã nhân viên tư vấn ERP, tên/số điện thoại/nhu cầu
  khách hàng, các câu trả lời hành vi, loại báo cáo, lý do chưa mua và showroom.
- File `Doanh số` xuất một dòng tổng hợp theo bộ lọc hiện tại: số đơn hàng duy
  nhất, doanh thu doanh nghiệp/cá nhân, tổng số báo cáo có tick
  `Có nhu cầu trả góp`, số đơn trả góp thành công theo `installmentStatus` của
  báo cáo bán hàng (fallback dữ liệu cũ `NORMAL_INSTALLMENT`), số lượng laptop,
  PC, PC ráp, Apple chỉ tính Macbook/iPhone/iPad, màn hình, máy in, phụ kiện,
  dịch vụ bảo hiểm; các lý do khách không trả góp nằm ở cột cuối cùng.
- File `Trả góp` xuất một dòng cho mỗi báo cáo có nhu cầu trả góp, gồm:
  `Ngày báo cáo`, `Email người báo cáo`, `Số tiền vay trả góp`,
  `Đối tác trả góp`, `Kết quả duyệt hồ sơ`, `Loại báo cáo`,
  `Phương thức thanh toán cuối cùng`, `Lý do không trả góp`.
  `Phương thức thanh toán cuối cùng` đọc từ `erpPaymentMethods`: có payment
  method installment thì ghi `Trả góp`, không có thì ghi `Trả thẳng`.
- File xuất admin dùng định dạng Excel `.xlsx` để Excel/WPS đọc tiếng Việt ổn định;
  dấu phẩy trong nội dung được giữ nguyên trong cùng một ô.
- `orderCode` là unique trên bảng `SalesReport`; một đơn mua hàng chỉ được báo
  cáo một lần.
- Không có field nhập `MSNV`; backend lấy user, email, tên, showroom và
  organization node từ token/user hiện tại. Home Summary dùng email để định danh
  SA khi lọc scope cá nhân, không dùng mã nhân viên suy ra.
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
  snapshot đã sanitize. `fetchedAt` chỉ là thời điểm đồng bộ; các bộ lọc ngày,
  Home dashboard và cockpit không dùng `fetchedAt` làm ngày bán. Nếu cache cũ
  thiếu `orderCreatedAt` nhưng snapshot còn `createdAt`, backend backfill lại
  ngày bán trước khi tính dashboard/cockpit. Chi tiết `Đơn chưa báo cáo` hiển
  thị `Tên nhân viên` cho mọi bộ phận có phát sinh bán hàng, không giới hạn chức
  danh SA. Backend ưu tiên tên của nhân viên active map đúng email/showroom, rồi
  fallback sang tên/email tư vấn, người bán hoặc người tạo từ ERP để không làm
  mất danh tính trên báo cáo HVTC. Nếu ERP xác nhận order hủy, trả toàn bộ, hoặc có
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
- Home Summary không rebuild fact đồng bộ trong request khi projection
  near-realtime được bật. Thay đổi ERP cache, Sales Report và MAP/eFAST tạo
  durable outbox cùng transaction nguồn; worker coalesce theo ngày/grain rồi
  cập nhật daily aggregate. Sau commit, backend phát `HOME_SUMMARY_UPDATED`
  không chứa KPI để app chỉ tải lại ngày/scope đang xem. `GET /home/summary`
  giữ DTO KPI hiện tại, thêm freshness metadata và trả last complete projection
  khi stale; không có projection hoàn chỉnh thì trả 503 bằng thông báo tiếng
  Việt. Legacy fact/read path còn sau feature flag trong một release để rollback.
- `SalesReportCategoryGroup` đồng bộ từ `data/categories.csv`, dùng `Cat group
ID` làm code, `Cat group name` làm tên gốc và `catGroupNameVi` làm nhãn tiếng
  Việt.
- Snapshot report lưu cả code, tên gốc và tên Việt để dữ liệu lịch sử không bị
  lệch nếu file category source đổi sau này.
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
  rows, order cockpit cache-only list, feature guard, export Excel `.xlsx` và
  BigQuery sync mapping.
- Flutter: Home/Report hub entry theo feature, route guard, order check before
  submit, cockpit 2 cột chưa/đã báo cáo, lọc ngày/SR/user, phân trang 20
  đơn/cột, realtime WebSocket refresh từ cache DB, QR/barcode scan mã
  đơn, auto-fill nhiều category/need/customer type từ mock ERP, checkbox
  selectors, installment partner/approval/reason validation, không gửi `MSNV`,
  form validation và export Excel `.xlsx`.
- Manual smoke sau deploy: cấu hình ERP env trên VPS, check một mã đơn thật,
  gửi một báo cáo mua hàng và xác nhận duplicate bị chặn.
