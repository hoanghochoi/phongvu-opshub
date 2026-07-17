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
- Paste thật vào Word Windows, đơn ERP có quantity > 1 và staging API/UI smoke
  vẫn là proof sau deploy; live PPM CLI hiện đã đạt ở local.
