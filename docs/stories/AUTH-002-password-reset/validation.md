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

- `/reset-password?token=bad` loads and rejects invalid token.
- Reset landing form uses server-side POST, has no inline script, and does not
  expose password fields in the URL.
- Forgot-password returns generic success.
- A valid reset link changes the password once and rejects reuse.
- `SUPER_ADMIN` can send a reset link; non-super-admin receives forbidden.
