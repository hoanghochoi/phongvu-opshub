# Validation

## Automated

- `npx prisma format && npx prisma validate && npx prisma generate`
- Focused Nest tests cho ERP authorized request, PPM batch/cache, calculator,
  amount words và contract service/controller.
- `npm run build`
- Flutter tests cho JSON models, HTML/TSV escaping, provider state, route/access
  và layout `390x844`.
- `flutter analyze --no-pub`
- `flutter test --no-pub`
- `git diff --check`

### Kết quả local 2026-07-17

- Đạt: Prisma format/validate/generate, Nest build, 33 test trọng tâm và toàn bộ
  79 Nest suite / 760 test.
- Đạt: `flutter pub get`, `flutter analyze --no-pub`, focused guard/core/screen
  (28 test), toàn bộ Flutter (558 passed, 3 skipped), Windows release, web
  release và Android staging debug build.
- Đạt: đối chiếu API công khai `super_clipboard 0.9.1`; cách gọi
  `SystemClipboard`, `DataWriterItem`, `Formats.htmlText` và
  `Formats.plainText` khớp tài liệu package.
- Đạt: live PPM CLI qua `SalesReportErpService` dùng credential capture hiện
  hữu; SKU `250902982` trả `8%` (`vatRateBps=800`) tại terminal đã chốt.
- Đạt follow-up UI/Word: 29 focused core/screen/design-guard test khóa layout
  một cột, preview desktop 960px, Times New Roman 12pt, cột tiền căn giữa,
  căn lề ô, số tiền không bẻ dòng và đoạn `Bằng chữ` ngoài bảng.
- Follow-up CF_HTML khóa payload ở dạng fragment thuần, font trực tiếp trên
  từng text run và tỷ lệ cột `6/40/6/7/16/9/16`; vẫn loại `thead/th` để Word
  không đánh dấu hàng tiêu đề lặp lại.
- Đạt staging: workflow `29564482891` apply migration, deploy đúng SHA
  `708ba564` và vượt public health/version/manifest checks. User đã xác nhận
  rich table paste được vào Word Windows trước follow-up định dạng này.
- Chưa xác minh: migration up/rollback trên database scratch vì Docker Desktop
  Linux engine chưa chạy trong phiên local này.

## Integration and Manual

- Backend smoke SKU `250902982` trả `vatRateBps=800` tại terminal
  `49180_PRICE_0001`; thêm fixture 0%, 10% và KCT nếu provider trả code.
- Đơn có quantity > 1 chứng minh `finalSellPrice` là giá mỗi đơn vị và footer
  reconcile đúng.
- User khác không đọc được snapshot; bản hết hạn bị 404 và cron xóa idempotent.
- Paste trên Word Windows giữ 7 cột, màu header, border, dòng tổng và tiền chữ.
- Build Windows, web và Android trước staging proof.
- Cần recheck thủ công sau khi phát hành follow-up: Word Windows hiển thị đúng
  Times New Roman 12pt và cùng tỷ lệ cột trên cả tài liệu trắng lẫn file mẫu;
  đồng thời không lặp header khi qua trang, số tiền không bẻ dòng và đoạn
  `Bằng chữ` nằm ngoài bảng. Đơn ERP có quantity > 1 vẫn là fixture tích hợp
  cần bổ sung.
