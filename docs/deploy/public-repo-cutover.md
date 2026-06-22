# Public Repo Cutover Checklist

`hoanghochoi/phongvu-opshub` became public before this checklist was committed.
Keep the pre-public steps below as the audit/runbook for future history cleanup
or credential rotation.

## Current status (2026-06-22)

- Repository visibility is `PUBLIC`.
- Git history was rewritten in a clean mirror and force-pushed for `main` and
  `staging`.
- The cleaned remote was verified with `gitleaks detect --redact=100` and had no
  findings.
- Old GitHub Actions workflow runs were deleted.
- GitHub Actions artifacts and caches were removed.
- Deploy workflows were hardened with environment gates, deployment concurrency,
  and pinned third-party actions.
- Production and staging GitHub Environments each contain the expected 12 secret
  names, and both deploy workflows are active.
- Full staging and production deploy smoke is still required before declaring
  the credential cutover complete.

## Historical checks before making public

- Confirm the current remote refs are the cleaned refs:

  ```powershell
  git ls-remote https://github.com/hoanghochoi/phongvu-opshub.git refs/heads/main refs/heads/staging
  ```

- Confirm workflow runs, artifacts, and caches are empty:

  ```powershell
  gh api -X GET /repos/hoanghochoi/phongvu-opshub/actions/runs -f per_page=1 --jq '.total_count'
  gh api -X GET /repos/hoanghochoi/phongvu-opshub/actions/artifacts -f per_page=1 --jq '.total_count'
  gh cache list --repo hoanghochoi/phongvu-opshub --limit 100
  ```

- Confirm history is clean from a fresh clone:

  ```powershell
  go run github.com/zricethezav/gitleaks/v8@latest detect --source <fresh-clone> --redact=100
  ```

## Immediately after making public

- Follow the detailed secret recreation and rotation guide:
  [`github-environment-secrets.md`](github-environment-secrets.md).
- If every old secret is unavailable, follow the full reset guide:
  [`tao-moi-toan-bo-github-secrets.md`](tao-moi-toan-bo-github-secrets.md).
- Create GitHub Environments:
  - `production`: restrict deployment branches to `main`.
  - `staging`: restrict deployment branches to `staging`.
- Move deploy and signing secrets from repository secrets to environment secrets.
  Keep repository-level copies only until the first private/public cutover smoke
  passes, then delete the repository-level copies.
- Set production required reviewers and prevent self-review if GitHub offers it.
- Add rulesets or branch protection for `main` and `staging`:
  - block force-push;
  - block branch deletion;
  - restrict who can push;
  - prefer pull requests for `main`.
- Keep Actions workflow permissions read-only.
- Restrict allowed actions to GitHub-owned actions and the pinned actions already
  used by the deploy workflows.
- Enable secret scanning and push protection if available for the public repo.

## Secret inventory

Repository secrets that were present before public preparation:

- Production Android signing: `ANDROID_KEYSTORE_BASE64`,
  `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
- Staging Android signing: `ANDROID_STAGING_KEYSTORE_BASE64`,
  `ANDROID_STAGING_KEYSTORE_PASSWORD`, `ANDROID_STAGING_KEY_ALIAS`,
  `ANDROID_STAGING_KEY_PASSWORD`.
- Production deploy: `OPSHUB_VPS_HOST`, `OPSHUB_VPS_PORT`,
  `OPSHUB_VPS_USER`, `OPSHUB_VPS_SSH_KEY`.
- Staging deploy: `OPSHUB_STAGING_VPS_HOST`, `OPSHUB_STAGING_VPS_PORT`,
  `OPSHUB_STAGING_VPS_USER`, `OPSHUB_STAGING_SSH_KEY`.
- Shared Tailscale deploy: `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET`.
- Production Windows signing: `WINDOWS_SIGNING_PFX_BASE64`,
  `WINDOWS_SIGNING_PFX_PASSWORD`.

Missing before public preparation:

- `WINDOWS_STAGING_SIGNING_PFX_BASE64`
- `WINDOWS_STAGING_SIGNING_PFX_PASSWORD`

If staging Windows builds should be signed, create or reuse an internal staging
PFX, then add the two missing secrets to the `staging` environment. If unsigned
staging Windows artifacts are acceptable, leave both unset; the staging workflow
will build unsigned artifacts and log that signing is disabled.

PowerShell helper to create base64 text from a PFX:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\path\to\opshub-staging-codesign.pfx')) |
  Set-Content .\opshub-staging-codesign.pfx.base64
```

## Deployment smoke order

1. Enable only the staging workflow and run `Deploy OpsHub Staging`.
2. Verify:

   ```powershell
   curl.exe -fsS https://opshub-staging.hoanghochoi.com/health
   curl.exe -fsS https://opshub-staging.hoanghochoi.com/api/health
   curl.exe -fsS "https://opshub-staging.hoanghochoi.com/api/app-version?platform=android"
   curl.exe -fsS "https://opshub-staging.hoanghochoi.com/api/app-version?platform=windows"
   curl.exe -fsS https://opshub.hoanghochoi.com/staging-download/downloads/latest.json
   ```

3. Enable production workflow and run `workflow_dispatch` with
   `skip_client_build=true`.
4. Verify production static path without changing app-version metadata:

   ```powershell
   curl.exe -fsS https://opshub.hoanghochoi.com/download
   curl.exe -fsS https://opshub.hoanghochoi.com/downloads/latest.json
   curl.exe -fsS "https://opshub.hoanghochoi.com/api/app-version?platform=android"
   curl.exe -fsS "https://opshub.hoanghochoi.com/api/app-version?platform=windows"
   ```

5. Only after staging and static production smoke pass, run the full production
   deploy from `main`.

## Clone hygiene after history rewrite

- Do not push from old clones without re-syncing; old clones can reintroduce the
  removed history.
- Preferred path: make a fresh clone after the public cutover.
- If a local clone has uncommitted work, export patches first, re-clone, then
  re-apply the patches manually.
