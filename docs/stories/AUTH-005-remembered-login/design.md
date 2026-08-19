# AUTH-005 Design And Figma Node Map

## Authority

- Linear: [OPS-208](https://linear.app/opshub/issue/OPS-208/auth-nho-mat-khau-opt-in-tren-man-hinh-dang-nhap)
- Figma file: `mFzSmQzlapSe3RSmUhvzll`, revision R1.
- State matrix: `2423:56206`.
- Shared checkbox component set: `180:2`.

## Node map

All nodes use the existing auth shell/card and shared Flutter tokens. The
changed control is one 48dp/44pt minimum checkbox row below the password field;
the visible label is exactly `Nhớ mật khẩu`, with the tooltip/semantics hint
`Tự điền thông tin đăng nhập lần sau`. The control follows the shared focus,
disabled, selected and error color tokens and remains inside the form's
scrollable lane when the keyboard opens.

| Viewport/platform | Default node | Checked node | Required visible states |
| --- | --- | --- | --- |
| Wide Windows/Web | `2424:68558` | `2424:68704` | default, checked |
| Compact Android | `2425:23834` | `2425:23956` | default, checked |
| Medium Android tablet | `2425:159566` | `2425:159688` | default, checked |
| Compact iOS | `2425:159855` | `2425:159977` | default, checked |
| Medium iPadOS | `2425:160144` | `2425:160266` | default, checked |
| Validation | `2425:160433` | — | field validation error |
| Submitting/disabled | `2425:160598` | — | fields and checkbox disabled |
| Secure-storage unavailable | `2425:160765` | — | Vietnamese non-blocking warning |

The Chrome audit matrix is `390x844`, `460x920`, `768x1024`, `1024x768`, and
`1440x900`; Android/iOS device checks use the matching compact/medium nodes.
No node adds a new route, payload, permission, or backend behavior.
