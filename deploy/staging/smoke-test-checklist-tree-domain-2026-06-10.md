# Smoke Test Checklist Staging - Tree Domain 2026-06-10

Môi trường staging:

- Trang tải: https://opshub.hoanghochoi.com/staging-download
- API: https://opshub-staging.hoanghochoi.com/api
- Health: https://opshub-staging.hoanghochoi.com/health

Quy ước test:

- Chỉ tick `[x]` khi bước đã pass thật trên staging.
- Mục chưa pass ghi note ngay sau dòng checklist, kèm user, nền tảng, thời điểm, ảnh/log nếu có.
- Không ghi mật khẩu staging, token, MAP password, hoặc thông tin tài khoản thật vào file này.
- Dùng tài khoản staging đã thống nhất: `admin@hoanghochoi.com`, `staging.admin@phongvu.vn`, `staging.acare@acare.vn`, `staging.staff@phongvu.vn`.

## 0. Thông Tin Lần Test

- Người test:
- Ngày giờ:
- Nền tảng: Windows / Android
- App version/build:
- Commit staging:
- GitHub workflow run:
- Kết quả chung: Đạt / Không đạt / Bị chặn
- Ghi chú chung:

## 1. Deploy Và Endpoint

- [x] GitHub workflow `Deploy OpsHub Staging` hoàn tất thành công cho commit cần test.
- [x] `https://opshub-staging.hoanghochoi.com/health` trả `ok`.
- [x] `https://opshub-staging.hoanghochoi.com/api/health` trả JSON có `status: ok` và `service: backend-nest`.
- [x] `https://opshub-staging.hoanghochoi.com/api/app-version?platform=android` trỏ về `/staging-download/downloads/`.
- [x] `https://opshub-staging.hoanghochoi.com/api/app-version?platform=windows` trỏ về `/staging-download/downloads/`.
- [x] `https://opshub.hoanghochoi.com/staging-download/downloads/latest.json` chỉ chứa URL staging.
- [x] Tải được APK Android staging mới.
- [x] Tải được bộ cài Windows staging mới.
- [x] App staging cài cạnh production, không ghi đè app production.

## 2. Đăng Nhập Và Role

- [x] `admin@hoanghochoi.com` đăng nhập được, role `SUPER_ADMIN`, không bị ép scope domain/store.
- [x] `staging.admin@phongvu.vn` đăng nhập được, role hiển thị/resolve là `ADMIN_PHONGVU` hoặc `Admin Phong Vũ`.
- [x] `staging.acare@acare.vn` đăng nhập được, role `ADMIN_ACARE`.
- [x] `staging.staff@phongvu.vn` đăng nhập được và chỉ thấy các chức năng được cấp.
- [x] Đăng xuất rồi đăng nhập lại không mất quyền hoặc giữ nhầm session user cũ.
- [x] Nhập sai mật khẩu báo lỗi rõ ràng, không clear session hợp lệ của user khác.

## 3. Navigation Quản Trị

- [x] `SUPER_ADMIN` thấy menu `Quản trị` và màn `Cơ cấu tổ chức`.
- [x] `ADMIN_PHONGVU` thấy các màn quản trị đúng quyền trong scope Phong Vũ.
- [ ] `ADMIN_ACARE` thấy các màn quản trị đúng quyền trong scope A Care. -> có tick quyền quản lý SR nhưng không thấy trong Quản trị
- [x] User không có quyền admin không thấy route admin, hoặc bị chặn/điều hướng rõ ràng.
- [x] Menu `Quản lý Vùng/Miền` không còn là luồng chỉnh sửa riêng, hoặc redirect về `Cơ cấu tổ chức`.
- [x] Menu `Quản lý SR` không còn là luồng chỉnh sửa riêng, hoặc redirect về `Cơ cấu tổ chức`.
- [x] Không còn hai nơi độc lập cùng sửa Miền/Vùng/SR làm lệch dữ liệu.

## 4. Cơ Cấu Tổ Chức Là Source Of Truth

- [x] Tree mặc định chỉ hiện root `phongvu.vn` và `acare.vn`.
- [x] Click root mới expand, trạng thái expand được giữ trong phiên màn hình.
- [x] Dưới `phongvu.vn` thấy Miền, Vùng, SR theo dữ liệu staging đã backfill.
- [x] Dưới `acare.vn` thấy Miền, Vùng, SR A Care, gồm `AC001` nếu staging DB có dữ liệu này.
- [x] Một SR đang có trong danh sách/quyền nghiệp vụ cũng xuất hiện là node type `SHOWROOM` trong tree.
- [ ] Node `REGION` hiển thị/sửa được mã nghiệp vụ, tên, viết tắt, trạng thái theo quyền.
- [ ] Node `AREA` hiển thị/sửa được mã nghiệp vụ, tên, viết tắt, parent Miền, trạng thái theo quyền.
- [ ] Node `SHOWROOM` hiển thị `Mã showroom`, `Tên showroom`, `Node cha`, type, trạng thái, user count/store info.
- [ ] Tạo Miền mới dưới root đúng domain, reload vẫn còn.
- [ ] Tạo Vùng mới dưới Miền, reload vẫn còn.
- [ ] Tạo SR mới dưới Vùng tạo/link được `Store` tương ứng.
- [ ] Move SR sang Vùng khác làm ancestry/scope đổi theo tree.
- [ ] Sau khi move SR, user/store/rule dùng scope mới, không còn phụ thuộc catalog Vùng/Miền cũ.
- [ ] Xóa node có children bị backend chặn với lý do rõ ràng.
- [ ] Xóa node có user/SR/reference bị backend chặn với lý do rõ ràng.
- [ ] Xóa node rỗng thành công hoặc inactive theo rule backend, UI không tự tắt node im lặng.

## 5. Shim API Vùng/Miền/SR Cũ

- [ ] Màn hoặc API cũ `/admin/regions` trả dữ liệu derive từ tree, không dùng source legacy độc lập.
- [ ] Màn hoặc API cũ `/admin/areas` trả dữ liệu derive từ tree, không dùng source legacy độc lập.
- [ ] Màn hoặc API cũ `/admin/stores` trả dữ liệu derive/link từ node `SHOWROOM`.
- [ ] Sửa qua shim nếu còn route gọi sẽ cập nhật tree/source canonical.
- [ ] Không phát sinh tình trạng gán cửa hàng vào Vùng/Miền nhưng tree không đổi.

## 6. Quản Lý User Và Scope

- [ ] Search user theo tên realtime debounce khoảng 300ms, giữ các filter hiện tại.
- [ ] Search user theo email realtime debounce khoảng 300ms, giữ các filter hiện tại.
- [ ] Filter user theo domain hoạt động với `phongvu.vn` và `acare.vn`.
- [ ] Filter user theo node tree hoạt động cho Miền, Vùng, SR.
- [ ] User editor dùng tree picker cho scope, không dùng dropdown Vùng/Miền/SR legacy như source chính.
- [ ] Sửa user/tick chức năng mở dialog tóm tắt thay đổi trước khi lưu.
- [ ] `Xác nhận lưu` gọi API và lưu đúng thay đổi.
- [ ] `Hủy thay đổi` quay về trạng thái trước sửa.
- [ ] `ADMIN_ACARE` chỉ thấy/sửa/reset mật khẩu user trong scope A Care hoặc domain `@acare.vn` theo rule staging.
- [ ] `ADMIN_PHONGVU` chỉ thấy/sửa/reset mật khẩu user trong scope Phong Vũ.
- [ ] Cả hai admin domain không thao tác được lên `SUPER_ADMIN`.

## 7. Policy Và Feature Rule Theo Tree

- [ ] Feature rule editor dùng tree picker cho scope node.
- [ ] Policy rule editor dùng tree picker cho scope node.
- [ ] Rule đặt ở Miền áp dụng xuống Vùng/SR descendants.
- [ ] Rule đặt ở Vùng áp dụng xuống SR descendants.
- [ ] Rule đặt ở SR chỉ áp dụng đúng SR đó.
- [ ] Rule theo node không cấp quyền vượt domain của admin đang thao tác.
- [ ] User đăng nhập lại nhận đúng feature/policy resolved từ node ancestry.

## 8. Quản Lý SR Và MAP Credential

- [ ] `SUPER_ADMIN` sửa được đầy đủ field SR/SHOWROOM theo quyền hiện tại.
- [ ] `ADMIN_PHONGVU` sửa được `mapVietinUsername` và `mapVietinPassword` của SR trong scope Phong Vũ.
- [ ] `ADMIN_ACARE` sửa được `mapVietinUsername` và `mapVietinPassword` của SR trong scope A Care.
- [ ] `ADMIN_PHONGVU` bị chặn khi sửa SR ngoài scope.
- [ ] `ADMIN_ACARE` bị chặn khi sửa SR ngoài scope.
- [ ] `ADMIN_PHONGVU` và `ADMIN_ACARE` không sửa được số tài khoản nhận tiền.
- [ ] `ADMIN_PHONGVU` và `ADMIN_ACARE` không sửa được tên tài khoản, ngân hàng, BIN.
- [ ] `ADMIN_PHONGVU` và `ADMIN_ACARE` không sửa được mã SR, tên SR, Vùng/Miền nếu không có quyền riêng.
- [ ] Khi field bị khóa, UI hiển thị locked/disabled rõ ràng và backend vẫn chặn nếu gọi API trực tiếp.

## 9. Feedback

- [ ] User có feature `FEEDBACK` gửi phản hồi text thành công.
- [ ] User có feature `FEEDBACK` gửi phản hồi kèm ảnh nhỏ thành công.
- [ ] User không có feature `FEEDBACK` không vào/gửi được phản hồi.
- [ ] `SUPER_ADMIN` thấy menu `Danh sách phản hồi` trong Quản trị.
- [ ] `SUPER_ADMIN` mở danh sách phản hồi và thấy phản hồi staging mới gửi.
- [ ] `ADMIN_PHONGVU` không thấy menu `Danh sách phản hồi`.
- [ ] `ADMIN_ACARE` không thấy menu `Danh sách phản hồi`.
- [ ] API admin list feedback trả 403 cho admin domain, chỉ cho `SUPER_ADMIN`.

## 10. Warranty Upload Và Realtime

- [ ] Upload ảnh từ camera Android gửi MIME/content type hợp lệ và backend nhận ảnh.
- [ ] Upload ảnh từ gallery Android gửi MIME/content type hợp lệ và backend nhận ảnh.
- [ ] Upload ảnh trên Windows gửi MIME/content type hợp lệ và backend nhận ảnh.
- [ ] File không phải ảnh bị UI cảnh báo trước khi submit.
- [ ] Backend vẫn chặn file không phải ảnh nếu gọi API trực tiếp.
- [ ] URL ảnh warranty trả về staging `/uploads/...`, không dùng storage production.
- [ ] Flutter WebSocket connect tới staging realtime thành công.
- [ ] App log có connect/disconnect/error/event ở flow realtime, không log secrets.
- [ ] Khi backend publish `WARRANTY_STATUS_UPDATED`, app reload/update record warranty liên quan.
- [ ] Realtime không reconnect liên tục khi app ở trạng thái bình thường.

## 11. Regression Nghiệp Vụ Chính

- [ ] FIFO check mở được, thiếu dữ liệu thì empty/error rõ ràng, không crash.
- [ ] FIFO sort mở được, input invalid báo validation rõ ràng.
- [ ] Lịch sử FIFO tải được hoặc empty state rõ ràng.
- [ ] VietQR mở được nếu có quyền, không dùng dữ liệu production.
- [ ] Sao kê mở được nếu có quyền, query staging không crash.
- [ ] Tiền vào trên Windows mở được nếu có quyền, trạng thái no-data xử lý rõ ràng.
- [ ] App logs upload được lỗi nhẹ an toàn, không log mật khẩu/token/MAP password.
- [ ] Không có API call nào từ app staging trỏ về `https://opshub.hoanghochoi.com/api` production.

## 12. Tiêu Chí Accept Cuối

- [ ] Workflow staging xanh và endpoint public pass.
- [ ] Android staging cài/mở được cạnh production.
- [ ] Windows staging cài/mở được cạnh production.
- [ ] `SUPER_ADMIN`, `ADMIN_PHONGVU`, `ADMIN_ACARE`, staff staging đăng nhập được.
- [ ] Tree là nơi duy nhất quản lý Miền/Vùng/SR trong UI.
- [ ] SR trong quản lý nghiệp vụ và tree không còn lệch nhau.
- [ ] Admin domain chỉ sửa MAP credential trong scope, không sửa tài khoản nhận tiền.
- [ ] Danh sách phản hồi chỉ `SUPER_ADMIN` thấy.
- [ ] Warranty upload ảnh và realtime warranty event hoạt động hoặc lỗi staging được ghi rõ.
- [ ] Không đụng endpoint/storage production trong toàn bộ smoke test.
