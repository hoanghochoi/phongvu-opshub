# Auth Contract

## Intent

Only authorized Phong Vu staff should access OpsHub workflows.

## Current Shape

- Flutter uses email/password sign-in with a separate registration form.
- Users without an account register with an email thuộc Phong Vũ and an OpsHub
  password before signing in.
- NestJS validates the allowed Phong Vu email domain list from
  `data/email_domain.txt` and issues JWT-backed sessions.
- Backend configuration includes `JWT_SECRET`; `EMAIL_DOMAIN_FILE` can override
  the default domain-list file path.
- Persistent login on the client stores JWTs in secure storage.
- Each user can keep only one active session per OS platform: `windows`,
  `android`, `ios`, `macos`, `linux`, and `web`. A newer login on the same
  platform replaces the older platform session; different platforms can stay
  signed in at the same time.
- Auth clients send an app-local device id and platform during login/register.
  The backend stores only a hash of the device id and validates session claims
  on every protected API request.
- Users can change their password while authenticated by entering their current
  password and a new password that satisfies the password policy.
- Users who forget their password can request a reset email from the login
  screen. The response is generic so the API does not reveal whether an email
  exists.
- `SUPER_ADMIN` can send a password reset link from user management. This does
  not unlock disabled users; `status=no` still blocks login.
- Password reset links point to `PUBLIC_BASE_URL/reset-password?token=...`, are
  single-use, store only a token hash, expire after 30 minutes by default, and
  invalidate previous active reset links for the same user.
- Successful password change/reset increments the user token version so older
  JWTs are rejected.

## Contract Notes

- Login behavior is security-sensitive and defaults to the high-risk lane when
  changed.
- Allowed Phong Vu email domains, password policy, reset-token lifetime, JWT
  token-version invalidation, platform-session enforcement, session
  persistence, and logout behavior must be explicit in implementation stories.
- Do not commit real credentials, tokens, service accounts, or production env
  values.

## Expected Proof

- Flutter auth state tests where practical.
- NestJS auth service/controller/password-reset tests.
- Manual or automated mobile smoke for login/logout when the flow changes.
