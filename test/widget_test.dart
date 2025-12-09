import 'package:flutter_test/flutter_test.dart';
import 'package:pv_assistant/app/app.dart';

void main() {
  testWidgets('App starts with login screen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const App());

    // Verify that login screen is shown
    expect(find.text('PV Assistant'), findsOneWidget);
    expect(find.text('Đăng nhập'), findsOneWidget);
  });
}
