# Validation

Required proof:

- `npx prisma validate`
- `npx prisma generate`
- `npm test -- --runInBand src/auth/auth-session.service.spec.ts src/auth/jwt.strategy.spec.ts src/auth/auth.service.spec.ts src/auth/auth.controller.spec.ts src/auth/password-reset.service.spec.ts`
- `npm test -- --runInBand`
- `npm run build`
- `flutter analyze --no-pub`
- `flutter test --no-pub --reporter expanded`
- `git diff --check`

Manual smoke after deploy:

- Login twice on the same platform; the second login stays valid and the first
  token is rejected.
- Login on Windows and Android with the same user; both sessions stay valid.
- Existing pre-AUTH-003 JWTs are rejected and clients are forced to sign in
  again after updating.
- Logout revokes only the current platform session.

