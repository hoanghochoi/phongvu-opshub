# Validation

## Automated

- `npx prisma format && npx prisma validate && npx prisma generate`
- Focused Nest tests cho ERP authorized request, mapping giá shipment (khác
  capture, thiếu/mơ hồ, không fallback), PPM live batch/no-cache, `uomName`,
  calculator mixed-tax, amount words và contract service/controller.
- `npm run build`
- Flutter tests cho JSON models, HTML/TSV escaping, cột `lineAfterVat`/nhãn đã
  VAT, provider state, route/access và layout `390x844`.
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

### Follow-up OPS-20 local 2026-07-24

- Đạt: PPM live batch/no-cache, stale 8% -> live 0%, không đọc/ghi legacy
  Redis tax cache, ERP `uomName`, SKU `220909037` 0%, mixed 0%/8%, quantity > 1,
  snapshot, quote conflict, history/access và token refresh trong 6 focused Nest
  suite / 43 test.
- Đạt: Contract Appendix model/provider/UI/HTML/TSV clipboard trong 10 focused
  Flutter test; cột chưa VAT và ba dòng tổng dùng đúng kết quả từng sản phẩm.
- Đạt: Nest build; full Nest 89 suite / 873 test; `flutter analyze --no-pub`;
  full Flutter 611 passed / 3 skipped; `git diff --check`.
- Local live PPM chưa chạy do môi trường máy không có ERP credential. Live SKU
  `220909037` và order `uomName` phải được xác minh trên staging sau deploy trước
  khi chuyển `Ready for Release`.

### OPS-32 local 2026-07-27

- Đạt: fixture capture/shipment khác giá, quantity > 1, strict mapping theo
  khóa ổn định, shipment thiếu/mơ hồ/giá không hợp lệ fail-closed, không
  fallback về các giá cũ; Sales Report lookup vẫn dùng giá capture.
- Đạt: preview, save, quoteVersion và snapshot cùng dùng lookup shipment;
  Flutter preview + HTML/TSV clipboard dùng `lineAfterVat` và nhãn đã VAT.
- Đạt: Prisma validate, Nest build, focused Nest 3 suite / 33 test, full Nest
  90 suite / 896 test, focused Flutter 10 test và `flutter analyze --no-pub`.
- Chưa xanh toàn bộ Flutter: run full đạt 615 pass / 3 skip trước một failure
  timing ngoài phạm vi ở `sales_report_hub_test.dart`; rerun riêng cùng suite
  đạt 25 test. Staging smoke ERP/Word vẫn là gate trước `Ready for Release`.

### OPS-209 implementation gate

- ERP fixture `quantity=2`, shipment `finalSellPrice=250`, `rowTotal=499` phải
  trả `lineAfterVat=499`; missing/negative/fractional/unsafe row total,
  shipment thiếu hoặc mơ hồ phải fail-closed và không fallback.
- Multi-order request phải trim/deduplicate tối đa 10 mã, dừng atomic khi một
  đơn lỗi, giới hạn 200 source lines, deduplicate PPM trên toàn batch và giữ
  thứ tự user nhập. Dòng tương thích được gộp và cộng `rowTotal`; khác giá,
  thuế hoặc đơn vị không gộp.
- Migration fresh/upgrade/rollback scratch, legacy snapshot read/copy,
  history search theo mọi source order, quote conflict khi rowTotal/tập đơn
  đổi và Sales Report capture-price regression đều bắt buộc.
- Flutter state phải prove add/remove/duplicate/max/no-API-before-fetch,
  locked/reset flow; visual interaction chỉ được prove sau approved Figma node
  map ở compact/medium/expanded/wide.
- Staging smoke phải có rowTotal khác tích finalSellPrice, hai đơn, save/refetch,
  history và Word Windows paste; proof ghi vào OPS-209 trước status transition.
- Local OPS-209 proof on 2026-08-19: focused Nest 2 suites/18 tests, full Nest
  124 suites (1,327 passed, 6 skipped), Nest build, focused Flutter 14 tests,
  Flutter feature analyzer, Windows debug, Web release, and explicit Android
  staging debug all pass. Full Flutter is rerunning after the final provider
  adjustment; Docker/PostgreSQL migration rehearsal, staging smoke, and the
  approved Figma/node-map visual gate remain open.

## Integration and Manual

- Backend smoke SKU `220909037` trả `vatRateBps=0` và SKU `250902982` trả
  `vatRateBps=800` tại terminal `49180_PRICE_0001`; thêm fixture 10% và KCT nếu
  provider trả code.
- Hai lookup liên tiếp phải gọi PPM hai lần; fixture stale 8% rồi live 0% phải
  trả kết quả 0% ở lần sau và không chạm Redis tax cache.
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
