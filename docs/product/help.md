# Staff Help And Roadmap

## Intent

OpsHub provides a public staff help page so users can read setup guidance,
common workflow notes, and the current roadmap without requiring a feature
permission.

## Contract

- `GET /help` is the public Flutter help route and must stay readable when the
  user is logged out.
- `GET /help/` redirects to `/help`.
- `GET /api/help-content/public` is the runtime source that the Flutter help
  screen reads.
- Super Admin runtime APIs are:
  - `GET /api/admin/help-content/pages`
  - `POST /api/admin/help-content/pages`
  - `PATCH /api/admin/help-content/pages/:key`
  - `POST /api/admin/help-content/assets`
  - `POST /api/admin/help-content/seed-from-docs`
- Help navigation is configured in `docs/help/navigation.json`.
- Help content is authored as Markdown under `docs/help/content/`.
- Help images are stored under `docs/help/assets/` and referenced from
  Markdown with `assets/<file-name>`.
- The Flutter help screen renders published runtime pages, shows the current
  navigation tree in-app, and rewrites `assets/...` markdown images to
  `/help/assets/...`.
- Child pages under `Hướng dẫn sử dụng` are added by creating a Markdown file
  and adding it to the `children` array of the `guide` item in
  `docs/help/navigation.json`.
- The download landing page exposes a visible `Hướng dẫn` link to
  `/help`.
- The login screen exposes a visible `Hướng dẫn` action so staff can
  open the public help route before signing in.
- The Flutter shell side menu exposes `Hướng dẫn` under `Cấu hình` and opens
  the in-app `/help` route as the primary authenticated flow.
- Runtime help pages support 3 visibility modes:
  `Nháp`, `Public`, and `Private`. `Private` pages are returned only when the
  caller is already authenticated.
- The Flutter help screen always exposes a `Quay lại` action. When the route
  has navigation history it pops back; otherwise it falls back to `/login` for
  logged-out sessions and `/home` for authenticated sessions.
- Super Admin sees `Quản lý hướng dẫn` inside `Quản trị`, can edit runtime
  Markdown content directly in app/web, and can restore runtime data from
  `docs/help/*` without redeploying the client app.
- Super Admin can upload help images from the runtime editor. Uploaded files
  are stored under public `/uploads/help-content/...`, and the editor inserts a
  ready-to-use Markdown image snippet into the current content.
- Runtime help auto-seeds from `docs/help/*` when DB is empty. When all current
  runtime pages still come from docs, the backend auto-syncs them from
  `docs/help/*` on the next load. Once a Super Admin edits a runtime page, that
  page leaves the docs-managed path until `Khôi phục từ docs` is used.
- Production `help-content` static-only deploys still publish `/help/assets/*`
  and sync `docs/help/*` onto the current release as the short rollback/source
  path for runtime help. They do not rebuild app packages or change
  app-version metadata.
- Non-Super Admin must not see the editor entry and backend must reject direct
  runtime-editor API calls from non-Super Admin accounts.
- Opening the help page from the app logs route-open states through
  `AppLogger`, and the runtime `HelpScreen` logs load/select/external-link
  branches with sanitized context.
- The help page is public. Do not publish passwords, tokens, authorization
  headers, raw logs, service-account data, customer-sensitive information, or
  internal roadmap details that should require authentication.

## Content Management

- Edit `docs/help/content/index.md` for usage guidance.
- Edit `docs/help/content/roadmap.md` for roadmap content.
- Edit `docs/help/navigation.json` for menu order, top-level pages, and child
  pages.
- Use `Quản trị -> Quản lý hướng dẫn` when the runtime copy must change
  immediately.
- Use `Khôi phục từ docs` when the runtime copy needs to realign with the
  current `docs/help/*` source after a rollback or `help-content` deploy.
- Add images to `docs/help/assets/`.
- Use `Tải ảnh và chèn` inside `Quản lý hướng dẫn` when a Super Admin needs a
  public image URL quickly without touching the static repo assets first.
- `docs/help/assets/` remains the static source path for hand-authored content
  and `help-content` deploys; runtime uploads are a parallel public path for
  editor-driven updates.
- Run `node scripts/build-help-site.mjs` before validating or deploying
  `docs/help` changes so the asset bundle stays consistent.
- See `docs/help/README.md` for the detailed maintenance runbook.

## Expected Proof

- `cd backend-nest`
- `npx prisma validate`
- `npx prisma generate`
- `npm run build`
- `npm test -- --runInBand src/help-content/help-content.service.spec.ts src/help-content/help-content.controller.spec.ts`
- `cd ..`
- `node scripts/build-help-site.mjs`
- `flutter analyze --no-pub`
- `flutter test --no-pub --reporter expanded test/admin_menu_screen_test.dart test/app_shell_route_viewport_test.dart test/auth_pre_shell_redesign_test.dart test/help_screen_test.dart`
- `flutter build web --debug --no-pub`
- `git diff --check`
