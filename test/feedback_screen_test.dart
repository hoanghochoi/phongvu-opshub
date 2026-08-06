import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/legacy_widget_finders.dart';
import 'package:phongvu_opshub/features/feedback/presentation/screens/feedback_screen.dart';

void main() {
  testWidgets('Góp ý screen uses current copy and validates required fields', (
    tester,
  ) async {
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    await tester.pumpWidget(const MaterialApp(home: FeedbackScreen()));
    await tester.pump();

    expect(find.byKey(const Key('feedback-ready-state')), findsOneWidget);
    expect(find.byKey(const Key('feedback-form-card')), findsNothing);
    expect(find.text('Gửi phản hồi'), findsNWidgets(2));
    await tester.tap(find.text('Gửi phản hồi').last);
    await tester.pump();

    expect(find.byKey(const Key('feedback-header')), findsOneWidget);
    expect(find.byKey(const Key('feedback-form-card')), findsOneWidget);
    expect(find.byType(Scaffold), findsNothing);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.text('Chia sẻ phản hồi'), findsOneWidget);
    expect(find.text('Sẵn sàng gửi'), findsOneWidget);
    expect(find.text('0/20 ảnh'), findsOneWidget);
    expect(find.text('Chức năng liên quan'), findsOneWidget);
    expect(find.text('Nội dung góp ý'), findsOneWidget);
    expect(find.text('Không bắt buộc, tối đa 20 ảnh'), findsOneWidget);
    expect(find.text('Phản hồi'), findsNothing);

    final submitButton = find.byKey(const ValueKey('submit-suggestion-button'));
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pump();

    expect(find.text('Vui lòng nhập chức năng liên quan'), findsOneWidget);
    expect(find.text('Vui lòng nhập nội dung góp ý'), findsOneWidget);
  });

  testWidgets('Góp ý form follows the approved compact and wide Figma lanes', (
    tester,
  ) async {
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });

    Future<void> pumpAt(Size size, Size expected, double expectedTop) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(key: ValueKey(size), home: const FeedbackScreen()),
      );
      await tester.pump();
      await tester.tap(find.text('Gửi phản hồi').last);
      await tester.pump();
      final form = find.byKey(const Key('feedback-form-card'));
      expect(tester.getSize(form), expected);
      expect(tester.getTopLeft(form).dy, expectedTop);
    }

    await pumpAt(const Size(375, 812), const Size(343, 552), 60);
    await pumpAt(const Size(834, 1112), const Size(343, 552), 60);
    await pumpAt(const Size(1024, 768), const Size(343, 552), 60);
    await pumpAt(const Size(1440, 900), const Size(1126, 590), 148);
  });
}
