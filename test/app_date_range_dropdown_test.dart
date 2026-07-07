import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/app_filter_dropdowns.dart';

void main() {
  testWidgets('date range dropdown yesterday preset selects previous day', (
    tester,
  ) async {
    DateTime? selectedStart;
    DateTime? selectedEnd;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              child: AppDateRangeDropdown(
                label: 'Ngày',
                start: DateTime(2026, 7, 4),
                end: DateTime(2026, 7, 4),
                now: () => DateTime(2026, 7, 4, 9),
                onChanged: (start, end) {
                  selectedStart = start;
                  selectedEnd = end;
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ngày: 04/07/2026'));
    await tester.pumpAndSettle();

    expect(find.text('Hôm qua'), findsOneWidget);
    expect(find.text('Hôm nay'), findsNothing);

    await tester.tap(find.text('Hôm qua'));
    await tester.pumpAndSettle();

    expect(selectedStart, DateTime(2026, 7, 3));
    expect(selectedEnd, DateTime(2026, 7, 3));
  });

  testWidgets('date range dropdown applies both dates from one picker', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    DateTime? selectedStart;
    DateTime? selectedEnd;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              child: AppDateRangeDropdown(
                label: 'Ngày',
                start: DateTime(2026, 7, 4),
                end: DateTime(2026, 7, 4),
                now: () => DateTime(2026, 7, 4, 9),
                onChanged: (start, end) {
                  selectedStart = start;
                  selectedEnd = end;
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ngày: 04/07/2026'));
    await tester.pumpAndSettle();

    expect(find.text('Chọn khoảng ngày'), findsOneWidget);
    expect(find.byTooltip('Chọn ngày'), findsNothing);

    await tester.tap(find.text('Chọn khoảng ngày'));
    await tester.pumpAndSettle();

    final dialogFinder = find.byType(DateRangePickerDialog);
    expect(dialogFinder, findsOneWidget);
    final pickerSurface = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(AnimatedContainer),
    );
    expect(tester.getSize(pickerSurface), const Size(620, 680));

    Navigator.of(tester.element(dialogFinder)).pop(
      DateTimeRange(start: DateTime(2026, 6, 25), end: DateTime(2026, 7, 4)),
    );
    await tester.pumpAndSettle();

    expect(selectedStart, DateTime(2026, 6, 25));
    expect(selectedEnd, DateTime(2026, 7, 4));
  });
}
