# Design

- Backend stores one `UserPlatformSession` row per `(userId, platform)` with a
  monotonically increasing `sessionVersion`. Login/register upsert that row and
  sign JWTs with `sessionId`, `platform`, `sessionVersion`, and `tokenVersion`.
- `JwtStrategy` rejects missing or stale session claims, revoked/expired rows,
  token-version mismatches, deleted users, and locked users.
- Password reset increments `tokenVersion` and revokes all platform sessions.
  Authenticated password change increments `tokenVersion` and returns a fresh
  token for the current platform session.
- Flutter generates a UUID once per app install and sends it with platform and
  app version metadata during login/register. Server logs use only sanitized
  platform/session data and hashed device id prefixes.

