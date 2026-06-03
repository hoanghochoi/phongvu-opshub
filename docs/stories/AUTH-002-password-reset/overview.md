# AUTH-002 Password Change And Reset

## Intent

Allow staff to recover access safely without exposing account existence and allow
`SUPER_ADMIN` to set a managed user's password directly when needed.

## Acceptance Criteria

- Authenticated users can change their own password only after entering the
  current password.
- Forgot-password requests send a 6-digit email code when the email belongs to
  an existing Phong Vũ account, while returning a generic success response for
  all allowed-domain requests.
- Password reset codes expire after 10 minutes, store only a bcrypt hash, reject
  reuse, and lock after too many failed attempts.
- After code verification in the app, the backend issues a short-lived one-time
  reset token; the user then enters and confirms the new password in the app.
- `SUPER_ADMIN` can set a user's new password directly from user management;
  other roles are rejected by the backend.
- Password change/reset increments `User.tokenVersion` and revokes active
  platform sessions so older JWTs stop working.
- Resetting a locked user does not unlock the account.
