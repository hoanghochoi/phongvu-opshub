# Staff Help And Roadmap

## Intent

OpsHub provides a public staff help page so users can read setup guidance,
common workflow notes, and the current roadmap without requiring a feature
permission.

## Contract

- `GET /help` currently serves the public static help page while the Flutter
  cutover is still pending.
- `GET /help/` redirects to `/help`.
- `GET /api/help-content/public` exposes the runtime help snapshot from DB so
  the next cutover can read the same content source without rebuilding Flutter.
- Super Admin runtime APIs are:
  - `GET /api/admin/help-content/pages`
  - `POST /api/admin/help-content/pages`
  - `PATCH /api/admin/help-content/pages/:key`
  - `POST /api/admin/help-content/seed-from-docs`
- Help navigation is configured in `docs/help/navigation.json`.
- Help content is authored as Markdown under `docs/help/content/`.
- Help images are stored under `docs/help/assets/` and referenced from
  Markdown with `assets/<file-name>`.
- The help page renders the current user guide and roadmap tabs from the
  deployed Markdown files.
- Child pages under `Hướng dẫn sử dụng` are added by creating a Markdown file
  and adding it to the `children` array of the `guide` item in
  `docs/help/navigation.json`; `deploy/home-server/help.html` should not need
  editing for normal content changes.
- The download landing page exposes a visible `Hướng dẫn sử dụng` link to
  `/help`.
- The Flutter Home side menu exposes `Hướng dẫn sử dụng` and opens the public
  help page in an external browser.
- Super Admin sees `Quản lý hướng dẫn` inside `Quản trị`, can edit runtime
  Markdown content directly in app/web, and can restore runtime data from
  `docs/help/*` without redeploying the client app.
- Non-Super Admin must not see the editor entry and backend must reject direct
  runtime-editor API calls from non-Super Admin accounts.
- Opening the help page from the app logs start, success, launcher false, and
  failure states through `AppLogger` with sanitized URL host/path context.
- The help page is public. Do not publish passwords, tokens, authorization
  headers, raw logs, service-account data, customer-sensitive information, or
  internal roadmap details that should require authentication.

## Content Management

- Edit `docs/help/content/index.md` for usage guidance.
- Edit `docs/help/content/roadmap.md` for roadmap content.
- Edit `docs/help/navigation.json` for menu order, top-level pages, and child
  pages.
- Use `Quản trị -> Quản lý hướng dẫn` when the runtime copy must change
  immediately without waiting for a static help deploy.
- Use `Khôi phục từ docs` in that editor when runtime data needs to be rolled
  back to the current `docs/help/*` version.
- Add images to `docs/help/assets/`.
- Runtime image upload is not part of this batch. Images still follow the
  static `docs/help/assets/` path until a dedicated asset-upload rollout lands.
- Run `node scripts/build-help-site.mjs` before validating or deploying static
  help changes.
- See `docs/help/README.md` for the detailed maintenance runbook.

## Expected Proof

- `cd backend-nest`
- `npx prisma validate`
- `npx prisma generate`
- `npm run build`
- `npm test -- --runInBand src/help-content/help-content.service.spec.ts src/help-content/help-content.controller.spec.ts`
- `cd ..`
- `node scripts/build-help-site.mjs`
- JavaScript syntax checks for the build script and static help page when the
  static `/help` site is changed.
- `flutter analyze --no-pub`
- `flutter test --no-pub --reporter expanded test/admin_menu_screen_test.dart`
- `git diff --check`
