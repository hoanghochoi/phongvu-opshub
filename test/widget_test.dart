import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App starts with login screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    // Build our app and trigger a frame.
    await tester.pumpWidget(const App());
    await tester.pump();

    // Verify that login screen is shown
    expect(find.text('PhongVu OpsHub'), findsOneWidget);
    expect(find.text('Đăng nhập'), findsOneWidget);
    expect(find.text('Đăng nhập bằng Google'), findsOneWidget);
  });
}
