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
- Static-only production deploys and staging deploys publish `dist/help/` with
  the download static files.

## Validation

- Run `node scripts/build-help-site.mjs`.
- Check JavaScript syntax for `scripts/build-help-site.mjs` and
  `deploy/home-server/help.html`.
- Run the focused Home widget test.
- Run `flutter analyze --no-pub`.
- Run `git diff --check`.
