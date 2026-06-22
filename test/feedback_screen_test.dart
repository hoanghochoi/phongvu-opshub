import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/feedback/presentation/screens/feedback_screen.dart';

void main() {
  testWidgets('Góp ý screen uses current copy and validates required fields', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: FeedbackScreen()));
    await tester.pump();

    expect(find.text('Góp ý'), findsOneWidget);
    expect(find.text('Cùng cải thiện OpsHub'), findsOneWidget);
    expect(find.text('Chức năng liên quan'), findsOneWidget);
    expect(find.text('Nội dung góp ý'), findsOneWidget);
    expect(find.text('Không bắt buộc, tối đa 10 ảnh'), findsOneWidget);
    expect(find.text('Phản hồi'), findsNothing);

    final submitButton = find.byKey(const ValueKey('submit-suggestion-button'));
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pump();

    expect(find.text('Vui lòng nhập chức năng liên quan'), findsOneWidget);
    expect(find.text('Vui lòng nhập nội dung góp ý'), findsOneWidget);
  });
}
