# AUTH-003 Single Platform Session

## Intent

Limit each user to one active login session per OS platform while still allowing
parallel use across different platforms.

## Acceptance Criteria

- Supported platforms are `windows`, `android`, `ios`, `macos`, `linux`, and
  `web`.
- A new login on the same user/platform replaces the older session; the older
  JWT is rejected on the next protected API request.
- Logins on different platforms remain valid at the same time.
- JWTs without platform session claims are rejected immediately after deploy.
- Locked users are rejected on protected API requests, not only at login.
- Logout revokes the current platform session server-side and clears the local
  Flutter session.
- The client stores an app-local UUID as the device id; the backend stores only
  its hash.

