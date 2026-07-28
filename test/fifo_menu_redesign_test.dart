import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/navigation/app_router.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('legacy FIFO hub deep link redirects to operations', (
    tester,
  ) async {
    final authProvider = _FakeAuthProvider();
    final router = AppRouter.createRouter(authProvider);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    router.go('/fifo-menu');
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/operations');
    expect(tester.takeException(), isNull);
  });
}

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider() : super(AuthRepository(ApiClient()));

  @override
  User? get user => null;

  @override
  bool get isInitialized => true;

  @override
  bool get isAuthenticated => true;
}
