# Validation

Required proof:

- `npx prisma validate`
- `npx prisma generate`
- `npm test -- --runInBand src/auth/auth.service.spec.ts src/auth/auth.controller.spec.ts src/auth/password-reset.service.spec.ts src/user/user.service.spec.ts`
- `npm test -- --runInBand`
- `npm run build`
- `flutter analyze --no-pub`
- `flutter test --no-pub --reporter expanded`
- `git diff --check`

Manual smoke after deploy:

- Forgot-password returns generic success and sends a 6-digit code from
  `admin@hoanghochoi.com` when the email belongs to an OpsHub account.
- Reset code works once, expires after 10 minutes, and rejects wrong codes.
- After code verification, the app shows password and confirm-password fields;
  a valid reset changes the password and requires login again.
- Old sessions are revoked after self-service or admin password reset.
- `SUPER_ADMIN` can set a user's password directly; non-super-admin receives
  forbidden.
- Legacy `/reset-password?token=bad` still loads and rejects invalid tokens.
