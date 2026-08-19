# AUTH-005 Validation

## Local proof

- `test/auth_credential_store_test.dart`: 5/5, covering empty, complete,
  partial/corrupt, secure-storage failure, namespace and invalid-input cases.
- `test/auth_provider_session_test.dart`: 20/20, covering the independent
  credential boundary, failed-login preservation, password change/reset clear,
  and existing session restore/logout consumers.
- `test/auth_pre_shell_redesign_test.dart`: 15/15, covering all existing auth
  viewports plus `Nhớ mật khẩu` semantics/hit target, prefill/no-overwrite,
  toggle clear, submitting disabled and storage-unavailable copy.
- `test/widget_test.dart`: 2/2 legacy login/session navigation tests.
- `flutter analyze`: pass. Web, Windows and staging-flavor Android debug
  builds pass. `scripts/verify-task.mjs --base origin/staging --full` and
  `git diff --check` pass.
- A serial full Flutter run reached 879 passed and 3 intentional skips with
  one unrelated timing failure in `sales_report_hub_test.dart`; an isolated
  rerun of that file passed 45/45.

## Required release proof

- A clean full Flutter run without the unrelated timing failure.
- After staging deploy: authenticated Chrome screenshots for all five declared
  viewports, exact Figma node comparison, secure storage runtime checks on
  Windows/Web and at least one Android/iOS device, plus router,
  session-restore/logout, password reset/change and single-platform-session
  regression evidence.

Local proof does not claim staging deploy, authenticated Chrome comparison, or
physical-device secure-storage behavior.
