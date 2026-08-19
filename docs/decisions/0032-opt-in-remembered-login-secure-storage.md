# 0032 Opt-In Remembered Login Uses Secure Storage

Date: 2026-08-19

## Status

Accepted for OPS-208 implementation and review.

## Context

OpsHub's JWT-backed session persistence and the login form's optional password
prefill solve different problems. Reusing `SharedPreferences` for a password
would widen the exposure of a sensitive value and coupling it to the session
snapshot would make logout, token expiry, and password rotation ambiguous.

## Decision

1. The login screen exposes the Vietnamese-first `Nhớ mật khẩu` checkbox. It is
   opt-in, does not auto-submit or auto-login, and stores nothing until the
   backend login has succeeded.
2. The email/password pair is stored as a versioned JSON envelope through
   `flutter_secure_storage`, under the environment-scoped key
   `AppStorageKeys.secure('auth.remembered_login.v1')`. It is never written to
   `SharedPreferences`, an API request, a build artifact, or an unsanitized
   log.
3. A missing, partial, corrupt, or unavailable value fails closed. Corrupt
   values are deleted; unavailable storage leaves ordinary login usable and
   reports a Vietnamese action message. A failed login does not overwrite an
   existing pair.
4. Turning the checkbox off deletes the pair immediately. Logout preserves it
   while the preference remains enabled. Successful password change/reset
   deletes the old pair and never saves the replacement password implicitly.
5. Auth session keys remain in `_sessionPreferenceKeys` only for session
   metadata; the remembered credential is an independent boundary.

## Consequences

- Users can restore form values across `/login` visits without granting access
  to the authenticated shell.
- Every supported Flutter platform uses its secure-storage adapter; a platform
  adapter outage is a recoverable feature warning rather than an auth outage.
- Password rotation can never leave a known-valid old password intentionally
  persisted by the feature.

## Rejected alternatives

- `SharedPreferences`: rejected because it is not an appropriate password
  boundary.
- Auto-login from the saved pair: rejected because it would bypass the
  explicit login action and change session/security semantics.
- Saving on checkbox selection: rejected because it could persist an unverified
  or failed credential.
