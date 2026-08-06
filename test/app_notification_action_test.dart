import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/app_notification_action.dart';

void main() {
  testWidgets('notification badge caps counts at 99+', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppNotificationIconButton(
          count: 100,
          tooltip: 'Thông báo',
          onPressed: () {},
        ),
      ),
    );

    expect(find.text('99+'), findsOneWidget);
    expect(find.text('100'), findsNothing);
  });

  testWidgets('notification badge remains hidden when count is zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppNotificationIconButton(
          count: 0,
          tooltip: 'Thông báo',
          onPressed: () {},
        ),
      ),
    );

    expect(find.text('99+'), findsNothing);
    expect(find.text('0'), findsNothing);
  });
}
