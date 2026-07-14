# OpsHub Staging Smoke Checklist

Use this checklist after the manual staging workflow succeeds.

## Server checks

- `ssh mementoamoris` resolves to `100.127.127.89`.
- `sudo ufw status verbose` has no public `22`, `80`, or `443` allow rule.
- `systemctl is-active cloudflared-opshub-staging` returns `active`.
- `curl -fsS https://opshub-staging.hoanghochoi.com/health` returns `ok`.
- `curl -fsS https://opshub-staging.hoanghochoi.com/api/health` returns backend health JSON.
- `curl -fsS https://opshub-staging.hoanghochoi.com/api/app-version?platform=android` points to `https://opshub-staging.hoanghochoi.com/downloads/`.
- `curl -fsS https://opshub-staging.hoanghochoi.com/download` reaches the Cloudflare Access-protected staging download page.
- `curl -fsS https://opshub-staging.hoanghochoi.com/downloads/latest.json` contains only staging URLs.

## Client checks

- Android staging APK installs beside production and shows `PhongVu OpsHub Staging`.
- Windows staging installer uses a separate app name, AppId, install folder, and shortcut.
- Login works with the known staging users created by the sanitizer.
- FIFO check/sort, warranty upload, feedback submit, app logs upload, and `/ws` realtime connection work.
- New uploads appear under `/srv/opshub-staging/uploads` only.
- No app-version, download manifest, or client API URL points to `opshub.hoanghochoi.com`.
