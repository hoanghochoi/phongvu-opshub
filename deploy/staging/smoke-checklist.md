# OpsHub Staging Smoke Checklist

Use this checklist after the manual staging workflow succeeds.

## Server checks

- `ssh mementoamoris` resolves to `100.127.127.89`.
- `sudo ufw status verbose` has no public `22`, `80`, or `443` allow rule.
- `systemctl is-active cloudflared-opshub-staging` returns `active`.
- `curl -fsS https://staging.phongvu.work/health` returns `ok`.
- `curl -fsS https://api-staging.phongvu.work/v1/health` returns backend health JSON.
- `curl -fsS https://api-staging.phongvu.work/v1/app-version?platform=android` returns staging metadata.
- `curl -fsS https://staging.phongvu.work/download` returns the public staging download landing page.
- `curl -fsS https://staging.phongvu.work/downloads/latest.json` contains only staging URLs.
- Direct-origin trailing-slash contract, run on `mementoamoris` with the staging
  Host header: `/download/` returns 308 with exactly `Location: /download`, and
  `/help/` returns 308 with exactly `Location: /help`.
- Direct-origin canonical `/download` and `/help` each return content with 200
  and no redirect loop. These origin checks are separate from the public
  public download-page check; do not weaken the route/content check to run them.

  ```bash
  curl -sS -o /dev/null -D - -H 'Host: staging.phongvu.work' http://127.0.0.1:8090/download/
  curl -sS -o /dev/null -D - -H 'Host: staging.phongvu.work' http://127.0.0.1:8090/help/
  curl -sS -o /dev/null -D - -H 'Host: staging.phongvu.work' http://127.0.0.1:8090/download
  curl -sS -o /dev/null -D - -H 'Host: staging.phongvu.work' http://127.0.0.1:8090/help
  ```
- The response carries enforced `Content-Security-Policy` (not
  `Content-Security-Policy-Report-Only`) and the normal security headers.
- Runtime env has ERP cache/status sync, VietQR auto-reconcile, MAP global sync
  and Home ERP backfill set to `false`, with every `SMTP_*` value absent.
- The deploy's recorded release SHA/symlink matches the workflow SHA. If the
  workflow exercised rollback, the deployment is failed even when the previous
  services recovered healthy.

## Client checks

- Android staging APK installs beside production and shows `PhongVu OpsHub Staging`.
- Windows staging installer uses a separate app name, AppId, install folder, and shortcut.
- Login works with the known staging users created by the sanitizer.
- FIFO check/sort, warranty upload, feedback submit, app logs upload, and `/v1/ws` realtime connection work.
- New uploads appear under `/srv/opshub-staging/uploads` only.
- Client API/realtime URLs point to the new staging host. Legacy package URLs are
  allowed only while the measured bridge window is active.

## Release-proof checks

- Follow `load-proof-runbook.md`; do not improvise a production or write-heavy
  profile.
- A 15-minute 100-QPS hold meets the release threshold only. It does not prove
  the rolling 30-day SLO, RPO 24 hours or RTO 4 hours.
- The final sanitized report records cleanup at zero remaining synthetic users
  and confirms every token/k6 temporary file was removed.
