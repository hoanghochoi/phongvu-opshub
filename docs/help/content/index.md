# Hướng dẫn sử dụng PhongVu OpsHub

Trang này là sổ tay nhanh cho nhân viên khi cài đặt và sử dụng OpsHub. Nội dung
có thể sửa trực tiếp bằng Markdown trong repo, sau đó deploy lại static page.

## Cài đặt hoặc cập nhật ứng dụng

1. Mở trang tải ứng dụng tại `/download`.
2. Chọn đúng bản theo thiết bị đang dùng: Windows hoặc Android.
3. Cài đặt bản mới nhất theo hướng dẫn của IT.
4. Mở lại OpsHub và đăng nhập bằng tài khoản email nội bộ đã được cấp quyền.

> Nếu máy báo bản cài Windows chưa được tin cậy, hãy kiểm tra lại hướng dẫn
> triển khai chứng chỉ nội bộ trước khi cài.

## Đăng nhập

- Dùng email nội bộ đã đăng ký trong OpsHub.
- Nếu quên mật khẩu, chọn luồng quên mật khẩu trong màn hình đăng nhập.
- Nếu tài khoản chưa thấy showroom hoặc tính năng cần dùng, liên hệ quản trị
  viên để kiểm tra phân quyền.

## Các khu vực chính

| Khu vực | Dùng để làm gì |
| --- | --- |
| FIFO | Kiểm tra và sắp xếp hàng theo quy trình FIFO |
| BH / SC | Gửi ảnh và theo dõi bảo hành, sửa chữa |
| VietQR | Tạo QR chuyển khoản và theo dõi trạng thái thanh toán |
| Sao kê | Đối soát giao dịch ngân hàng theo quyền được cấp |
| Cấn trừ | Gửi, duyệt và hoàn tất yêu cầu cấn trừ |
| Góp ý | Gửi phản hồi về lỗi, vướng mắc hoặc đề xuất cải tiến |

## Hỗ trợ

- Bấm nút **Hỗ trợ** trên màn hình chính để mở QR hoặc link group Seatalk.
- Khi báo lỗi, gửi kèm thao tác vừa làm, thời điểm gặp lỗi và mã đơn nếu có.
- Không gửi mật khẩu, token, file cấu hình bí mật hoặc dữ liệu nhạy cảm lên
  group hỗ trợ.

## Thêm hình ảnh minh họa

Đặt ảnh vào thư mục `docs/help/assets/`, rồi chèn trong Markdown theo mẫu:

```markdown
![Mô tả ảnh cho người đọc](assets/ten-anh.png)
```

Ảnh nên là ảnh đã che dữ liệu nhạy cảm. Tên file nên dùng chữ thường, không dấu,
không khoảng trắng, ví dụ `dang-nhap.png` hoặc `sao-ke-bo-loc.png`.
