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

## Contract Notes

- Login behavior is security-sensitive and defaults to the high-risk lane when
  changed.
- Allowed Phong Vu email domains, password policy, token lifetime, session persistence, and
  logout behavior must be explicit in implementation stories.
- Do not commit real credentials, tokens, service accounts, or production env
  values.

## Expected Proof

- Flutter auth state tests where practical.
- NestJS auth service/controller tests.
- Manual or automated mobile smoke for login/logout when the flow changes.
