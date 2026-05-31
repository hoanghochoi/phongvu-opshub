# AUTH-002 Password Change And Reset

## Intent

Allow staff to recover access safely without exposing account existence and allow
`SUPER_ADMIN` to trigger a password reset link for a managed user.

## Acceptance Criteria

- Authenticated users can change their own password only after entering the
  current password.
- Forgot-password requests send a reset email when the email belongs to an
  existing Phong Vũ account, while returning a generic success response for all
  allowed-domain requests.
- `SUPER_ADMIN` can send a reset link from user management; other roles are
  rejected by the backend.
- Reset links use `https://opshub.hoanghochoi.com/reset-password?token=...`,
  are one-time use, store only the token hash, expire after 30 minutes by
  default, and invalidate older active reset links for the same user.
- Password change/reset increments `User.tokenVersion` so older JWTs stop
  working.
- Resetting a locked user does not unlock the account.
