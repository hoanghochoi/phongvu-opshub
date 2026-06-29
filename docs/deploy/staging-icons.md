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
- Staging download metadata copies the web staging icon before publishing the
  download page icon.
- Production workflows do not run the staging icon apply script.
