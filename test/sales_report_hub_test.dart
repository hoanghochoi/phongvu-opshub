import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:phongvu_opshub/app/widgets/app_feature_grid.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/sales_report/presentation/screens/sales_report_screen.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets('Báo cáo opens a function hub instead of report tabs', (
    tester,
  ) async {
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'user-1',
        email: 'sale@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-store-cp01',
        featureAccess: {'SALES_REPORT': true},
      ),
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const SalesReportScreen(),
        ),
        GoRoute(
          path: '/sales-reports/purchased',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Purchased form'))),
        ),
        GoRoute(
          path: '/sales-reports/not-purchased',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Not purchased form'))),
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

    expect(find.text('Mua hàng'), findsOneWidget);
    expect(find.text('Chưa mua hàng'), findsOneWidget);
    expect(find.byType(AppFeatureTile), findsNWidgets(2));
    expect(find.byType(SegmentedButton<String>), findsNothing);

    await tester.tap(find.text('Mua hàng'));
    await tester.pumpAndSettle();

    expect(find.text('Purchased form'), findsOneWidget);
  });
}

class _FakeAuthProvider extends AuthProvider {
  final User currentUser;

  _FakeAuthProvider(this.currentUser) : super(AuthRepository(ApiClient()));

  @override
  User? get user => currentUser;
}
