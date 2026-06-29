import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:phongvu_opshub/app/widgets/app_feature_grid.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/sales_report/data/sales_report_repository.dart';
import 'package:phongvu_opshub/features/sales_report/domain/sales_report.dart';
import 'package:phongvu_opshub/features/sales_report/presentation/providers/sales_report_provider.dart';
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
    expect(find.text('Báo cáo sale'), findsNothing);
    expect(find.byType(AppFeatureTile), findsNWidgets(2));
    expect(find.byType(SegmentedButton<String>), findsNothing);

    await tester.tap(find.text('Mua hàng'));
    await tester.pumpAndSettle();

    expect(find.text('Purchased form'), findsOneWidget);
  });

  testWidgets('Báo cáo hub shows sale list only with admin report feature', (
    tester,
  ) async {
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'admin-1',
        email: 'lead@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-area-hcm',
        featureAccess: {'ADMIN_SALES_REPORTS': true},
      ),
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const SalesReportScreen(),
        ),
        GoRoute(
          path: '/admin/sales-reports',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Admin reports'))),
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

    expect(find.text('Mua hàng'), findsNothing);
    expect(find.text('Chưa mua hàng'), findsNothing);
    expect(find.text('Báo cáo sale'), findsOneWidget);
    expect(find.byType(AppFeatureTile), findsOneWidget);

    await tester.tap(find.text('Báo cáo sale'));
    await tester.pumpAndSettle();

    expect(find.text('Admin reports'), findsOneWidget);
  });

  testWidgets('Báo cáo form requires explicit behavior answers', (
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
    final repository = _FakeSalesReportRepository();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<SalesReportProvider>(
            create: (_) => SalesReportProvider(repository),
          ),
        ],
        child: const MaterialApp(home: SalesReportFormScreen.notPurchased()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Có'), findsNothing);
    expect(find.text('Chọn'), findsNWidgets(4));

    await tester.ensureVisible(find.text('Gửi báo cáo'));
    await tester.tap(find.text('Gửi báo cáo'));
    await tester.pumpAndSettle();

    expect(find.text('Vui lòng nhập nhu cầu khách hàng'), findsOneWidget);
    expect(find.text('Vui lòng chọn Tư vấn 3 giải pháp'), findsOneWidget);
    expect(repository.createCalled, isFalse);
  });

  testWidgets(
    'Báo cáo chưa mua opens installment partners and failure reason',
    (tester) async {
      final authProvider = _FakeAuthProvider(
        const User(
          id: 'user-1',
          email: 'sale@phongvu.vn',
          role: 'USER',
          organizationNodeId: 'org-store-cp01',
          featureAccess: {'SALES_REPORT': true},
        ),
      );
      final repository = _FakeSalesReportRepository();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<SalesReportProvider>(
              create: (_) => SalesReportProvider(repository),
            ),
          ],
          child: const MaterialApp(home: SalesReportFormScreen.notPurchased()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('sales-report-installment-checkbox')),
      );
      await tester.tap(
        find.byKey(const ValueKey('sales-report-installment-checkbox')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Đối tác trả góp'), findsOneWidget);
      expect(find.text('Lý do trả góp thất bại'), findsOneWidget);
      expect(find.text('VNPAY - POS'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('sales-report-installment-VNPAY_POS')),
      );
      await tester.ensureVisible(find.text('Gửi báo cáo'));
      await tester.tap(find.text('Gửi báo cáo'));
      await tester.pumpAndSettle();

      expect(find.text('Vui lòng nhập lý do trả góp thất bại'), findsOneWidget);
      expect(repository.createCalled, isFalse);
    },
  );

  test('SalesReportOrderCheck parses multiple category groups', () {
    final check = SalesReportOrderCheck.fromJson({
      'orderCode': '2606290001',
      'categoryGroups': [
        {
          'id': 'NH03',
          'catGroupName': 'Computer components',
          'catGroupNameVi': 'Linh kiện máy tính',
        },
        {
          'id': 'NH08',
          'catGroupName': 'Network and Security equipment',
          'catGroupNameVi': 'Thiết bị mạng và an ninh',
        },
      ],
    });

    expect(check.categoryGroups.map((category) => category.id), [
      'NH03',
      'NH08',
    ]);
    expect(check.categoryGroup?.id, isNull);
  });
}

class _FakeAuthProvider extends AuthProvider {
  final User currentUser;

  _FakeAuthProvider(this.currentUser) : super(AuthRepository(ApiClient()));

  @override
  User? get user => currentUser;
}

class _FakeSalesReportRepository extends SalesReportRepository {
  bool createCalled = false;
  SalesReportInput? lastInput;

  _FakeSalesReportRepository() : super(ApiClient());

  @override
  Future<List<SalesReportCategoryGroup>> fetchCategories({
    bool admin = false,
  }) async {
    return const [
      SalesReportCategoryGroup(
        id: 'NH08',
        catGroupName: 'Network and Security equipment',
        catGroupNameVi: 'Thiết bị mạng và an ninh',
      ),
    ];
  }

  @override
  Future<Map<String, dynamic>> create(SalesReportInput input) async {
    createCalled = true;
    lastInput = input;
    return const {};
  }
}
