# Flutter Implementation Rules For UI Redesign

## 1. Entry gate

Chỉ bắt đầu visual redesign implementation khi có:

- Linear implementation scope và acceptance criteria;
- exact approved Figma frame/revision;
- protected current behavior và affected consumers đã xác định;
- task worktree do `scripts/task-lifecycle.mjs start` tạo từ live
  `origin/staging`;
- validation plan phù hợp risk lane.

Restorative bug fix không đổi intended design có thể dùng approved behavior/
current source thay cho frame mới, nhưng phải ghi rõ căn cứ và proof.

## 2. Incremental migration

- Migrate theo shared foundation → component → screen; không rewrite toàn app.
- Screen chưa migrate tiếp tục dùng current theme/runtime contract.
- Không trộn typography/token mới và cũ tùy tiện trong cùng migrated surface.
- Giữ business logic, provider/service/API/permission ngoài scope không đổi.
- Không xóa/deprecate legacy component trước khi không còn consumer và có proof.

## 3. Shared theme and components

- Map target vào `AppColors`, `AppTextStyles`, `AppRadius`, `AppLayoutTokens`
  và `AppTheme`.
- Dùng/evolve shared widgets như `AppResponsiveContent`,
  `AppResponsiveScrollView`, `AppFormColumn`, shared buttons/inputs/state panels.
- Không hardcode color, typography, spacing, radius, shadow hoặc breakpoint.
- Material 3 là nền kỹ thuật, không phải visual authority.
- Không tạo feature-local primitive khi shared component có thể được mở rộng.

Be Vietnam Pro chỉ được bật qua approved foundation issue có assets, license,
fallback và platform proof. Không thêm network font runtime.

## 4. Responsive and platform

- Compact `<600`, medium `600–899`, expanded `900–1199`, wide `>=1200`.
- Dựa trên available width, không model thiết bị.
- Android và Windows là primary proof targets; web contract vẫn phải giữ.
- Desktop dùng bounded content width/density; mobile touch-first và safe area.
- Table/modal tràn hai chiều dùng shared two-axis scrolling contract.
- Platform-specific feature không được chạy flow trên platform unsupported.

## 5. Required UI behavior

- Implement approved loading, refreshing, empty, error/retry, offline, partial,
  permission/session, validation, disabled và pagination states khi áp dụng.
- Vietnamese-first copy, action-oriented; không lộ code/role/backend details.
- Date range dùng canonical shared picker; selector dùng shared combobox.
- Scan/search/submit input và primary actions giữ cùng hàng.
- Related flows giữ presentation model nhất quán; long modal giữ fixed context
  header và scrollable body.
- Dialog dismissal, dirty form guard, global selection và input context menu
  giữ theo `docs/product/ui-ux.md`.

## 6. Logging

Flow user-facing mới/thay đổi phải log start, success, failure và key branches
qua `AppLogger` với context đã sanitize: feature/source, scope/id/count/status/
duration khi phù hợp. Không log token, password, raw payload, scanned value,
email hoặc secret.

## 7. Design drift

Nếu approved Figma không thể implement an toàn:

1. Dừng phần bị ảnh hưởng.
2. Ghi blocker và technical evidence vào Linear.
3. Đề xuất option/trade-off.
4. Tạo Figma revision.
5. Chờ re-approval trước khi tiếp tục.

Không “sửa cho gần giống” trong code rồi để docs chạy theo sau.

## 8. Git workflow

Từ canonical clean `staging` worktree:

```powershell
node scripts/task-lifecycle.mjs start `
  --issue OPS-123 `
  --slug short-description `
  --worktree ..\opshub-ops-123
node scripts/task-lifecycle.mjs start `
  --issue OPS-123 `
  --slug short-description `
  --worktree ..\opshub-ops-123 --execute
```

- Branch phải là `codex/ops-123-short-description` từ exact live
  `origin/staging` SHA.
- Không commit trực tiếp lên `staging`/`main`; PR mặc định target `staging`.
- Không force push hoặc tự merge/promote protected branches.
- Sau merge chạy lifecycle `finish` theo release playbook trước task tiếp theo.

## 9. Verification

Tối thiểu cho code UI đã đổi:

```powershell
dart format --output=none --set-exit-if-changed <changed Dart files>
git diff --check
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
```

Thêm focused widget/unit/golden/visual proof theo behavior; layout change cần
screenshots hoặc observable smoke ở relevant widths/platforms. Normal/high-risk
work phải chạy affected-consumer proof. Không claim pass nếu command chưa chạy;
nếu blocked, nêu verified/unverified và residual risk.
