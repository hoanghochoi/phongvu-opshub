# HELP-001 Static Help Page

## Goal

Give staff a public `/help` page that can show usage guidance, roadmap content,
and images while keeping content editable by hand in Markdown.

## Contract

- `GET /help` serves the static help page.
- `GET /help/` redirects to `/help`.
- The page fetches Markdown from `/help/content/index.md` and
  `/help/content/roadmap.md`.
- The page fetches `/help/navigation.json` for menu order and parent/child
  page grouping.
- Images referenced as `assets/<file>` are served from `/help/assets/<file>`.
- New child pages under `Hướng dẫn sử dụng` require only a Markdown file plus a
  `children` entry in `docs/help/navigation.json`.
- `docs/help/README.md` documents how to edit content, add images, build, test,
  and deploy the page.
- `/download` includes a visible `Hướng dẫn sử dụng` link to `/help`.
- The Flutter Home side menu includes `Hướng dẫn sử dụng` and opens the help
  page externally with `AppLogger` coverage.
- `GET /api/help-content/public` mirrors the runtime help pages from DB, and
  Super Admin can edit that runtime copy through `/admin/help-content` plus the
  `/api/admin/help-content/*` endpoints.
- The public `/help` page remains static in this batch; runtime DB content is
  the next-step source for the eventual Flutter cutover.
- The `help-content` branch is the production content source for `docs/help`.
- Pushing the `help-content` branch runs a production static-only deploy that
  publishes `dist/help/` with the download static files and does not rebuild app
  packages or change app-version metadata.
- Full production deploys from `main` load `docs/help` from `origin/help-content`
  before building the help site when that branch exists.
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
- Check JavaScript syntax for `scripts/build-help-site.mjs` and
  `deploy/home-server/help.html`.
- Run the focused admin menu widget test.
- Run `flutter analyze --no-pub`.
- Run `git diff --check`.
