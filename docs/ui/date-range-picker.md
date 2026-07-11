# Canonical Date Range Picker

## Import path

Filter bars normally import the shared trigger:

```dart
import 'package:phongvu_opshub/app/widgets/app_filter_dropdowns.dart';
```

The canonical selection surface and advanced types live at:

```dart
import 'package:phongvu_opshub/app/widgets/date_range_picker/date_range_picker.dart';
```

Do not import a calendar library or Flutter's `showDateRangePicker` from a
feature/page. `AppDateRangeDropdown` opens `DateRangePicker.show` and preserves
the existing filter callback contract.

## Props and usage

```dart
AppDateRangeDropdown(
  label: 'Ngày',
  start: provider.startDate,
  end: provider.endDate,
  allowEmptyRange: true,
  firstDate: DateTime(2020),
  lastDate: DateTime(2100, 12, 31),
  selectableDayPredicate: (day) => !disabledDates.contains(day),
  onChanged: provider.setDateRange,
)
```

- `start` / `end`: committed filter value copied into draft state on open.
- `onChanged`: called once after `Áp dụng`; never called by draft selection,
  `Hủy`, outside dismissal, or close.
- `allowEmptyRange`: shows `Xóa bộ lọc` and permits applying `null/null`.
- `firstDate` / `lastDate`: inclusive bounds; default 2020-01-01–2100-12-31.
- `selectableDayPredicate`: disables dates without forking the component.
- `now`: injectable local clock for presets and tests.

Advanced/demo code may call `DateRangePicker.show(...)` directly. Run the demo:

```powershell
flutter run -t tool/date_range_picker_demo.dart
```

## Date formatting and timezone

- Visible dates use `dd/MM/yyyy`.
- The picker returns local date-only values created as
  `DateTime(year, month, day)`, with no UTC conversion or time-of-day.
- Existing providers/repositories keep serializing `startDate` and `endDate` as
  `yyyy-MM-dd`. Do not call `toUtc()`, append `Z`, or send ISO timestamps.
- Empty remains `null/null`; each feature keeps its existing fallback range and
  query-param behavior. Vietnam/local business-day semantics are unchanged.

## Standard presets

Presets are inclusive and based on local `currentDate`:

| Canonical preset | Visible label | Range |
| --- | --- | --- |
| Today | Hôm nay | today–today |
| Yesterday | Hôm qua | yesterday–yesterday |
| Last 3 Days | 3 ngày gần nhất | today minus 2 days–today |
| Last 7 Days | 7 ngày gần nhất | today minus 6 days–today |
| Last 30 Days | 30 ngày gần nhất | today minus 29 days–today |
| Last 3 Months | 3 tháng gần nhất | same/clamped day 3 calendar months ago–today |
| Last 6 Months | 6 tháng gần nhất | same/clamped day 6 calendar months ago–today |
| Last 1 Year | 1 năm gần nhất | same/clamped day 12 calendar months ago–today |
| Custom | Tùy chỉnh | keeps the current draft for manual selection |

Preset and Clear actions only change draft state. `Áp dụng` commits it.

## Desktop behavior

- Compact anchored popover attached to the trigger button, with no dimmed
  full-screen modal/dialog backdrop. The popover should stay visually connected
  to the trigger, fit inside the viewport, and close on outside click without
  committing draft changes.
- Preset navigation stays on the left and two calendars stay on the right.
- Header always shows the draft range; endpoints use the primary token and
  inner range days use the primary-surface token.
- Month/year navigation, min/max and disabled dates apply to both calendars.
- Arrow keys move by one/seven days; Enter or Space selects the focused day;
  Tab traverses presets, navigation and actions.

## Mobile behavior

- Width below `AppLayoutTokens.compactBreakpoint` opens an is-scroll-controlled
  bottom sheet with safe-area handling and one visible month.
- Presets scroll horizontally; primary touch targets are at least 44–48 px.
- Clear, Cancel and Apply remain in the bottom action bar.
- Swipe/outside dismissal and close do not commit draft changes.

## Repository rule

All date range filters must reuse the canonical shared DateRangePicker. Do not create feature-local implementations.

Feature/page code must not import a calendar library directly. Extend the
canonical props or implementation when new shared behavior is required.
