# Design

- Keep `User.tokenVersion`, `PasswordResetToken`, and `EmailVerificationCode` as
  the reset primitives; no new Prisma table is required for this flow.
- `POST /auth/forgot-password` sends a 6-digit reset code through the shared mail
  service when the allowed-domain email belongs to an OpsHub account. Missing
  accounts return a clear 404 so Flutter can show a registration dialog instead
  of advancing to code entry.
- `POST /auth/forgot-password/verify-code` consumes a valid reset code and
  creates a one-time `PasswordResetToken`; `POST /auth/reset-password` consumes
  that token and updates the password.
- `POST /admin/users/:id/reset-password` is guarded by `SUPER_ADMIN` and sets the
  target user's new password directly from a `newPassword` request body.
- The backend-served `/reset-password` page remains as legacy compatibility for
  previously issued links, but current reset emails send codes instead of links.
- SMTP uses `SMTP_USER=hoanghochoi1618@gmail.com` with the existing Gmail app
  password and displays `SMTP_FROM=admin@hoanghochoi.com`, a verified Gmail
  "Send mail as" alias.
- Never log password, code, reset token, SMTP secret, authorization headers, or
  full sensitive payloads.
