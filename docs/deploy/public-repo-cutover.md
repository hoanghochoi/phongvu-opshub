# Public Repo Cutover Checklist

Use this checklist before changing `hoanghochoi/phongvu-opshub` from private to
public. Do not make the repository public until every pre-public item is checked.

## Pre-public status

- Deploy workflows are disabled while the repo is being prepared.
- Git history was rewritten in a clean mirror and force-pushed for `main` and
  `staging`.
- The cleaned remote was verified with `gitleaks detect --redact=100` and had no
  findings.
- Old GitHub Actions workflow runs were deleted.
- GitHub Actions artifacts and caches were removed.
- Deploy workflows were hardened with environment gates, deployment concurrency,
  and pinned third-party actions.

## Before clicking Make public

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
