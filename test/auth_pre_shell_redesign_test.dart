import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/legacy_widget_finders.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/auth/presentation/screens/assignment_pending_screen.dart';
import 'package:phongvu_opshub/features/auth/presentation/screens/email_check_screen.dart';
import 'package:phongvu_opshub/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:phongvu_opshub/features/auth/presentation/screens/register_screen.dart';
import 'package:phongvu_opshub/features/auth/presentation/widgets/auth_screen_shell.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets('auth entry screens render inside redesign shell', (
    WidgetTester tester,
  ) async {
    await _pumpAuthScreen(tester, const EmailCheckScreen());
    expect(find.byType(AuthScreenShell), findsOneWidget);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.text('Đăng nhập'), findsWidgets);
    expect(find.text('Dùng tài khoản nội bộ để tiếp tục.'), findsOneWidget);

    await _pumpAuthScreen(
      tester,
      const RegisterScreen(initialEmail: 'new.user@phongvu.vn'),
    );
    expect(find.byType(AuthScreenShell), findsOneWidget);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.text('Đăng ký tài khoản'), findsOneWidget);
    expect(find.text('Gửi mã xác thực email'), findsOneWidget);

    await _pumpAuthScreen(tester, const ForgotPasswordScreen());
    expect(find.byType(AuthScreenShell), findsOneWidget);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.text('Quên mật khẩu'), findsOneWidget);
    expect(find.text('Gửi mã đổi mật khẩu'), findsOneWidget);

    await _pumpAuthScreen(tester, const AssignmentPendingScreen());
    expect(find.byType(AuthScreenShell), findsOneWidget);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.text('Chờ gán tổ chức'), findsOneWidget);
    expect(find.text('Tải lại trạng thái'), findsOneWidget);
    expect(find.text('Đăng xuất'), findsOneWidget);
  });
}

Future<void> _pumpAuthScreen(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>(
      create: (_) => _IdleAuthProvider(),
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

class _IdleAuthProvider extends AuthProvider {
  _IdleAuthProvider() : super(AuthRepository(ApiClient()));

  @override
  bool get isLoading => false;
}
