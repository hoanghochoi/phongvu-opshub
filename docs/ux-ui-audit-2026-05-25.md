# UX/UI Audit - 2026-05-25

## Scope

This audit targets Android mobile and Windows PC UI consistency for OpsHub. The
follow-up implementation pass closes the listed P0/P1/P2 findings with scoped UI
patches, launcher icon cleanup, Android build hardening, and fresh validation.

## Evidence Collected

Local screenshots are stored under `tmp/ux-audit-2026-05-25/` and are not
committed because they may contain runtime/session data.

| Area | Platform | Evidence | Notes |
| --- | --- | --- | --- |
| Login | Android emulator | `android/02-login.png` | Clean unauthenticated screen captured. |
| Register | Android emulator | `android/04-after-register-tap.png` | Captured with Android ANR dialog over the form. |
| Launch compatibility | Android emulator | `android/01-launch.png` | System 16 KB compatibility dialog appears before login. |
| Windows shell | Windows debug build | runtime log/code inspection | Window screenshot attempts were discarded because they captured unrelated apps. |
| Launcher icon | Android/iOS/Windows generated assets | generated asset inspection | Padded source generated and launcher assets regenerated. |
| Implementation pass | Flutter static/runtime proof | current patch validation | `git diff --check`, `flutter analyze`, `flutter test`, `flutter build apk --debug`, Android `zipalign -c -P 16 -v 4`, Windows debug smoke. |
| Form/layout consistency pass | Flutter static/runtime proof | current patch validation | Shared form gaps and responsive wrappers applied across auth, admin, FIFO, sort, warranty, chat scanner, feedback, payment monitor, and VietQR forms. `git diff --check`, `flutter analyze`, `flutter test`, and Windows debug smoke passed. |

## Coverage Limits

- Authenticated mobile screens were not fully captured because the physical
  Android device rejected the debug install as a version downgrade and then
  required user confirmation to uninstall/reinstall. No forced uninstall was
  performed.
- The implementation pass retried Android device install without force; the
  device returned `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`.
- Windows screenshots captured through full-screen tooling included unrelated
  desktop windows, so they are treated as invalid evidence and excluded from the
  report.
- The Windows app initially encountered a FIFO render exception during debug
  startup. The render blocker was fixed and re-smoked in the implementation
  pass.

## Backlog Findings

### P0 - FIFO Windows Render Blocker

- Screen: FIFO check screen.
- Platform: Windows PC.
- Evidence: `lib/features/fifo/presentation/screens/fifo_check_screen.dart`,
  lines 99-105.
- State: Debug runtime reported `BoxConstraints forces an infinite width` around
  the FIFO search `ElevatedButton.icon`.
- Impact: Windows authenticated shell can fail to render when the FIFO screen is
  present in the navigation stack, blocking UX audit and likely blocking staff
  use on PC.
- Recommendation: constrain the search button width on desktop/mobile, or use a
  shared input action component with fixed height and bounded min/max width.
- Test needed: Windows smoke for Home -> FIFO -> search bar, plus
  `flutter analyze` and `flutter test`.
- Fix applied: constrained the FIFO search `ElevatedButton.icon` to a fixed
  width so the global button minimum height no longer expands to infinite width
  inside the row on Windows.

### P1 - Auth Layout Is Visually Separate From Operational Screens

- Screen: Login and register.
- Platform: Android mobile.
- Evidence: `android/02-login.png`, `android/04-after-register-tap.png`.
- State: Auth uses a large gradient/card treatment while operational screens use
  denser utility layouts. Register has many tall fields in a single card and one
  label truncates on mobile.
- Impact: The first-run experience feels less consistent with the staff
  operations UI, and dense forms risk feeling cramped on smaller screens.
- Recommendation: keep the brand moment but align auth spacing, field height,
  card radius, and button treatment with shared app metrics. Split long optional
  labels or reduce input horizontal padding.
- Test needed: Android screenshots for login/register on 360x800 and 412x915
  logical viewports.
- Fix applied: constrained auth forms to shared responsive max widths, reduced
  oversized logo/card spacing, aligned card radius and field density with app
  metrics, and normalized dense login/register/profile/store-selection form
  spacing with shared form gap tokens.

### P1 - Android 16 KB Compatibility Dialog On Launch

- Screen: App launch.
- Platform: Android emulator / newer Android page-size checks.
- Evidence: `android/01-launch.png`.
- State: Android shows a compatibility dialog for native libraries that are not
  16 KB aligned.
- Impact: Staff may see a system warning before the app, which hurts trust and
  interrupts the first screen.
- Recommendation: verify release build/native dependencies for 16 KB page-size
  support and update affected native libraries or Android build tooling.
- Test needed: Install release/profile APK on Android 15/16 emulator or device
  with page-size compatibility checks.
- Fix applied: pinned Android NDK r28.2.13676358 and disabled legacy JNI
  packaging so generated APKs use the modern native-library packaging path
  required for 16 KB page-size readiness.
- Proof: `flutter build apk --debug` passed and
  `zipalign -c -P 16 -v 4 build/app/outputs/flutter-apk/app-debug.apk` reported
  `Verification successful`.

### P1 - Desktop Needs A PC Layout Contract

- Screen: Home, FIFO, payment monitor, admin/manual inventory, VietQR.
- Platform: Windows PC.
- Evidence: Windows debug attempt plus current mobile-first component patterns.
- State: Several flows are built from mobile shell primitives. Without a clear
  desktop max-width/grid contract, forms can become too wide or navigation can
  feel mobile-only on PC.
- Impact: PC users get inconsistent density and spacing between operational
  tools, especially payment monitor/admin screens.
- Recommendation: introduce desktop layout tokens: page max width, two-column
  form grid, section gap, card gap, button height, icon-button size, and shell
  navigation behavior.
- Test needed: Windows screenshots at 1366x768 and 1920x1080 for Home, FIFO,
  Payment monitor, Admin/manual inventory, and VietQR.
- Fix applied: introduced shared desktop layout tokens and responsive content
  wrappers, then applied max-width/padding contracts to Home, FIFO, Sort,
  Warranty, Admin, inventory import, Payment monitor, and VietQR screens. A
  follow-up consistency pass also covered FIFO menu/history, admin user/store
  and role lists/dialogs, profile, store selection, chat/manual scanner input,
  and search/filter rows that mix inputs with actions.
- Proof: Windows debug smoke built and launched without render/layout
  exceptions after the patch. Backend-local network errors remained because
  `localhost:3000` was not running.

### P2 - Shared Empty/Loading/Error States Need A Pass

- Screen: FIFO, Sort, Warranty, Admin, VietQR, Payment monitor.
- Platform: Android and Windows.
- Evidence: code inspection and partial smoke coverage.
- State: Feature screens use local state presentations, so empty/loading/error
  spacing and copy can diverge.
- Impact: The app can feel assembled feature-by-feature instead of one product.
- Recommendation: centralize state surfaces for empty, loading, error, success,
  exported/disabled, and confirmed transaction states.
- Test needed: targeted screenshots per state after design-token cleanup.
- Fix applied: introduced shared state surfaces for loading, empty, error, and
  status banners, then adopted them in FIFO, Sort, warranty, payment monitor,
  and FIFO history flows.

### P2 - Form Field Spacing Was Too Tight On Dense Input Pages

- Screen: Login, register, profile, store selection, admin user/store/role
  editors, FIFO check/history, Sort, Warranty, Feedback, VietQR, Payment
  monitor, chat/manual scanner fallback.
- Platform: Android and Windows.
- State: Several input groups used local `SizedBox` gaps from 8-14 px or
  screen-local padding, so adjacent fields and input/action rows felt cramped
  compared with the rest of the UI.
- Impact: Staff forms are harder to scan, especially on PC where fields sit
  next to action buttons and on mobile where validation text can make dense
  groups feel crowded.
- Fix applied: added shared `formFieldGap`, `formSectionGap`,
  `formInlineGap`, and `AppFormColumn`, then applied those tokens across form
  pages and admin dialogs. Form-heavy screens now use shared responsive max
  widths instead of ad hoc full-width padding.
- Proof: `git diff --check`, `flutter analyze`, `flutter test`, and Windows
  debug smoke passed. Backend-local network errors remained because
  `localhost:3000` was not running.
- Test needed: Android and Windows visual smoke for authenticated form pages
  with real backend data.

## Implemented Logo Fix

- Promoted `assets/icon/variants/9router_copilot_v2/` as the canonical launcher
  icon set.
- Updated `flutter_launcher_icons` config to use the 9Router v2 padded,
  foreground, and favicon source files.
- Regenerated and synchronized Android, iOS, macOS, web, and Windows launcher
  assets from the 9Router v2 set.
- Verified generated dimensions:
  - Android `mipmap-xxxhdpi/ic_launcher.png`: 192x192.
  - Android `drawable-xxxhdpi/ic_launcher_foreground.png`: 432x432.
  - iOS marketing icon: 1024x1024.

## Recommended Next Story

Run a backend-backed visual pass with real authenticated data on Android and
Windows, then capture final screenshots for dense operational states.
