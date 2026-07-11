import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/app_filter_dropdowns.dart';
import 'package:phongvu_opshub/app/widgets/date_range_picker/date_range_picker.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';

void main() {
  setUpAll(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  testWidgets('preset only updates filter after Apply', (tester) async {
    DateRangePickerResult? applied;
    await _pumpPicker(
      tester,
      initialStart: DateTime(2026, 7, 4),
      initialEnd: DateTime(2026, 7, 4),
      onApply: (value) => applied = value,
    );

    await tester.tap(find.byKey(const Key('date-range-preset-last7Days')));
    await tester.pump();
    expect(applied, isNull);
    expect(find.text('05/07/2026 – 11/07/2026'), findsOneWidget);

    await tester.tap(find.byKey(const Key('date-range-apply')));
    expect(applied?.start, DateTime(2026, 7, 5));
    expect(applied?.end, DateTime(2026, 7, 11));
  });

  testWidgets('selects a range across two months and applies once', (
    tester,
  ) async {
    DateRangePickerResult? applied;
    await _pumpPicker(
      tester,
      initialStart: DateTime(2026, 6, 25),
      onApply: (value) => applied = value,
    );

    await tester.tap(find.byKey(const Key('date-cell-2026-07-04')).last);
    await tester.pump();
    expect(find.text('25/06/2026 – 04/07/2026'), findsOneWidget);
    expect(applied, isNull);

    await tester.tap(find.byKey(const Key('date-range-apply')));
    expect(applied?.start, DateTime(2026, 6, 25));
    expect(applied?.end, DateTime(2026, 7, 4));
  });

  testWidgets('Cancel discards draft changes', (tester) async {
    DateRangePickerResult? applied;
    var cancelled = false;
    await _pumpPicker(
      tester,
      initialStart: DateTime(2026, 7, 4),
      initialEnd: DateTime(2026, 7, 4),
      onApply: (value) => applied = value,
      onCancel: () => cancelled = true,
    );

    await tester.tap(find.byKey(const Key('date-range-preset-yesterday')));
    await tester.tap(find.byKey(const Key('date-range-cancel')));

    expect(cancelled, isTrue);
    expect(applied, isNull);
  });

  testWidgets('Clear is draft state and applies an empty range', (
    tester,
  ) async {
    DateRangePickerResult? applied;
    await _pumpPicker(
      tester,
      initialStart: DateTime(2026, 7, 4),
      initialEnd: DateTime(2026, 7, 4),
      onApply: (value) => applied = value,
    );

    await tester.tap(find.byKey(const Key('date-range-clear')));
    await tester.pump();
    expect(applied, isNull);
    expect(find.text('Tất cả ngày'), findsOneWidget);

    await tester.tap(find.byKey(const Key('date-range-apply')));
    expect(applied?.isEmpty, isTrue);
  });

  testWidgets('honors min max and disabled dates', (tester) async {
    await _pumpPicker(
      tester,
      initialStart: DateTime(2026, 7, 4),
      initialEnd: DateTime(2026, 7, 4),
      firstDate: DateTime(2026, 7, 3),
      lastDate: DateTime(2026, 7, 10),
      selectableDayPredicate: (day) => day.day != 5,
    );

    InkWell day2() => tester.widget<InkWell>(
      find.byKey(const Key('date-cell-2026-07-02')).first,
    );
    InkWell day5() => tester.widget<InkWell>(
      find.byKey(const Key('date-cell-2026-07-05')).first,
    );
    InkWell day10() => tester.widget<InkWell>(
      find.byKey(const Key('date-cell-2026-07-10')).first,
    );

    expect(day2().onTap, isNull);
    expect(day5().onTap, isNull);
    expect(day10().onTap, isNotNull);
  });

  testWidgets('mobile trigger opens one-month bottom sheet', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    DateTime? selectedStart;
    DateTime? selectedEnd;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppDateRangeDropdown(
            label: 'Ngày',
            start: DateTime(2026, 7, 4),
            end: DateTime(2026, 7, 4),
            now: () => DateTime(2026, 7, 11),
            onChanged: (start, end) {
              selectedStart = start;
              selectedEnd = end;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-date-range-picker')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('date-range-mobile')), findsOneWidget);
    expect(find.byKey(const Key('mobile-calendar')), findsOneWidget);
    expect(find.byKey(const Key('from-calendar')), findsNothing);
    expect(find.byKey(const Key('to-calendar')), findsNothing);

    await tester.tap(find.byKey(const Key('date-range-preset-today')));
    await tester.tap(find.byKey(const Key('date-range-apply')));
    await tester.pumpAndSettle();
    expect(selectedStart, DateTime(2026, 7, 11));
    expect(selectedEnd, DateTime(2026, 7, 11));
  });

  testWidgets('desktop trigger opens compact anchored popover', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 120),
              child: SizedBox(
                width: 260,
                child: AppDateRangeDropdown(
                  label: 'Ngày',
                  start: DateTime(2026, 7, 4),
                  end: DateTime(2026, 7, 4),
                  now: () => DateTime(2026, 7, 11),
                  onChanged: (_, _) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final trigger = find.byKey(const Key('open-date-range-picker'));
    final triggerBottom = tester.getBottomLeft(trigger).dy;
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    final popover = find.byKey(const Key('date-range-popover'));
    expect(popover, findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const Key('date-range-desktop')), findsOneWidget);
    expect(find.byKey(const Key('from-calendar')), findsOneWidget);
    expect(find.byKey(const Key('to-calendar')), findsOneWidget);

    final popoverTopLeft = tester.getTopLeft(popover);
    final popoverSize = tester.getSize(popover);
    expect(popoverSize.width, lessThan(900));
    expect(popoverSize.height, lessThan(580));
    expect(popoverTopLeft.dy, greaterThanOrEqualTo(triggerBottom));
    expect(popoverTopLeft.dy - triggerBottom, lessThanOrEqualTo(12));
    expect(popoverTopLeft.dx, greaterThanOrEqualTo(12));
  });

  testWidgets('outside dismiss and close do not update filter', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var changes = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppDateRangeDropdown(
              label: 'Ngày',
              start: DateTime(2026, 7, 4),
              end: DateTime(2026, 7, 4),
              now: () => DateTime(2026, 7, 11),
              onChanged: (_, _) => changes += 1,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-date-range-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('date-range-preset-today')));
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(changes, 0);
  });

  testWidgets('keyboard arrows move focus and Enter selects end date', (
    tester,
  ) async {
    DateRangePickerResult? applied;
    await _pumpPicker(
      tester,
      initialStart: DateTime(2026, 7, 4),
      initialEnd: DateTime(2026, 7, 4),
      onApply: (value) => applied = value,
    );

    await tester.tap(find.byKey(const Key('date-cell-2026-07-04')).first);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.tap(find.byKey(const Key('date-range-apply')));

    expect(applied?.start, DateTime(2026, 7, 4));
    expect(applied?.end, DateTime(2026, 7, 5));
  });
}

Future<void> _pumpPicker(
  WidgetTester tester, {
  DateTime? initialStart,
  DateTime? initialEnd,
  DateTime? firstDate,
  DateTime? lastDate,
  AppSelectableDayPredicate? selectableDayPredicate,
  ValueChanged<DateRangePickerResult>? onApply,
  VoidCallback? onCancel,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: DateRangePicker(
            initialStart: initialStart,
            initialEnd: initialEnd,
            firstDate: firstDate ?? DateTime(2020),
            lastDate: lastDate ?? DateTime(2100, 12, 31),
            currentDate: DateTime(2026, 7, 11),
            onApply: onApply ?? (_) {},
            onCancel: onCancel ?? () {},
            selectableDayPredicate: selectableDayPredicate,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
