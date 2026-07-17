# SALES-REPORT-001: Báo cáo bán hàng

## Story

Sale cần gửi báo cáo mua hàng/chưa mua hàng trong OpsHub để dữ liệu không còn
nằm rời ở Google Form và có thể dùng cho dashboard sau này.

## Acceptance

- Vận hành hiện trực tiếp `Báo cáo bán hàng` tại `/sales-reports` khi user có
  `SALES_REPORT`; `/reports` chỉ redirect tương thích. `ADMIN_SALES_REPORTS`
  đưa `Danh sách báo cáo bán hàng` vào menu `Quản trị`.
- Màn hình `Báo cáo bán hàng` hiển thị cockpit 2 cột theo khoảng ngày: trái là đơn chưa báo
  cáo, phải là đơn đã báo cáo; phần card, nút và filter không cuộn theo danh
  sách; mỗi cột tự cuộn vùng list, hiển thị 20 đơn/trang, có total đếm từ DB và
  bộ chuyển trang riêng dạng compact chỉ gồm hai mũi tên. Phía trên giữ hai nút
  nằm ngang `Báo cáo mua thủ công` và `Báo cáo chưa mua`, cùng `Tải lại`;
  xuất file/danh sách thuộc màn quản trị riêng.
- Cockpit lọc theo daterange `Ngày`, `SR` và `User`; filter `SR`/`User` chỉ hiện
  trong scope quản lý. Khi mở màn hình, daterange mặc định là ngày hiện tại
  giống Trang chủ và request đầu tiên gửi ngày bắt đầu/kết thúc cùng ngày đó.
- Backend tự đồng bộ danh sách đơn ERP từ staff-bff theo ngày mỗi 1 phút và khi
  service khởi động, mặc định 50 đơn/ngày gần nhất (giới hạn cấu hình tối đa
  cũng là 50 theo contract hiện tại của ERP list), rồi upsert snapshot rút gọn vào bảng cache riêng. Ngay trong
  lần sync/list hoặc lookup đầu tiên, backend phải lấy showroom từ
  `createdFromSiteDisplayName` của ERP dạng `[CP58] ...` để ghi `storeCode`;
  các sync phía sau không được ghi đè showroom này bằng context user/owner yếu
  hơn. Backend vẫn map `creator.email` sang user nội bộ và showroom/node được
  gán; payload sync thiếu dữ liệu không được xóa mapping đã lưu. Cache cũ đã có
  user nhưng thiếu showroom/node sẽ được backfill lại từ user nội bộ trong lần
  sync sau. Flutter không kích hoạt ERP sync; client đọc cache DB khi mở màn
  hình hoặc bấm `Tải lại`, và refresh realtime qua WebSocket khi backend báo có
  đơn mới hoặc mapping vừa được bổ sung trong scope liên quan.
- User thường chỉ thấy đơn/report của mình theo
  `data.orders.creator.email`, fallback về consultant/seller/source-user
  snapshot nếu ERP không trả creator. STORE_MANAGER hoặc chức danh quản lý theo
  node xem dữ liệu trong showroom/node con được gán; Super Admin xem toàn bộ
  cache/report trong DB.
- Bấm đơn chưa báo cáo mở dialog báo cáo mua hàng và dùng lại luồng
  `check-order` để tự fill dữ liệu cần thiết trước khi sale nhập phần còn lại.
- Nút `Báo cáo mua thủ công` mở form mua hàng hiện hữu để sale tự nhập hoặc
  quét mã đơn khi đơn chưa xuất hiện trong danh sách cockpit.
- Nếu report thủ công có `orderCode` trùng đơn đang nằm trong cache cockpit theo
  filter hiện tại, cockpit phải tính đơn đó là đã báo cáo và loại khỏi cột chưa
  báo cáo sau khi reload.
- Đơn ERP có `grandTotal <= 0` là đơn vận hành nội bộ, không tính là đơn cần
  báo cáo; backend phải persist exclusion để reload vẫn không hiện ở cột chưa
  báo cáo/đã báo cáo và không tính vào KPI.
- Form `Mua hàng` yêu cầu nhập hoặc quét QR/barcode mã đơn và check ERP trước
  khi nhập/gửi báo cáo; sau khi check có thể bấm `Kiểm tra đơn khác` để đổi đơn.
- Nếu chi tiết ERP sau lần check do user chủ động vẫn có `paymentStatus` thuộc
  nhóm chưa thanh toán, form phải khóa nút `Gửi báo cáo`, cuộn phần thân modal
  về đầu và hiện toast `Đơn chưa thanh toán, vui lòng vào spos bấm Thanh toán
  lại hoặc Hủy đơn.` Không tạo báo cáo cho đến khi đơn được thanh toán hoặc hủy.
- Nếu ERP trả `confirmationStatus` hoặc `fulfillmentStatus` là `cancelled`
  không phân biệt hoa/thường, app báo `Đơn đã bị hủy.` và không load thông tin
  đơn hàng vào form.
- ERP/Listing trả được ngành hàng/nhu cầu thì app tự fill; với ngành hàng, từng
  item chỉ exact-match node `categories[]` có level lớn nhất với dòng tương ứng
  trong `data/categories.csv`, rồi lấy `Cat group ID` và `Type` từ chính dòng
  đó. Không dùng `NHxx` level 1, category cha, product group/type, tên sản phẩm
  hay vị trí mảng làm fallback. Thiếu level hoặc node sâu nhất không map được
  thì sale chọn tay; `Type = gift` không tự tick ngành hàng. Một báo cáo có thể
  chọn nhiều ngành hàng.
- Nhu cầu khách hàng và các câu hỏi hành vi sale là bắt buộc; hành vi tư vấn,
  trải nghiệm, quét Zalo và tải App PV mặc định là chưa chọn, không tự chọn
  `Có`, và các nhóm lựa chọn trong form dùng checkbox thay cho dropdown.
- Cả 2 form bắt buộc nhập `Tên khách hàng`; báo cáo mua hàng tự fill khi ERP
  trả được tên khách hàng nhưng vẫn cho sale nhập khi ERP không có dữ liệu.
- Form lưu loại khách hàng bằng `customerType`; báo cáo mua hàng tự fill
  `Doanh nghiệp` khi ERP trả `billingInfo.customerType = BUSINESS` hoặc
  `billingInfo.taxCode` có giá trị; nếu cả hai không thể hiện doanh nghiệp thì
  xem là `Cá nhân`, gồm `billingInfo.customerType = INDIVIDUAL`.
  `Học sinh - Sinh viên` là checkbox con của
  `Cá nhân`, được lưu bằng flag riêng `customerIsStudent`; tick HS-SV tự tick
  `Cá nhân`, còn chọn `Doanh nghiệp` thì khóa/bỏ chọn `Cá nhân` và HS-SV.
- Báo cáo mua hàng bắt buộc nhóm checkbox `CTKM áp dụng`: `Đổi điểm thi`,
  `Học sinh - Sinh viên`, `CTKM khác`. Check/submit ERP tự fill `Đổi điểm thi`
  từ `payments[].partnerTransactionCode` bắt đầu `PVDD`, tự fill
  `Học sinh - Sinh viên` từ `priceSummary[].tags` bắt đầu `PVHSSV`, và fill
  `CTKM khác` nếu không khớp. Hai nhóm đặc biệt đồng thời ép loại khách về
  `Cá nhân` + cờ `Học sinh - Sinh viên`.
- Backend re-check ERP khi submit, chặn đơn chưa thanh toán bằng cùng thông báo
  hướng dẫn SPOS và chặn duplicate `orderCode`.
- Check/submit lưu trạng thái vòng đời ERP và dữ liệu hoàn trả. Pending được
  giữ trong tiến độ nhưng chưa tính doanh số; đơn 0 VND, hủy/trả toàn bộ bị
  loại; trả một phần trừ giá trị trả trước khi bỏ VAT 8%.
- Backend rà trạng thái mỗi 5 phút, mặc định tối đa 80 đơn với concurrency 2:
  rà cả pending trong cache chưa báo cáo và pending đã báo cáo, ưu tiên ngày bán
  gần nhất đến ngày xa nhất trong từng nhóm, đồng thời vẫn dành quota cho đơn
  completed để bắt hoàn trả muộn. Mỗi ngày Việt Nam, background gọi tối đa 3
  lần/đơn pending với khoảng cách ít nhất 60 phút; completed chỉ gọi lại sau 2
  ngày và quá 10 ngày từ ngày bán thì không gọi lại. Pending chuyển completed ở
  lượt nào thì lượt đó mở đầu chu kỳ kiểm tra completed 2 ngày. Redis lease ngăn
  nhiều replica chạy trùng; quota theo showroom giúp tránh dồn tải lên ERP.
  Check/submit do user chủ động không bị quota background chặn và luôn persist
  trạng thái hủy/trả/hoàn thành mới nhất từ ERP.
- Form `Chưa mua hàng` không gọi ERP, bắt buộc ngành hàng và lý do chưa mua.
  Form bỏ ô Zalo text tự do; số điện thoại chỉ được để trống hoặc nhập đúng
  `0` + 9 chữ số. Hai checkbox `Zalo cá nhân` và `Zalo OA` được lưu độc lập
  cùng kênh `PHONE` suy ra từ số hợp lệ trong `customerContactChannels` để các
  chức năng và báo cáo sau dùng lại.
- Cả 2 form có tick `Có nhu cầu trả góp`. Khi tick, sale phải chọn một hoặc
  nhiều đối tác trong list: `VNPAY - POS`, `PAYOO - POS`,
  `HomeCredit - CTTC`, `Shinhan - CTTC`, `HDSaison - CTTC`,
  `AEON Finance - CTTC`, `Mirae Asset`, `MPOS`; chọn hồ sơ được duyệt hay chưa,
  nhập số tiền vay nếu có, và chọn lý do không trả góp trong danh sách cố định.
  Các số tiền trên UI dùng dấu phân cách hàng ngàn theo chuẩn `vi_VN`.
- Báo cáo mua hàng tự tick nhu cầu trả góp khi ERP có
  `payments[].paymentMethod` chứa `installment` và tự điền tổng `amount` dương
  của các payment đó làm số tiền vay gợi ý.
- Từ cockpit, bấm đơn chưa báo cáo, `Báo cáo mua thủ công`, và
  `Báo cáo chưa mua` đều mở cùng kiểu modal. Header card của modal được cố định
  ngoài vùng cuộn để luôn giữ tên báo cáo, trạng thái và hành động quay lại.
- ERP order check lưu phương thức thanh toán, loại khách hàng, snapshot đơn hàng
  đã sanitize, và từng sản phẩm thành từng row trong `SalesReportOrderItem`.
  Backend map thêm `categoryType` bằng `Type` trong `data/categories.csv`, chỉ
  dùng category level sâu nhất trong payload `categories` từ Listing.
- Admin xuất 3 file Excel `.xlsx` tiếng Việt: `HVTC` một dòng mỗi báo cáo
  mua/chưa mua theo các cột hành vi khách hàng; `Doanh số` một dòng tổng hợp số
  đơn duy nhất, doanh thu doanh nghiệp/cá nhân, tổng số báo cáo có tick
  `Có nhu cầu trả góp`, số đơn trả góp thành công theo payment method ERP và số
  lượng theo type laptop/PC/PC ráp/Apple/màn hình/máy in/phụ kiện/bảo hiểm mở
  rộng; lý do trả góp nằm ở cột cuối cùng của file `Doanh số`;
  `Trả góp` chỉ lấy các row có `installmentNeed = true`, gồm các cột tiếng Việt
  `Ngày báo cáo`, `Email người báo cáo`, `Số tiền vay trả góp`,
  `Đối tác trả góp`, `Kết quả duyệt hồ sơ`, `Loại báo cáo`,
  `Phương thức thanh toán cuối cùng`, `Lý do không trả góp`. Với row
  `NOT_PURCHASED`, phương thức thanh toán cuối cùng là `Chưa mua hàng`; chỉ
  row `PURCHASED` mới phân loại `Trả góp` hoặc `Trả thẳng` theo ERP method.
- Admin có `ADMIN_SALES_REPORTS` theo node tổ chức xem/query/export báo cáo
  trong phạm vi được gán; Super Admin thấy toàn app. Nếu admin được gán nhiều
  SR, danh sách quản trị có bộ lọc `SR` để xem từng showroom hoặc `Tất cả SR`;
  filter list và export dùng cùng `storeIds`.
- OpsHub sync dữ liệu báo cáo sang BigQuery bằng bốn bảng
  report/revenue-by-store/item/payment để Looker Studio đọc từ BigQuery. Bảng
  doanh số BigQuery có một row cho mỗi cửa hàng/showroom, không sync một dòng
  tổng toàn bộ. Sync chạy nền khi bật env và có endpoint admin
  `POST /api/sales-reports/admin/bigquery-sync` để chạy thủ công.
- Danh sách báo cáo admin mặc định chọn ngày hiện tại. Bộ lọc dùng một action
  `Chọn khoảng ngày` để chọn cả `Từ ngày` và `Đến ngày` trong cùng một range
  picker rồi áp dụng một lần; nếu admin chủ động chọn `Tất cả ngày`, query/export
  mặc định lấy 30 ngày gần nhất và hiện dòng nhắc giải thích fallback này.
- Ngành hàng lấy từ `data/categories.csv`, hiển thị tiếng Việt và lưu snapshot
  song song code/tên gốc/tên Việt.
- Không có payload nhập tay `MSNV`.

## Proof Target

- Backend: Prisma validate/generate, Nest build, focused sales-report Jest khi
  bổ sung test suite.
- Flutter: `flutter analyze`, focused widget/provider tests khi bổ sung test
  suite.
- Repo: `git diff --check`.

## Notes

- Dashboard UI chưa thuộc story này; DB/API/export phải đủ để dashboard nối vào
  sau.
- ERP credential nhập qua env trên server, không commit vào repo.
