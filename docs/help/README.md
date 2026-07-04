# Hướng dẫn thiết kế và quản lý trang /help

Public `/help` hiện là route Flutter đọc runtime help qua
`/api/help-content/public`. Bộ `docs/help/*` vẫn là nguồn authoring, asset, và
rollback/source path ngắn hạn cho runtime help.

## 1. Cấu trúc thư mục

```text
docs/help/
  README.md
  navigation.json
  content/
    index.md
    getting-started.md
    roadmap.md
  assets/
    dang-nhap.png
    sao-ke-bo-loc.png
deploy/home-server/help.html
scripts/build-help-site.mjs
```

- `navigation.json`: cấu hình menu cha/con của runtime help.
- `content/*.md`: từng trang nội dung Markdown dùng để seed/restore runtime.
- `assets/*`: ảnh minh họa dùng trong Markdown, được serve qua
  `/help/assets/*`.
- `help.html`: shell authoring/rollback cho bundle tĩnh, không còn là luồng
  public chính.
- `build-help-site.mjs`: build `docs/help/` thành `dist/help/` để kiểm tra
  asset path và publish bundle tĩnh hỗ trợ rollback.

## 2. Cách soạn file Markdown

Mỗi file Markdown nên bắt đầu bằng một tiêu đề cấp 1:

```markdown
# Tên trang
```

Dùng tiêu đề cấp 2 cho các phần lớn:

```markdown
## Khi nào dùng tính năng này
## Các bước thao tác
## Lỗi thường gặp
```

Dùng danh sách số khi có thứ tự thao tác:

```markdown
1. Mở màn hình chính.
2. Chọn tính năng cần dùng.
3. Kiểm tra thông tin trước khi gửi.
```

Dùng bullet khi không cần thứ tự:

```markdown
- Không gửi mật khẩu lên group hỗ trợ.
- Ảnh minh họa phải che dữ liệu nhạy cảm.
- Nội dung nên viết ngắn, rõ việc cần làm.
```

Dùng bảng cho nội dung so sánh:

```markdown
| Trường hợp | Cách xử lý |
| --- | --- |
| Quên mật khẩu | Dùng luồng quên mật khẩu |
| Chưa thấy showroom | Liên hệ quản trị viên |
```

Dùng cảnh báo khi cần nhấn mạnh:

```markdown
> Không đưa token, mật khẩu, ảnh chứa dữ liệu khách hàng hoặc file cấu hình bí
> mật lên trang help.
```

Dùng code inline cho đường dẫn, lệnh, tên file:

```markdown
Sửa file `docs/help/navigation.json`, sau đó chạy `node scripts/build-help-site.mjs`.
```

## 3. Cách thêm ảnh

1. Đặt ảnh vào `docs/help/assets/`.
2. Đặt tên file viết thường, không dấu, không khoảng trắng.
3. Chèn ảnh trong Markdown bằng đường dẫn `assets/<ten-file>`.

Ví dụ:

```markdown
![Màn hình đăng nhập](assets/dang-nhap.png)
```

Quy tắc ảnh:

- Dùng `.png` cho ảnh chụp màn hình.
- Dùng `.jpg` cho ảnh chụp từ camera.
- Cắt ảnh vào đúng vùng cần hướng dẫn.
- Che dữ liệu nhạy cảm trước khi đưa vào repo.
- Luôn viết alt text trong `![...]` để người đọc hiểu ảnh nói gì.

## 4. Cách thêm mục con dưới Hướng dẫn sử dụng

Ví dụ muốn thêm mục con `VietQR` dưới `Hướng dẫn sử dụng`.

Bước 1: tạo file Markdown mới:

```text
docs/help/content/vietqr.md
```

Nội dung mẫu:

```markdown
# VietQR

## Khi nào dùng

Dùng VietQR khi cần tạo mã chuyển khoản cho đơn hàng.

## Các bước thao tác

1. Mở tính năng VietQR.
2. Nhập hoặc quét mã đơn.
3. Kiểm tra số tiền và nội dung chuyển khoản.
4. Gửi QR cho khách.
```

Bước 2: mở `docs/help/navigation.json`, thêm item vào `children` của
`guide`:

```json
{
  "key": "guide",
  "title": "Hướng dẫn sử dụng",
  "file": "index.md",
  "children": [
    {
      "key": "getting-started",
      "title": "Bắt đầu sử dụng",
      "file": "getting-started.md"
    },
    {
      "key": "vietqr",
      "title": "VietQR",
      "file": "vietqr.md"
    }
  ]
}
```

Bước 3: build để kiểm tra:

```powershell
node scripts/build-help-site.mjs
```

Nếu file Markdown hoặc ảnh bị thiếu, script sẽ báo lỗi.

## 5. Cách thêm một mục ngang hàng với Roadmap

Ví dụ muốn thêm mục `FAQ` ngang hàng với `Hướng dẫn sử dụng` và `Roadmap`.

Bước 1: tạo file:

```text
docs/help/content/faq.md
```

Bước 2: thêm item mới vào mảng ngoài cùng của `navigation.json`:

```json
[
  {
    "key": "guide",
    "title": "Hướng dẫn sử dụng",
    "file": "index.md",
    "children": []
  },
  {
    "key": "faq",
    "title": "FAQ",
    "file": "faq.md"
  },
  {
    "key": "roadmap",
    "title": "Roadmap",
    "file": "roadmap.md"
  }
]
```

## 6. Quy tắc đặt key và tên file

`key` dùng cho URL hash, ví dụ `/help#vietqr`.

Quy tắc:

- Chỉ dùng chữ thường, số và dấu gạch ngang.
- Không dùng dấu tiếng Việt.
- Không dùng khoảng trắng.
- Mỗi `key` phải là duy nhất.

Đúng:

```json
{ "key": "sao-ke", "title": "Sao kê", "file": "sao-ke.md" }
```

Sai:

```json
{ "key": "Sao Kê", "title": "Sao kê", "file": "Sao kê.md" }
```

Tên file Markdown cũng nên dùng kebab-case:

```text
sao-ke.md
can-tru.md
bao-hanh.md
```

## 7. Mẫu bố cục cho một trang hướng dẫn

Nên dùng bố cục này để nhân viên đọc nhanh:

```markdown
# Tên tính năng

## Khi nào dùng

Viết 1-2 câu nói rõ tính năng dùng trong trường hợp nào.

## Ai được dùng

- Nhân viên showroom
- Kế toán
- Quản trị viên

## Các bước thao tác

1. Bước đầu tiên.
2. Bước tiếp theo.
3. Kiểm tra lại trước khi gửi.

## Lỗi thường gặp

| Lỗi | Cách xử lý |
| --- | --- |
| Không thấy tính năng | Kiểm tra phân quyền với quản trị viên |
| Không gửi được dữ liệu | Kiểm tra mạng và thử lại |

## Cần hỗ trợ

Bấm nút **Hỗ trợ** trên màn hình chính và gửi thông tin cần thiết.
```

## 8. Nguyên tắc viết nội dung

- Viết tiếng Việt trước, dễ hiểu với nhân viên vận hành.
- Viết theo hành động: mở gì, bấm gì, kiểm tra gì.
- Tránh ghi thuật ngữ nội bộ như `FIN_ACC`, `SUPER_ADMIN`, policy key hoặc lỗi
  kỹ thuật nếu người dùng không cần biết.
- Mỗi đoạn nên ngắn, khoảng 2-4 dòng.
- Một trang dài thì tách thành nhiều mục con.
- Roadmap chỉ nên ghi nội dung có thể công khai cho nhân viên.

## 9. Xem thử local

### 9.1. Kiểm tra bundle authoring và asset path

```powershell
node scripts/build-help-site.mjs
python -m http.server 4173 -d dist
```

Mở:

```text
http://localhost:4173/help/
http://localhost:4173/help/#guide
http://localhost:4173/help/#getting-started
http://localhost:4173/help/#roadmap
```

Luồng này chỉ để kiểm tra `docs/help/*` và asset bundle, không phải public
route thật đang chạy trong app.

### 9.2. Kiểm tra public route Flutter

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000/api
```

Sau đó mở `/help` trong app/web và xác nhận nội dung đọc được từ
`/api/help-content/public`.

## 10. Deploy riêng trang /help

Workflow production và staging vẫn build `docs/help/*` bằng:

```bash
node scripts/build-help-site.mjs
```

Nhưng public `/help` bây giờ là route Flutter đọc runtime DB/API, nên cần hiểu
đúng 2 lớp:

1. `docs/help/*` là source/asset/rollback path.
2. Runtime help trong DB là nội dung public mà staff thật sự nhìn thấy.

`help-content` vẫn là nhánh source chính cho `docs/help/*`. Push nhánh này sẽ
chạy production static-only deploy, chỉ refresh `/download`, `/help/assets/*`,
bundle `dist/help/`, và sync `docs/help/*` vào release đang chạy; không rebuild
APK, Windows installer, backend image hoặc app-version metadata.

Nếu runtime help hiện vẫn hoàn toàn bám docs, backend sẽ auto-sync nội dung mới
ở request kế tiếp. Nếu đã từng chỉnh tay trong `Quản lý hướng dẫn`, dùng nút
`Khôi phục từ docs` để kéo source branch về lại public runtime.

### 10.1. Tạo nhánh lần đầu

Repo hiện tại đã có `origin/help-content`. Chỉ dùng bước này khi clone mới mà
local chưa có nhánh:

```bash
git fetch origin help-content
git switch --track origin/help-content
```

Nếu cần tạo lại từ đầu trong repo khác:

```bash
git switch staging
git pull --ff-only origin staging
git switch -c help-content
git push -u origin help-content
```

### 10.2. Luồng sửa nội dung hằng ngày

```bash
git switch help-content
git pull --ff-only origin help-content

# sua docs/help/content/*, docs/help/navigation.json, docs/help/assets/*
node scripts/build-help-site.mjs
git diff --check

git add docs/help
git commit -m "docs(help): update help content"
git push origin help-content
```

Sau khi push, GitHub Actions `Deploy OpsHub` sẽ tự chạy job
`deploy_download_static`. Các job `build_android`, `build_windows`, và full
`deploy` phải ở trạng thái `skipped` đối với branch `help-content`.

Sau deploy:

- Nếu runtime help chưa từng bị chỉnh tay trong admin, public `/help` sẽ tự lấy
  nội dung docs mới ở request kế tiếp.
- Nếu runtime help đã bị chỉnh tay, mở `Quản trị -> Quản lý hướng dẫn` và bấm
  `Khôi phục từ docs` để realign với `help-content`.

Theo dõi run:

```bash
gh run list --workflow deploy-opshub.yml --branch help-content --limit 1
gh run watch <run-id>
```

Nếu cần chạy lại bằng tay, dispatch production workflow với
`skip_client_build=true` từ chính nhánh `help-content`:

```bash
gh workflow run deploy-opshub.yml --ref help-content -f skip_client_build=true
```

### 10.3. Smoke sau deploy

```bash
curl -fsSI https://opshub.hoanghochoi.com/help
curl -fsS https://opshub.hoanghochoi.com/api/help-content/public
curl -fsS "https://opshub.hoanghochoi.com/api/app-version?platform=android"
```

Kết quả mong muốn:

- `/help` trả `200 OK`.
- `/api/help-content/public` trả về JSON có `pages`.
- `/app-version` không đổi chỉ vì deploy help; release notes/version vẫn là bản
  app production hiện tại.

### 10.4. Lưu ý an toàn

- Chỉ stage `docs/help` khi chỉ sửa nội dung hướng dẫn.
- Không sửa `lib/`, `backend-nest/`, workflow, hoặc file app trong nhánh
  `help-content` nếu mục tiêu chỉ là cập nhật nội dung.
- Không push `main` chỉ để sửa nội dung help; push `main` là đường deploy app
  production đầy đủ.
- Nếu Actions báo `Branch "help-content" is not allowed to deploy to
  production`, kiểm tra GitHub Environment `production` và thêm
  `help-content` vào deployment branch policy.

## 11. Checklist trước khi báo xong

- `navigation.json` hợp lệ JSON.
- Mỗi item trong menu có `key`, `title`, `file`.
- File Markdown khai báo trong menu tồn tại trong `docs/help/content/`.
- Ảnh trong Markdown tồn tại trong `docs/help/assets/`.
- Không có ảnh hoặc nội dung lộ dữ liệu nhạy cảm.
- `node scripts/build-help-site.mjs` chạy thành công.
- `git diff --check` không báo lỗi whitespace.
- `/download` vẫn có nút `Hướng dẫn sử dụng`.
- Menu app vẫn có mục `Hướng dẫn sử dụng`.
- Nếu có runtime chỉnh tay trước đó, đã xác nhận có cần `Khôi phục từ docs`
  hay không.
