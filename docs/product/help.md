# Staff Help And Roadmap

## Intent

OpsHub provides a public staff help page so users can read setup guidance,
common workflow notes, and the current roadmap without requiring a feature
permission.

## Contract

- `GET /help` serves the public help page.
- `GET /help/` redirects to `/help`.
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
- Add images to `docs/help/assets/`.
- Run `node scripts/build-help-site.mjs` before validating or deploying static
  help changes.
- See `docs/help/README.md` for the detailed maintenance runbook.

## Expected Proof

- `node scripts/build-help-site.mjs`
- JavaScript syntax checks for the build script and static help page.
- `flutter analyze --no-pub`
- Focused Home widget test for the side-menu entry.
- `git diff --check`
