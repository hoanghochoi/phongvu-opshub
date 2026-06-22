import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:phongvu_opshub/app/app.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/auth/presentation/screens/email_check_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App starts with login screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    expect(find.text('PhongVu OpsHub'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Mật khẩu'), findsOneWidget);
    expect(find.text('Đăng nhập', skipOffstage: false), findsWidgets);
    expect(find.text('Đăng ký'), findsOneWidget);
  });

  testWidgets(
    'expired session dialog uses the root navigator and returns login',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});

      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();

      final loginContext = tester.element(find.byType(EmailCheckScreen));
      final authProvider = Provider.of<AuthProvider>(
        loginContext,
        listen: false,
      );
      authProvider.setSessionExpiredDialogMessageForTesting(
        'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
      );

      await tester.pump();
      await tester.pump();

      expect(find.text('Phiên đăng nhập đã hết hạn'), findsOneWidget);
      expect(find.text('Đăng nhập lại'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Đăng nhập lại'));
      await tester.pumpAndSettle();

      expect(find.byType(EmailCheckScreen), findsOneWidget);
      expect(authProvider.sessionExpiredDialogMessage, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
