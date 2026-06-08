# Smoke Test Staging Sau Refresh DB Production

Ngày tạo: 2026-06-08
Môi trường: `https://opshub-staging.hoanghochoi.com`
Build kỳ vọng: `2026.06.08.7+200007` - release notes `Staging GitHub 8cef0a0`

## Nguyên tắc test

- Chỉ test trên staging, không dùng production URL.
- Không ghi mật khẩu, token, mã OTP, app password, thông tin ngân hàng thật vào checklist hoặc ảnh chụp.
- Nếu gặp lỗi, ghi lại: tài khoản test, màn hình, thao tác vừa làm, thời điểm, ảnh chụp màn hình, và message lỗi.
- Sau mỗi nhóm test có thao tác tạo/sửa dữ liệu, refresh màn hình và mở lại app để kiểm tra dữ liệu còn đúng.

## 1. Preflight

- [ ] Mở `https://opshub-staging.hoanghochoi.com/health`, kỳ vọng hiển thị `ok`.
- [ ] Mở `https://opshub-staging.hoanghochoi.com/api/health`, kỳ vọng JSON có `status: ok` và `service: backend-nest`.
- [ ] Mở app staging, kiểm tra màn cập nhật bắt buộc đang trỏ build `2026.06.08.7+200007` nếu app cũ hơn.
- [ ] Đảm bảo đang dùng tài khoản staging đã thống nhất. Không dùng tài khoản production thật để thao tác nghiệp vụ.

## 2. Đăng nhập và phân quyền cơ bản

- [ ] Đăng nhập bằng `admin@hoanghochoi.com`; kỳ vọng vào được app với quyền `SUPER_ADMIN`.
- [ ] Đăng xuất, đăng nhập lại bằng tài khoản staging admin Phong Vũ; kỳ vọng vào được app và thấy menu admin.
- [ ] Đăng xuất, đăng nhập bằng tài khoản staging staff Phong Vũ; kỳ vọng chỉ thấy các chức năng được tick cho user đó.
- [ ] Đăng xuất, đăng nhập bằng tài khoản staging A Care; kỳ vọng chỉ thấy dữ liệu/luồng thuộc A Care khi scope áp dụng.
- [ ] Thử mở một màn không được tick quyền bằng tài khoản staff; kỳ vọng bị chặn hoặc không thấy menu, không được vào màn trống.
- [ ] Đăng xuất rồi đăng nhập lại sau khi đổi user; kỳ vọng session cũ không tự giữ quyền của user trước.

## 3. Cơ cấu tổ chức dạng tree

- [ ] Vào Admin -> Cơ cấu tổ chức.
- [ ] Kiểm tra cây có root domain `phongvu.vn` và `acaretek.vn`.
- [ ] Mở root `phongvu.vn`; kỳ vọng có node con sub-domain `phongvu.vn`.
- [ ] Kiểm tra các sub-domain/khối/phòng ban/showroom/chức danh hiển thị theo dạng tree, không bị lẫn thành list phẳng khó đọc.
- [ ] Chọn node showroom bất kỳ; kỳ vọng panel chi tiết bên phải hiển thị đúng mã showroom/tên showroom/node cha.
- [ ] Với `SUPER_ADMIN`, tạo thử một node test dưới `phongvu.vn` với tên dễ nhận biết, ví dụ `TEST-SMOKE-<ngày>`.
- [ ] Sửa tên node test vừa tạo; kỳ vọng tree cập nhật ngay và reload vẫn còn đúng.
- [ ] Xóa node test khi node chưa có dữ liệu phụ thuộc; kỳ vọng xóa được và không còn trong tree.
- [ ] Thử xóa node có children hoặc showroom thật; kỳ vọng bị chặn, app hiển thị lý do rõ ràng.
- [ ] Đăng nhập user không phải `SUPER_ADMIN`; kỳ vọng không thấy hoặc không dùng được nút thêm/sửa/xóa node.

## 4. Quản lý người dùng và filter

- [ ] Vào Admin -> Quản lý người dùng.
- [ ] Search theo tên; kỳ vọng danh sách lọc đúng và không mất filter khác đang chọn.
- [ ] Search theo email; kỳ vọng tìm được user staging tương ứng.
- [ ] Filter theo domain/sub-domain `phongvu.vn`; kỳ vọng chỉ ra user thuộc domain phù hợp.
- [ ] Filter theo node tổ chức/showroom; kỳ vọng danh sách chỉ còn user thuộc node đó hoặc node con nếu UI thiết kế có include children.
- [ ] Filter theo chức năng/màn hình; kỳ vọng chỉ ra user đã được tick chức năng đó.
- [ ] Filter theo role; kỳ vọng role hiển thị đúng và không lẫn role khác.
- [ ] Filter theo status; kỳ vọng user locked/active phân tách đúng.
- [ ] Bấm reset filter; kỳ vọng chỉ còn search rỗng và danh sách trở về trạng thái mặc định.

## 5. Sửa user và tick nhiều chức năng

- [ ] Mở dialog Sửa người dùng của một tài khoản staff staging.
- [ ] Kiểm tra section `Chức năng được sử dụng` hiển thị dạng checkbox tree.
- [ ] Tick thêm 2-3 chức năng test, lưu lại; kỳ vọng toast/thông báo thành công.
- [ ] Mở lại user đó; kỳ vọng các chức năng vừa tick vẫn được giữ.
- [ ] Đăng nhập bằng user đó; kỳ vọng menu/màn hình tương ứng được mở.
- [ ] Bỏ tick một chức năng, lưu lại, đăng nhập lại user đó; kỳ vọng chức năng bị bỏ tick không còn dùng được.
- [ ] Đảm bảo `SUPER_ADMIN` vẫn dùng được toàn bộ app dù không cần tick từng chức năng.

## 6. Dữ liệu showroom và master data sau refresh

- [ ] Mở danh sách showroom/cửa hàng; kỳ vọng có dữ liệu showroom production đã sanitize, tối thiểu 35 showroom.
- [ ] Tìm các mã mẫu: `AC001`, `CP01`, `CP02`, `CP05`; kỳ vọng tìm được và tên/area hiển thị hợp lý.
- [ ] Mở chi tiết một showroom; kỳ vọng không hiển thị số tài khoản chuyển khoản thật, username/password MAP, hoặc secret thô.
- [ ] Kiểm tra filter/khu vực: số vùng/khu vực/phòng ban/chức danh có dữ liệu, không rỗng bất thường.
- [ ] Với user showroom, kiểm tra app chỉ gợi ý/show dữ liệu showroom thuộc scope của user.

## 7. Luồng nghiệp vụ chính

- [ ] Warranty: mở danh sách bảo hành, filter theo showroom/khoảng ngày, mở chi tiết một record; kỳ vọng không có PII nhạy cảm thật sau sanitize.
- [ ] Warranty: tạo một phiếu test mới với dữ liệu giả; kỳ vọng lưu được, reload còn dữ liệu, log không báo lỗi.
- [ ] VietQR/MAP: mở màn giao dịch/thanh toán; kỳ vọng danh sách có dữ liệu đã sanitize và không lộ payer account/raw secret thật.
- [ ] VietQR/MAP: filter theo showroom và trạng thái; kỳ vọng kết quả đổi đúng theo filter.
- [ ] FIFO: mở màn FIFO/log; kỳ vọng có dữ liệu lịch sử đã sanitize, filter được theo showroom/thời gian.
- [ ] Feedback: mở màn feedback; nếu danh sách rỗng thì app phải hiển thị empty state rõ ràng, không crash.
- [ ] Realtime: thực hiện thao tác có cập nhật realtime nếu có flow phù hợp; kỳ vọng màn khác nhận cập nhật hoặc không báo mất kết nối.

## 8. Kiểm tra an toàn dữ liệu staging

- [ ] User session cũ không còn hiệu lực sau refresh; nếu đang mở app trước refresh, kỳ vọng phải đăng nhập lại.
- [ ] Các token reset password/email verification cũ không còn dùng được.
- [ ] Không thấy app logs production cũ trong màn/log viewer staging.
- [ ] Không thấy payment delivery logs production cũ.
- [ ] Không thấy store transfer account/MAP credential thật ở UI hoặc response debug.

## 9. Kết luận smoke test

- [ ] Pass toàn bộ nhóm 1-8.
- [ ] Nếu fail, tạo ticket/ghi chú với format: `Màn hình -> thao tác -> expected -> actual -> tài khoản -> thời điểm -> ảnh/log`.
- [ ] Nếu fail ở auth/phân quyền/org-tree, dừng test nghiệp vụ phía sau và báo lại trước khi sửa dữ liệu tiếp.
- [ ] Nếu fail ở dữ liệu sensitive, dừng ngay và không chia sẻ ảnh/log ra ngoài nhóm nội bộ.
