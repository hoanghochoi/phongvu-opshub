# Execution Plan: OPS-208 Remembered Login

Date: 2026-08-19

## Status

Active — implementation complete locally; staging/release gates pending.

## Outcome

Provide the approved R1 login checkbox `Nhớ mật khẩu` with secure-storage-only
prefill/save/clear behavior while preserving all existing auth/session flows.

## Context

Product contract: `docs/product/auth.md`. Durable decision:
`docs/decisions/0032-opt-in-remembered-login-secure-storage.md`. Story packet:
`docs/stories/AUTH-005-remembered-login/`. Linear/Figma authority is recorded in
OPS-208 and the story design node map.

## Scope and recovery

- Changed runtime: credential store, AuthProvider boundary, shared checkbox,
  login screen, password change/reset cleanup, and focused tests.
- No backend/API/session contract change. Revert the task branch to the
  pre-implementation SHA to remove the feature; secure-storage key is versioned
  and can be cleared independently.

## Progress

- [x] Create issue/design revision and guarded `codex/ops-208-remember-password`
  worktree from `origin/staging`.
- [x] Implement secure credential boundary and provider operations.
- [x] Integrate responsive/accessibility checkbox and login behavior.
- [x] Add focused store/provider/widget proof and documentation authority.
- [x] Run analyzer, focused auth proof, platform builds, affected verification
  and review exact diff.
- [ ] Deploy staging, perform Chrome/device QA, and record evidence in OPS-208.

## Validation

Focused local proof passes for the credential store, auth pre-shell redesign,
auth provider/session consumers, and the legacy login widget tests. Flutter
analyze passes. The full suite completed with 879 passed and 3 intentional
skips but one unrelated timing failure in `sales_report_hub_test.dart`; that
file passes in isolation (45/45). Platform builds and affected verification
pass locally. Staging deploy, authenticated visual comparison, and physical
device secure-storage checks remain pending.
