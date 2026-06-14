# Auth Contract

## Intent

Only authorized Phong Vũ and ACareTek staff should access OpsHub workflows.

## Current Shape

- Flutter uses email/password sign-in with a separate registration form.
- Users without an account register with an OpsHub-accepted staff email domain
  and an OpsHub password before signing in.
- Newly registered users do not self-select an SR/store. They can authenticate,
  but if they do not have `organizationNodeId` the auth/profile response returns
  `assignmentPending=true` and the app keeps them on `/assignment-pending` until
  a `SUPER_ADMIN` assigns an organization node.
- The pending screen must show: `Chưa được gán phòng ban, cửa hàng. Vui lòng
  liên hệ hoang.nv1@phongvu-mna.vn - zalo: 0906581906 để được hỗ trợ.` It
  provides refresh account and logout actions.
- Self-service `/users/me/select-store` is retired and returns `410 Gone`.
- NestJS validates allowed staff email domains from the
  `AUTH_ALLOWED_EMAIL_DOMAINS` admin setting. Organization-tree domain nodes are
  metadata only and do not enable or block login.
- `data/email_domain.txt` and `EMAIL_DOMAIN_FILE` remain fallback inputs when
  the admin setting is unavailable, but production should keep the setting as
  the source of truth.
- The break-glass account `admin@hoanghochoi.com` is allowed as an exact email
  exception even though `hoanghochoi.com` is not an operational organization
  domain.
- Backend configuration includes `JWT_SECRET`.
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
  screen. The email contains a 6-digit code that expires after 10 minutes. The
  response is generic so the API does not reveal whether an email exists.
- After verifying the reset code in the app, users enter the new password and
  confirmation in the app. The backend stores only a one-time reset-token hash
  between code verification and final password update.
- `SUPER_ADMIN` can set a user's new password directly from user management.
  This does not unlock disabled users; `status=no` still blocks login.
- The legacy reset landing page remains available for previously issued links,
  but the current forgot-password flow no longer sends reset links.
- Successful password change/reset increments the user token version so older
  JWTs are rejected.

## Contract Notes

- Login behavior is security-sensitive and defaults to the high-risk lane when
  changed.
- Allowed OpsHub staff email domains through `AUTH_ALLOWED_EMAIL_DOMAINS`,
  password policy, reset-code lifetime, JWT token-version invalidation,
  platform-session enforcement, session
  persistence, and logout behavior must be explicit in implementation stories.
- Do not commit real credentials, tokens, service accounts, or production env
  values.

## Expected Proof

- Flutter auth state tests where practical.
- NestJS auth service/controller/password-reset tests.
- Manual or automated mobile smoke for login/logout when the flow changes.
