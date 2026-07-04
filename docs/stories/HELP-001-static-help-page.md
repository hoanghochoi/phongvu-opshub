# HELP-001 Public Help Route

## Goal

Give staff a public `/help` page that can show usage guidance, roadmap content,
and images while keeping content editable by hand in Markdown.

## Contract

- `GET /help` serves the public Flutter help route.
- `GET /help/` redirects to `/help`.
- The page reads `GET /api/help-content/public` for runtime navigation and
  markdown content.
- Images referenced as `assets/<file>` are served from `/help/assets/<file>`.
- New child pages under `Hướng dẫn sử dụng` require only a Markdown file plus a
  `children` entry in `docs/help/navigation.json`.
- `docs/help/README.md` documents how to edit content, add images, build, test,
  and deploy the route.
- `/download` includes a visible `Hướng dẫn sử dụng` link to `/help`.
- The Flutter account menu includes `Hướng dẫn sử dụng` and opens the in-app
  help route with `AppLogger` coverage.
- `GET /api/help-content/public` mirrors the runtime help pages from DB, and
  Super Admin can edit that runtime copy through `/admin/help-content` plus the
  `/api/admin/help-content/*` endpoints.
- Runtime help auto-seeds from `docs/help/*` when DB is empty. When all current
  runtime pages still come from docs, the backend auto-syncs them from
  `docs/help/*` on the next load. Admin-edited runtime pages stop auto-syncing
  until `Khôi phục từ docs` is used.
- The `help-content` branch is the production content source for `docs/help/*`
  and `/help/assets/*`.
- Pushing the `help-content` branch runs a production static-only deploy that
  publishes `dist/help/`, syncs `docs/help/*` onto the live release as the
  rollback/source path for runtime help, and does not rebuild app packages or
  change app-version metadata.
- Full production deploys from `main` load `docs/help` from `origin/help-content`
  before building the help asset bundle when that branch exists.
- Manual static-only production deploys and staging deploys also publish
  `dist/help/` with the download static files.
- Runtime image upload is deferred; image references still rely on
  `docs/help/assets/` until a dedicated upload flow is shipped.

## Validation

- Run `npx prisma validate`.
- Run `npx prisma generate`.
- Run `npm run build` in `backend-nest/`.
- Run `npm test -- --runInBand src/help-content/help-content.service.spec.ts src/help-content/help-content.controller.spec.ts` in `backend-nest/`.
- Run `node scripts/build-help-site.mjs`.
- Run the focused admin/help widget tests.
- Run `flutter analyze --no-pub`.
- Run `flutter build web --debug --no-pub`.
- Run `git diff --check`.
