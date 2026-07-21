# Git Branch And Production Promotion Playbook

## Mục tiêu và bất biến

- `staging` là branch tích hợp/QA; `main` là production.
- Luồng feature mặc định là task branch -> PR -> squash merge vào `staging`.
- Direct push vào `staging` hoặc `main` chỉ hợp lệ khi Đại Ca ra lệnh rõ trong
  task hiện tại, nêu đúng hành động và branch đích.
- Quyền thực hiện không bỏ qua clean worktree, scope review, CI, staging deploy,
  QA, release lock hoặc fast-forward.
- Không force push. `main` chỉ nhận đúng SHA của `origin/staging`; ngay sau
  promotion, hai remote ref phải cùng SHA.

Các câu `làm tiếp`, `release nhé`, `xử lý phần còn lại` không phải authorization
để direct push. Ví dụ đủ rõ:

```text
Push branch OPS-142-fix-date-picker trực tiếp vào staging.
Promote origin/staging vào main ngay bây giờ.
```

## Báo cáo bắt buộc trước direct push

```text
Nguồn: <branch hoặc SHA>
Đích: <staging hoặc main>
SHA hiện tại: <sha>
Kiểm tra: clean scope=<pass/fail>, CI=<pass/fail>, QA=<pass/fail>, fast-forward=<pass/fail>
Hành động: sẽ push trực tiếp theo lệnh explicit của anh
```

Nếu một check fail hoặc source SHA đổi, dừng. Không xin phép kiểu “gộp chung cho
tiện”; release mà tiện quá thường là lúc rollback bắt đầu tập cardio.

## Feature mặc định

1. Tạo một Linear issue, một Codex task, một worktree, một task branch và một PR.
2. Branch phải chứa Linear ID và bắt đầu từ `origin/staging` mới nhất:

   ```powershell
   git fetch origin
   git worktree add ..\opshub-ops-142 -b codex/ops-142-fix-date-picker origin/staging
   Set-Location ..\opshub-ops-142
   ```

3. Chạy proof theo vùng thay đổi: Flutter (`flutter analyze`, `flutter test`),
   NestJS (`npm run build`, `npm test -- --runInBand`), Go (`go test ./...`) và
   `git diff --check`.
4. `.github/workflows/release-guard-pr.yml` phải chạy trên mọi PR vào `staging`
   hoặc `main`. Ruleset chỉ được require check `Release guard` sau khi check đã
   xuất hiện và pass ít nhất một lần trên GitHub.
5. PR title: `[OPS-142] Fix date picker`; base: `staging`; body dùng
   `Part of OPS-142`. Dùng `Fixes OPS-142` chỉ khi production release thực sự
   dự kiến đóng issue.
6. Feature PR dùng squash-and-merge. Merge vào `staging` chưa phải `Done`.

## Ngoại lệ: direct push vào staging

Chỉ dùng cho hotfix/revert/recovery/cấu hình vận hành hoặc khi Đại Ca ghi rõ
feature nào được bỏ PR. Trình tự:

1. Fetch và xác định source branch/SHA chính xác.
2. Xác minh worktree sạch, diff không ngoài phạm vi, proof liên quan đã pass.
3. Báo block source/target/checks ở trên và nêu tác động: mất PR review, không có
   squash commit tự động, Linear PR automation có thể không chạy.
4. Chỉ sau lệnh explicit mới push đúng ref `staging`; không force.
5. Theo dõi `Deploy OpsHub Staging`, chờ QA của Đại Ca và giữ issue ở
   `Ready for QA`/`Testing`, không `Done`.

## Promotion staging -> main

Điều kiện bắt buộc:

- feature đã vào `staging`; staging deploy thành công;
- Đại Ca đã QA và ra lệnh `Promote origin/staging vào main ngay bây giờ`;
- release window khóa, không có merge mới;
- staging SHA được ghi chính xác; CI/check runs của SHA đó đều đạt;
- `origin/main` là ancestor của `origin/staging`.

Dry-run cục bộ (không push):

```powershell
git fetch origin main staging
$stagingSha = (git rev-parse origin/staging).Trim()
node scripts/promote-production.mjs `
  --expected-sha $stagingSha `
  --ci-confirmed --qa-confirmed --release-window-locked
```

Production dùng workflow `Promote OpsHub Production` (`workflow_dispatch`):

1. Nhập đúng staging SHA đã QA.
2. Nhập `QA-APPROVED`.
3. Nhập `PROMOTE ORIGIN/STAGING TO MAIN`.
4. Approve job trong environment `production`.
5. Workflow dùng GitHub App token, kiểm tra GitHub checks/statuses, chạy guard
   với `--execute`, push non-force và fetch lại để chứng minh hai SHA bằng nhau.
6. Push bằng GitHub App token kích hoạt `Deploy OpsHub` trên `main`; không thay
   bằng `GITHUB_TOKEN`, vì push từ token mặc định không tạo downstream workflow.

Bootstrap lần đầu là ngoại lệ có thứ tự: workflow chỉ xuất hiện trong danh sách
dispatch sau khi file đã có trên default branch `main`. Vì vậy hãy cài App và
secrets trước, merge PR này vào `staging`, deploy/QA, rồi chỉ sau lệnh promote
explicit của Đại Ca mới chạy guard cục bộ với `--execute` bằng credential đang
được phép fast-forward `main`. Xác minh production deploy xong mới bật ruleset
require-PR/restrict-update với release App là bypass duy nhất. Các lần sau dùng
workflow dispatch; không lặp lại bootstrap local.

Nếu staging đổi sau push, guard báo trạng thái không đồng nhất và dừng; không tự
rollback Git history. Khóa release, đánh giá commit mới, rồi chọn promote SHA mới
hoặc tạo revert qua `staging`.

## GitHub App, Rulesets và production environment

Tạo GitHub App riêng (ví dụ `opshub-release-bot`), chỉ cài trên repo này, với
quyền tối thiểu `Contents: write`, `Checks: read`, `Commit statuses: read`.
Lưu App ID vào repository variable `OPSHUB_RELEASE_APP_ID` và private key vào
environment secret `OPSHUB_RELEASE_APP_PRIVATE_KEY`. Không dùng PAT cá nhân.

Rulesets đích:

- Cả `staging` và `main`: chặn delete và non-fast-forward.
- `staging`: require PR, required checks, tối thiểu một approval; release App là
  bypass actor cho direct-push ngoại lệ.
- `main`: restrict updates/require PR; chỉ release App được bypass để đưa
  `origin/staging` lên `main`.

Không bật require-PR/restrict-updates trước khi App đã được cài và thêm vào bypass
list; nếu không workflow promotion sẽ tự khóa cửa rồi để chìa khóa bên trong.
Audit read-only:

```powershell
gh api repos/hoanghochoi/phongvu-opshub/rulesets
gh api repos/hoanghochoi/phongvu-opshub/environments/production
```

Environment `production` phải giới hạn branch `main` và `help-content`, có
required reviewer, và nên tắt admin bypass. Workflow promotion cũng dùng
environment này, vì vậy token/secret chỉ xuất hiện sau approval.

## Linear lifecycle

| Sự kiện | Status |
| --- | --- |
| Issue mới | Todo |
| Codex bắt đầu | In Progress |
| PR vào `staging` mở | In Review |
| PR merge vào `staging` | Ready for QA |
| Đang kiểm thử staging | Testing |
| QA đạt | Ready for Release |
| Đại Ca ra lệnh promote | Releasing |
| Production deploy đạt | Done |

Không chuyển `Done` vì task branch đã push, PR đã merge, staging đã deploy, QA
đã approve hoặc release PR đã mở. Nếu workspace chưa có các status trên, admin
phải tạo chúng trước khi bật automation theo target branch.

## Hotfix, feature flag và rollback

- Code chưa sẵn sàng không vào `staging`, trừ khi bị khóa bằng feature flag,
  draft PR, route ẩn hoặc integration branch có tài liệu.
- Hotfix: `main` -> hotfix branch -> PR/explicit exception vào `staging` -> test
  -> Đại Ca ra lệnh promote -> `main`.
- Rollback: tạo revert branch từ commit đã phát hành -> đưa revert vào `staging`
  -> deploy/QA -> Đại Ca ra lệnh promote. Không rewrite `main`.

## Proof và smoke định kỳ

```powershell
node scripts/test-git-release-workflow.mjs
python -c "import glob,yaml; [yaml.safe_load(open(p,encoding='utf-8')) for p in glob.glob('.github/workflows/*.yml')]; print('workflow yaml: PASS')"
git diff --check
```

Test bắt buộc chứng minh: dry-run thành công không đổi ref, execute fixture đưa
`main == staging`, và các case diverged history, stale SHA, thiếu QA, dirty
worktree hoặc CI fail đều bị chặn.
