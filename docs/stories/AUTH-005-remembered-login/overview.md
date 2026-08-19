# AUTH-005 Remembered Login

## Intent

Give staff an explicit, opt-in way to prefill the email and password on the
public login form without changing session, API, logout, or route behavior.

## Acceptance criteria

- `/login` displays the exact visible copy `Nhớ mật khẩu` below the password
  field and before `Đăng nhập`; its accessible hint is
  `Tự điền thông tin đăng nhập lần sau`.
- A complete remembered pair is read asynchronously from secure storage and
  prefills only when the user has not started entering either field.
- Checking the preference only selects the preference. A successful login with
  it selected saves the new email/password pair; a failed login leaves any old
  pair untouched.
- Unchecking clears the pair immediately. If clear fails, the checkbox stays
  checked and the user receives a Vietnamese retry message.
- Logout keeps the pair when the preference is still enabled. Successful
  password change/reset clears the old pair and never saves the new password.
- Missing/partial/corrupt/unavailable storage fails closed, never uses
  `SharedPreferences`, and never logs plaintext password/token data.
- No auto-login, new API/backend contract, route change, or change to
  single-platform session behavior is introduced.
