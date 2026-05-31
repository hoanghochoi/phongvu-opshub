# Design

- Add `User.tokenVersion` and `PasswordResetToken` in Prisma with hashed token,
  expiry, consumed timestamp, attempt count, source, and admin actor metadata.
- Add public auth APIs for forgot/reset and a JWT-protected self-service change
  password API.
- Add an admin API under `POST /admin/users/:id/reset-password` guarded by
  `SUPER_ADMIN`.
- Serve a minimal backend HTML landing page at `/reset-password`; the page uses
  a server-side `POST /reset-password` form so password values never enter the
  URL. Keep the JSON `POST /auth/reset-password` API for programmatic clients.
- Reuse SMTP through a shared mail service and never log password, token, SMTP
  secret, or full reset link.
