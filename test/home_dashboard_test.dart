import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/store_branch.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/home/data/repositories/home_summary_repository.dart';
import 'package:phongvu_opshub/features/home/domain/home_summary.dart';
import 'package:phongvu_opshub/features/home/presentation/providers/home_summary_provider.dart';
import 'package:phongvu_opshub/features/home/presentation/screens/home_screen.dart';
import 'package:phongvu_opshub/features/home/presentation/widgets/home_summary_page.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets(
    'Home dashboard renders scoped summary cards and progress panel',
    (tester) async {
      final authProvider = _FakeAuthProvider(_staffUser());
      final summaryProvider = HomeSummaryProvider(
        _FakeHomeSummaryRepository(
          summary: HomeSummary(
            date: '2026-07-04',
            available: true,
            scope: 'OWN',
            scopeLabel: 'Phạm vi cá nhân',
            scopeDetail: '2 showroom: CP75, CP62',
            coverageLabel: 'Tỷ lệ phủ báo cáo',
            totalRevenue: 125000000,
            totalOrders: 42,
            totalReports: 38,
            reportedOrders: 35,
            unreportedOrders: 7,
            coverageRate: 83.33,
            refreshedAt: DateTime.parse('2026-07-04T03:15:00.000Z'),
          ),
        ),
      );
      addTearDown(summaryProvider.dispose);
      summaryProvider.syncAuth(authProvider.user, isInitialized: true);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<HomeSummaryProvider>.value(
              value: summaryProvider,
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home-summary-page')), findsOneWidget);
      expect(find.byKey(const Key('home-summary-header')), findsOneWidget);
      expect(find.byKey(const Key('home-summary-toolbar')), findsOneWidget);
      expect(find.byKey(const Key('home-summary-grid')), findsOneWidget);
      expect(find.byType(HomeSummaryDatePicker), findsOneWidget);
      expect(find.byType(HomeSummaryRefreshButton), findsOneWidget);
      expect(
        find.byKey(const Key('home-summary-progress-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-summary-card-revenue')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-summary-card-totalOrders')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('home-summary-card-conversionRate')),
          matching: find.text('83.3%'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-summary-card-totalReports')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-summary-card-reportedOrders')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-summary-card-unreportedOrders')),
        findsOneWidget,
      );
      final homeSummaryColumn = tester.widget<Column>(
        find.byKey(const Key('home-summary-page')),
      );
      final structuredChildren = homeSummaryColumn.children
          .where((child) => child is! SizedBox)
          .toList();
      expect(structuredChildren[0], isA<HomeSummaryHeader>());
      expect(structuredChildren[1], isA<HomeSummaryToolbar>());
      expect(structuredChildren[2], isA<SummaryCardGrid>());
      expect(structuredChildren[3], isA<ReportProgressPanel>());
      expect(find.text('Trang chủ vận hành'), findsOneWidget);
      expect(find.text('Doanh số trong ngày'), findsOneWidget);
      expect(find.text('125.000.000 VND'), findsOneWidget);
      expect(
        find.byKey(const Key('home-summary-progress-donut')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('home-operations-shortcut')), findsOneWidget);
      expect(find.text('Công cụ nhanh'), findsOneWidget);
      expect(find.text('Đối soát'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('home-summary-page')),
          matching: find.byKey(const Key('home-operations-shortcut')),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('Home dashboard shows neutral unavailable state from scope API', (
    tester,
  ) async {
    final authProvider = _FakeAuthProvider(_staffUser());
    final summaryProvider = HomeSummaryProvider(
      _FakeHomeSummaryRepository(
        summary: HomeSummary(
          date: '2026-07-04',
          available: false,
          scope: 'UNAVAILABLE',
          scopeLabel: 'Chưa sẵn sàng',
          scopeDetail: '',
          coverageLabel: 'Tỷ lệ phủ báo cáo',
          totalRevenue: 0,
          totalOrders: 0,
          totalReports: 0,
          reportedOrders: 0,
          unreportedOrders: 0,
          coverageRate: 0,
          refreshedAt: DateTime.parse('2026-07-04T03:15:00.000Z'),
          unavailableMessage:
              'Tài khoản hiện chưa có quyền xem tổng quan báo cáo sale.',
        ),
      ),
    );
    addTearDown(summaryProvider.dispose);
    summaryProvider.syncAuth(authProvider.user, isInitialized: true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<HomeSummaryProvider>.value(
            value: summaryProvider,
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-summary-unavailable')), findsOneWidget);
    expect(
      find.text('Dashboard chưa khả dụng cho tài khoản này'),
      findsOneWidget,
    );
    expect(
      find.text('Tài khoản hiện chưa có quyền xem tổng quan báo cáo sale.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('home-summary-grid')), findsNothing);
  });
}

class _FakeAuthProvider extends AuthProvider {
  final User currentUser;

  _FakeAuthProvider(this.currentUser) : super(AuthRepository(ApiClient()));

  @override
  User? get user => currentUser;
}

class _FakeHomeSummaryRepository extends HomeSummaryRepository {
  final HomeSummary summary;

  _FakeHomeSummaryRepository({required this.summary}) : super(ApiClient());

  @override
  Future<HomeSummary> fetchSummary({required String date}) async => summary;
}

User _staffUser() {
  return const User(
    id: 'user-1',
    email: 'staff@phongvu.vn',
    name: 'Dashboard Staff',
    role: 'USER',
    organizationNodeId: 'org-store-cp75',
    assignedStores: [
      StoreBranch(id: 'store-75', storeId: 'CP75', storeName: 'CP75'),
      StoreBranch(id: 'store-62', storeId: 'CP62', storeName: 'CP62'),
    ],
    featureAccess: {'FIFO': true, 'WARRANTY': true, 'FEEDBACK': true},
  );
}
