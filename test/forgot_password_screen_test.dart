import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:phongvu_opshub/features/auth/presentation/screens/register_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('missing forgot-password account opens register dialog', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final authProvider = _MissingResetAuthProvider();
    final router = GoRouter(
      initialLocation: '/forgot-password',
      routes: [
        GoRoute(
          path: '/forgot-password',
          builder: (context, state) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) {
            return RegisterScreen(initialEmail: state.extra as String?);
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'missing@phongvu.vn',
    );
    await tester.tap(find.text('Gửi mã đổi mật khẩu'));
    await tester.pumpAndSettle();

    expect(authProvider.requestedEmail, 'missing@phongvu.vn');
    expect(find.text('Chưa có tài khoản'), findsOneWidget);
    expect(find.text('Đăng ký tài khoản'), findsOneWidget);

    await tester.tap(find.text('Đăng ký tài khoản'));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterScreen), findsOneWidget);
    final emailField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Email'),
    );
    expect(emailField.controller?.text, 'missing@phongvu.vn');
  });
}

class _MissingResetAuthProvider extends AuthProvider {
  _MissingResetAuthProvider() : super(AuthRepository(ApiClient()));

  String? requestedEmail;

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage =>
      'Email này chưa có tài khoản OpsHub. Vui lòng đăng ký tài khoản trước.';

  @override
  bool get passwordResetAccountMissing => true;

  @override
  Future<bool> requestPasswordReset({required String email}) async {
    requestedEmail = email;
    return false;
  }
}
