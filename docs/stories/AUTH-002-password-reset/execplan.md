# Execution Plan

1. Reuse existing Prisma reset tables and implement reset-code send, verify, and
   token consumption in the auth service.
2. Change the admin reset endpoint to accept `newPassword` and set the managed
   user's password directly under `SUPER_ADMIN` guard.
3. Replace the Flutter forgot-password screen with the in-app email code and new
   password flow, and update the user-management reset dialog.
4. Update SMTP docs/env examples for the verified `admin@hoanghochoi.com` Gmail
   alias.
5. Run focused backend tests, full backend/Flutter validation, and diff hygiene
   before committing.
