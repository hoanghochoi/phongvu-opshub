# Auth Contract

## Intent

Only authorized Phong Vu staff should access OpsHub workflows.

## Current Shape

- Flutter uses Google Sign-In.
- NestJS validates login and issues JWT-backed sessions.
- Backend configuration includes `GOOGLE_CLIENT_ID`, `ALLOWED_DOMAIN`, and
  `JWT_SECRET`.
- Persistent login on the client uses local storage.

## Contract Notes

- Login behavior is security-sensitive and defaults to the high-risk lane when
  changed.
- Allowed domain, token lifetime, session persistence, and logout behavior must
  be explicit in implementation stories.
- Do not commit real credentials, tokens, service accounts, or production env
  values.

## Expected Proof

- Flutter auth state tests where practical.
- NestJS auth service/controller tests.
- Manual or automated mobile smoke for login/logout when the flow changes.
