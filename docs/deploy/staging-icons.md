# OpsHub staging icons

Production keeps the current launcher icon sources under `assets/icon/source/`.
Staging uses the generated icon set under `assets/icon/staging/`, with a
top-left `STAGING` badge so it is visually distinct while minimally covering the
logo.

## Regenerate

```powershell
& 'C:\Users\ASUS1\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' scripts\generate-staging-icons.py
```

The script generates:

- `assets/icon/staging/source/`
- `assets/icon/staging/android/`
- `assets/icon/staging/ios/`
- `assets/icon/staging/web/`
- `assets/icon/staging/windows/`
- `assets/icon/staging/macos/`
- `android/app/src/staging/res/`

## Build contract

- Android staging uses `android/app/src/staging/res/` through the existing
  `staging` flavor.
- Windows staging copies `assets/icon/staging/windows/app_icon.ico` before
  `flutter build windows`.
- Flutter UI reads the staging app logo from `AppBrand` when `APP_ENV=staging`
  or `API_BASE_URL` points to the staging domain.
- Web staging copies `assets/icon/staging/web/` before `flutter build web` and
  rewrites `web/index.html` plus `web/manifest.json` to show the staging title
  and PWA name. Staging download metadata copies that web staging icon before
  publishing the download page icon.
- Production workflows do not run the staging icon apply script.
