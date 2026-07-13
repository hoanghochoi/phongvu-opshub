import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/navigation/app_router.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:provider/provider.dart';

void main() {
  group('AppRouter.initialLocationForUri', () {
    test('keeps the public help path on a direct browser entry', () {
      expect(
        AppRouter.initialLocationForUri(
          Uri.parse('https://opshub-staging.hoanghochoi.com/help'),
        ),
        '/help',
      );
    });

    test('keeps an existing hash route', () {
      expect(
        AppRouter.initialLocationForUri(
          Uri.parse('https://opshub-staging.hoanghochoi.com/#/operations'),
        ),
        '/operations',
      );
    });

    test('uses home for an ordinary root entry', () {
      expect(
        AppRouter.initialLocationForUri(
          Uri.parse('https://opshub-staging.hoanghochoi.com/'),
        ),
        '/home',
      );
    });
  });

  testWidgets('public help bypasses auth initialization loading', (
    tester,
  ) async {
    final authProvider = _InitializingAuthProvider();
    final router = AppRouter.createRouter(
      authProvider,
      helpScreen: const Text('public-help-ready'),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    router.go('/help');
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/help');
    expect(find.text('public-help-ready'), findsOneWidget);
  });
}

class _InitializingAuthProvider extends AuthProvider {
  _InitializingAuthProvider() : super(AuthRepository(ApiClient()));

  @override
  bool get isInitialized => false;

  @override
  bool get isAuthenticated => false;
}
