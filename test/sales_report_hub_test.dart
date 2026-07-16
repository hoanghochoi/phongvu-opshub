import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/navigation/app_router.dart';
import 'package:phongvu_opshub/app/widgets/app_buttons.dart';
import 'package:phongvu_opshub/app/widgets/app_combobox.dart';
import 'helpers/legacy_widget_finders.dart';
import 'package:go_router/go_router.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/realtime_connection_manager.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/store_branch.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/sales_report/data/sales_report_repository.dart';
import 'package:phongvu_opshub/features/sales_report/domain/sales_report.dart';
import 'package:phongvu_opshub/features/sales_report/presentation/providers/sales_report_provider.dart';
import 'package:phongvu_opshub/features/sales_report/presentation/screens/sales_report_admin_screen.dart';
import 'package:phongvu_opshub/features/sales_report/presentation/screens/sales_report_screen.dart';
import 'package:phongvu_opshub/features/sales_report/presentation/widgets/sales_report_export_menu.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets('Báo cáo opens a two-column order cockpit', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider(
      const User(
        id: 'user-1',
        email: 'sale@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-store-cp01',
        featureAccess: {'SALES_REPORT': true},
      ),
    );
    final repository = _FakeSalesReportRepository(unreportedTotal: 7998);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: SalesReportScreen()),
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
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<SalesReportProvider>(
            create: (_) => SalesReportProvider(repository),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.fetchOrdersCount, 1);
    expect(
      find.byKey(const Key('sales-report-workspace-header')),
      findsNothing,
    );
    expect(find.text('Đơn cần báo cáo'), findsNothing);
    expect(find.text('Báo cáo mua thủ công'), findsOneWidget);
    expect(find.text('Báo cáo chưa mua'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Báo cáo mua thủ công')).dy,
      tester.getTopLeft(find.text('Báo cáo chưa mua')).dy,
    );
    expect(find.text('Đã báo cáo'), findsOneWidget);
    expect(find.text('Chưa báo cáo'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Chưa báo cáo')).dx,
      lessThan(tester.getTopLeft(find.text('Đã báo cáo')).dx),
    );
    expect(find.text('2607010001'), findsOneWidget);
    expect(find.text('2607010002'), findsOneWidget);
    expect(find.text('CP62 • Sale CP62'), findsOneWidget);
    expect(find.textContaining('ĐỊA ĐIỂM KINH DOANH'), findsNothing);
    expect(find.text('7.998'), findsWidgets);
    expect(find.text('Trang 1/400'), findsOneWidget);
    expect(find.text('Trước'), findsNothing);
    expect(find.text('Sau'), findsNothing);
    expect(find.byType(SegmentedButton<String>), findsNothing);

    await tester.ensureVisible(find.byTooltip('Trang sau'));
    await tester.tap(find.byTooltip('Trang sau'));
    await tester.pumpAndSettle();

    expect(repository.fetchOrdersCount, 2);
    expect(repository.lastOrdersQuery?.reportedPage, 0);
    expect(repository.lastOrdersQuery?.unreportedPage, 1);
    expect(repository.lastOrdersQuery?.limit, 20);

    await tester.ensureVisible(find.text('Báo cáo mua thủ công'));
    await tester.tap(find.text('Báo cáo mua thủ công'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Báo cáo mua hàng'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/');

    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Báo cáo chưa mua'));
    await tester.tap(find.text('Báo cáo chưa mua'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Báo cáo chưa mua hàng'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/');
  });

  testWidgets('Báo cáo mobile uses compact hero, tabs and filter sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

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
        child: const MaterialApp(home: Scaffold(body: SalesReportScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('sales-report-workspace-header')),
      findsNothing,
    );
    expect(find.text('Chờ báo cáo'), findsOneWidget);
    expect(find.text('Hoàn tất'), findsOneWidget);
    expect(find.text('Đã mua (nhập tay)'), findsOneWidget);
    expect(find.text('Chưa mua'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Đã mua (nhập tay)')).dy,
      tester.getTopLeft(find.text('Chưa mua')).dy,
    );
    expect(find.text('Chưa báo cáo (21)'), findsOneWidget);
    expect(find.text('Đã báo cáo (1)'), findsOneWidget);
    expect(find.text('2607010002'), findsOneWidget);
    expect(find.text('2607010001'), findsNothing);

    await tester.tap(find.text('Đã báo cáo (1)'));
    await tester.pumpAndSettle();

    expect(find.text('2607010001'), findsOneWidget);

    await tester.tap(find.text('Lọc'));
    await tester.pumpAndSettle();

    expect(find.text('Bộ lọc nâng cao'), findsOneWidget);
    expect(find.text('Áp dụng'), findsOneWidget);
  });

  testWidgets('Báo cáo app route provides the sales report provider', (
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
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: MaterialApp(
          home: AppRouter.buildSalesReportHubRoute(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repository.fetchOrdersCount, 1);
    expect(find.text('Đã báo cáo'), findsOneWidget);
    expect(find.text('Chưa báo cáo'), findsOneWidget);
  });

  testWidgets('manager cockpit filters orders by date, showroom and user', (
    tester,
  ) async {
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'manager-1',
        email: 'manager@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-store-cp01',
        featureAccess: {'SALES_REPORT': true, 'ADMIN_SALES_REPORTS': true},
      ),
    );
    final repository = _FakeSalesReportRepository(managedScope: true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<SalesReportProvider>(
            create: (_) => SalesReportProvider(
              repository,
              now: () => DateTime(2026, 7, 1),
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SalesReportScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ngày: 01/07/2026'), findsOneWidget);
    expect(
      find.text(
        'Không chọn khoảng ngày: hệ thống mặc định lấy 30 ngày gần nhất.',
      ),
      findsNothing,
    );
    expect(find.text('Showroom'), findsOneWidget);
    expect(find.text('Tất cả'), findsWidgets);
    expect(find.text('Nhân viên: Tất cả'), findsNothing);
    expect(find.text('Lọc'), findsOneWidget);
    expect(repository.lastOrdersQuery?.startDate, DateTime(2026, 7, 1));
    expect(repository.lastOrdersQuery?.endDate, DateTime(2026, 7, 1));

    await tester.tap(find.text('Ngày: 01/07/2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7 ngày gần nhất'));
    await tester.tap(find.byKey(const Key('date-range-apply')));
    await tester.pumpAndSettle();

    expect(repository.lastOrdersQuery?.startDate, DateTime(2026, 6, 25));
    expect(repository.lastOrdersQuery?.endDate, DateTime(2026, 7, 1));

    await tester.tap(find.text('Lọc'));
    await tester.pumpAndSettle();

    expect(find.text('Bộ lọc nâng cao'), findsOneWidget);
    expect(find.text('Nhân viên'), findsOneWidget);
    expect(find.text('Tất cả'), findsWidgets);

    await tester.tap(find.byTooltip('Đóng bộ lọc'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AppCombobox<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('CP01 - Phong Vu CP01'));
    await tester.pumpAndSettle();

    expect(repository.lastOrdersQuery?.storeCode, 'CP01');
    expect(repository.lastOrdersQuery?.startDate, DateTime(2026, 6, 25));
    expect(repository.lastOrdersQuery?.endDate, DateTime(2026, 7, 1));
    expect(repository.lastOrdersQuery?.reportedPage, 0);
    expect(repository.lastOrdersQuery?.unreportedPage, 0);
  });

  testWidgets('Báo cáo opens purchased dialog from unreported order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'user-1',
        email: 'sale@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-store-cp01',
        featureAccess: {'SALES_REPORT': true},
      ),
    );
    final repository = _FakeSalesReportRepository(
      orderCheckOverrides: const {
        'customerType': 'PERSONAL',
        'customerIsStudent': true,
        'promotionCodes': ['EXAM_SCORE_EXCHANGE', 'STUDENT'],
        'installmentNeed': true,
        'installmentLoanAmount': 5000000,
      },
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<SalesReportProvider>(
            create: (_) => SalesReportProvider(repository),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SalesReportScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('2607010002'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repository.checkOrderCount, 1);
    expect(find.text('Báo cáo mua hàng'), findsOneWidget);
    expect(find.text('Đơn hàng đã kiểm tra'), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(
            _checkboxTileByKey('sales-report-customer-type-PERSONAL'),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            _checkboxTileByKey('sales-report-customer-student'),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            _checkboxTileByKey('sales-report-promotion-EXAM_SCORE_EXCHANGE'),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            _checkboxTileByKey('sales-report-promotion-STUDENT'),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            _checkboxTileByKey('sales-report-installment-checkbox'),
          )
          .value,
      isTrue,
    );
    expect(find.text('5.000.000'), findsOneWidget);

    final header = find.byKey(const Key('sales-report-form-header'));
    final headerTop = tester.getTopLeft(header).dy;
    final dialogScroll = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(SingleChildScrollView),
    );
    await tester.drag(dialogScroll, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header).dy, headerTop);
  });

  testWidgets('Báo cáo blocks unpaid order submission and returns modal to top', (
    tester,
  ) async {
    final repository = _FakeSalesReportRepository(
      orderCheckOverrides: const {
        'order': {'paymentStatus': 'pending_payment'},
      },
    );

    final authProvider = _FakeAuthProvider(
      const User(
        id: 'user-1',
        email: 'sale@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-store-cp01',
        featureAccess: {'SALES_REPORT': true},
      ),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<SalesReportProvider>(
            create: (_) => SalesReportProvider(repository),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SalesReportFormScreen.purchased(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.enterText(
      _textFormFieldByParentKey('sales-report-order-code-field'),
      '2607010002',
    );
    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.maxScrollExtent);

    final checkButton = tester.widget<AppSecondaryButton>(
      find.widgetWithText(AppSecondaryButton, 'Kiểm tra đơn hàng'),
    );
    checkButton.onPressed!.call();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(
      find.text(
        'Đơn chưa thanh toán, vui lòng vào spos bấm Thanh toán lại hoặc Hủy đơn.',
      ),
      findsOneWidget,
    );
    expect(position.pixels, 0);
    expect(
      tester
          .widget<AppPrimaryButton>(
            find.widgetWithText(AppPrimaryButton, 'Gửi báo cáo'),
          )
          .onPressed,
      isNull,
    );
    expect(repository.createCalled, isFalse);
  });

  testWidgets('Báo cáo hub omits duplicate export and list actions', (
    tester,
  ) async {
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'admin-1',
        email: 'lead@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-area-hcm',
        featureAccess: {'SALES_REPORT': true, 'ADMIN_SALES_REPORTS': true},
      ),
    );
    final repository = _FakeSalesReportRepository();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: SalesReportScreen()),
        ),
        GoRoute(
          path: '/admin/sales-reports',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Admin reports'))),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<SalesReportProvider>(
            create: (_) => SalesReportProvider(repository),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('sales-report-workspace-header')),
      findsNothing,
    );
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.text('Báo cáo chưa mua'), findsOneWidget);
    expect(find.text('Xuất file'), findsNothing);
    expect(find.text('Danh sách'), findsNothing);
    expect(find.text('Đã báo cáo'), findsOneWidget);
    expect(find.text('Chưa báo cáo'), findsOneWidget);
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
        child: const MaterialApp(
          home: Scaffold(body: SalesReportFormScreen.notPurchased()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CheckboxListTile), findsWidgets);
    expect(find.text('Loại khách hàng'), findsOneWidget);
    expect(find.text('Tên khách hàng'), findsOneWidget);

    await tester.ensureVisible(find.text('Gửi báo cáo'));
    await tester.tap(find.text('Gửi báo cáo'));
    await tester.pumpAndSettle();

    expect(find.text('Vui lòng nhập tên khách hàng'), findsOneWidget);
    expect(find.text('Vui lòng nhập nhu cầu khách hàng'), findsOneWidget);
    expect(find.text('Vui lòng chọn loại khách hàng'), findsOneWidget);
    expect(find.text('Vui lòng chọn Tư vấn 3 giải pháp'), findsOneWidget);
    expect(repository.createCalled, isFalse);
  });

  testWidgets('Báo cáo mua hàng requires CTKM áp dụng', (tester) async {
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
        child: const MaterialApp(
          home: Scaffold(
            body: SalesReportFormScreen.purchased(
              initialOrderCode: '2607010002',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Gửi báo cáo'));
    await tester.tap(find.text('Gửi báo cáo'));
    await tester.pumpAndSettle();

    expect(find.text('Vui lòng chọn CTKM áp dụng'), findsOneWidget);
    expect(repository.createCalled, isFalse);
  });

  testWidgets('Báo cáo form scrolls to top after successful submit', (
    tester,
  ) async {
    final repository = _FakeSalesReportRepository();
    await _pumpNotPurchasedForm(tester, repository);

    await _tapVisible(
      tester,
      _checkboxTileByKey('sales-report-customer-type-PERSONAL'),
    );
    await tester.ensureVisible(
      _textFormFieldByParentKey('sales-report-customer-name-field'),
    );
    await tester.enterText(
      _textFormFieldByParentKey('sales-report-customer-name-field'),
      'Nguyễn Văn A',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('sales-report-category-NH08')),
    );
    await tester.ensureVisible(
      _textFormFieldByParentKey('sales-report-customer-need-field'),
    );
    await tester.enterText(
      _textFormFieldByParentKey('sales-report-customer-need-field'),
      'Laptop văn phòng',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('sales-report-answer-Tư vấn 3 giải pháp-YES')),
    );
    await _tapVisible(
      tester,
      find.byKey(
        const ValueKey('sales-report-answer-KH đã được trải nghiệm-YES'),
      ),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('sales-report-answer-KH quét Zalo-YES')),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('sales-report-answer-KH tải ứng dụng PV-YES')),
    );
    await _tapVisible(
      tester,
      find.byKey(
        const ValueKey('sales-report-not-purchased-reason-PRICE_HESITATION'),
      ),
    );

    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    await tester.ensureVisible(find.text('Gửi báo cáo'));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));

    await tester.tap(find.text('Gửi báo cáo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(repository.createCalled, isTrue);
    expect(repository.lastInput?.customerName, 'Nguyễn Văn A');
    expect(repository.lastInput?.entrySource, isNull);
    expect(position.pixels, 0);
  });

  testWidgets('Học sinh - Sinh viên is a child option of Cá nhân', (
    tester,
  ) async {
    final repository = _FakeSalesReportRepository();
    await _pumpNotPurchasedForm(tester, repository);

    final businessFinder = _checkboxTileByKey(
      'sales-report-customer-type-BUSINESS',
    );
    final personalFinder = _checkboxTileByKey(
      'sales-report-customer-type-PERSONAL',
    );
    final studentFinder = _checkboxTileByKey('sales-report-customer-student');

    await tester.ensureVisible(studentFinder);
    await tester.tap(studentFinder);
    await tester.pumpAndSettle();

    expect(tester.widget<CheckboxListTile>(personalFinder).value, isTrue);
    expect(tester.widget<CheckboxListTile>(studentFinder).value, isTrue);
    expect(tester.widget<CheckboxListTile>(businessFinder).value, isFalse);

    await tester.ensureVisible(businessFinder);
    await tester.tap(businessFinder);
    await tester.pumpAndSettle();

    expect(tester.widget<CheckboxListTile>(businessFinder).value, isTrue);
    expect(tester.widget<CheckboxListTile>(personalFinder).value, isFalse);
    expect(tester.widget<CheckboxListTile>(studentFinder).value, isFalse);
    expect(tester.widget<CheckboxListTile>(personalFinder).onChanged, isNull);
    expect(tester.widget<CheckboxListTile>(studentFinder).onChanged, isNull);
  });

  testWidgets('Số tiền vay formats thousand separators while typing', (
    tester,
  ) async {
    final repository = _FakeSalesReportRepository();
    await _pumpNotPurchasedForm(tester, repository);

    await tester.ensureVisible(
      find.byKey(const ValueKey('sales-report-installment-checkbox')),
    );
    await tester.tap(
      find.byKey(const ValueKey('sales-report-installment-checkbox')),
    );
    await tester.pumpAndSettle();

    final loanField = find.descendant(
      of: find.byKey(const ValueKey('sales-report-installment-loan-amount')),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(loanField, '5000000');
    await tester.pump();

    expect(find.text('5.000.000'), findsOneWidget);
  });

  testWidgets(
    'Báo cáo chưa mua opens installment approval and no-installment reason',
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
          child: const MaterialApp(
            home: Scaffold(body: SalesReportFormScreen.notPurchased()),
          ),
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
      expect(find.text('Hồ sơ được duyệt không'), findsOneWidget);
      expect(find.text('Lý do không trả góp'), findsOneWidget);
      expect(find.text('VNPAY - POS'), findsOneWidget);
      expect(find.text('Mirae Asset'), findsOneWidget);
      expect(find.text('MPOS'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('sales-report-installment-VNPAY_POS')),
      );
      await tester.ensureVisible(find.text('Gửi báo cáo'));
      await tester.tap(find.text('Gửi báo cáo'));
      await tester.pumpAndSettle();

      expect(
        find.text('Vui lòng chọn hồ sơ được duyệt hay chưa'),
        findsOneWidget,
      );
      expect(find.text('Vui lòng chọn lý do không trả góp'), findsOneWidget);
      expect(repository.createCalled, isFalse);
    },
  );

  testWidgets('Báo cáo bán hàng admin filters list by selected date range', (
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
    final repository = _FakeSalesReportRepository();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<SalesReportProvider>(
            create: (_) => SalesReportProvider(
              repository,
              now: () => DateTime(2026, 7, 4, 9),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SalesReportAdminScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.fetchListCount, 1);
    expect(
      find.byKey(const Key('sales-report-admin-workspace-header')),
      findsOneWidget,
    );
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.text('Ngày: 04/07/2026'), findsOneWidget);
    expect(
      find.text(
        'Không chọn khoảng ngày: hệ thống mặc định lấy 30 ngày gần nhất.',
      ),
      findsNothing,
    );
    expect(find.text('Loại'), findsOneWidget);
    expect(find.text('Tất cả'), findsWidgets);
    expect(find.text('Xuất file'), findsOneWidget);
    expect(repository.lastListQuery?.startDate, DateTime(2026, 7, 4));
    expect(repository.lastListQuery?.endDate, DateTime(2026, 7, 4));

    await tester.tap(find.text('Xuất file'));
    await tester.pumpAndSettle();
    expect(find.text('HVTC'), findsOneWidget);
    expect(find.text('Doanh số'), findsOneWidget);
    expect(find.text('Trả góp'), findsOneWidget);

    await tester.tap(find.text('Ngày: 04/07/2026'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('date-range-desktop')), findsOneWidget);
    expect(find.byKey(const Key('from-calendar')), findsOneWidget);
    expect(find.byKey(const Key('to-calendar')), findsOneWidget);
  });

  testWidgets('Báo cáo bán hàng admin filters by assigned SR', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider(
      const User(
        id: 'admin-1',
        email: 'lead@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-area-hcm',
        assignedStores: [
          StoreBranch(id: 'store-1', storeId: 'CP01', storeName: 'PV CP01'),
          StoreBranch(id: 'store-2', storeId: 'CP02', storeName: 'PV CP02'),
        ],
        featureAccess: {'ADMIN_SALES_REPORTS': true},
      ),
    );
    final repository = _FakeSalesReportRepository();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<SalesReportProvider>(
            create: (_) => SalesReportProvider(
              repository,
              now: () => DateTime(2026, 7, 4, 9),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SalesReportAdminScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.lastListQuery?.storeIds, isEmpty);
    expect(find.text('Showroom'), findsWidgets);
    expect(find.text('Tất cả showroom'), findsWidgets);

    final storeFilter = find.byType(AppCombobox<String>).at(1);
    await tester.tap(storeFilter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('CP02 - PV CP02').last);
    await tester.pumpAndSettle();

    expect(repository.fetchListCount, 2);
    expect(repository.lastListQuery?.storeIds, ['CP02']);
    expect(find.text('CP02 - PV CP02'), findsWidgets);
  });

  testWidgets('Báo cáo bán hàng admin loads SR filter for super admin', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider(
      const User(
        id: 'super-admin-1',
        email: 'admin@phongvu.vn',
        role: 'SUPER_ADMIN',
        featureAccess: {'ADMIN_SALES_REPORTS': true},
      ),
    );
    final repository = _FakeSalesReportRepository();
    final authRepository = _FakeStoreAuthRepository(const [
      StoreBranch(id: 'store-1', storeId: 'CP01', storeName: 'PV CP01'),
      StoreBranch(id: 'store-2', storeId: 'CP02', storeName: 'PV CP02'),
    ]);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<SalesReportProvider>(
            create: (_) => SalesReportProvider(
              repository,
              now: () => DateTime(2026, 7, 4, 9),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SalesReportAdminScreen(authRepository: authRepository),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(authRepository.getStoresCount, 1);
    expect(repository.lastListQuery?.storeIds, isEmpty);
    expect(find.text('Showroom'), findsWidgets);
    expect(find.text('Tất cả showroom'), findsWidgets);

    final storeFilter = find.byType(AppCombobox<String>).at(1);
    await tester.tap(storeFilter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('CP02 - PV CP02').last);
    await tester.pumpAndSettle();

    expect(repository.fetchListCount, 2);
    expect(repository.lastListQuery?.storeIds, ['CP02']);
  });

  testWidgets('Sales report export menu emits selected export type', (
    tester,
  ) async {
    String? selectedType;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              child: SalesReportExportMenuButton(
                isExporting: false,
                onExport: (type) => selectedType = type,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Xuất file'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Doanh số'));
    await tester.pumpAndSettle();

    expect(selectedType, 'REVENUE');
  });

  test('SalesReportOrderCheck parses multiple category groups', () {
    final check = SalesReportOrderCheck.fromJson({
      'orderCode': '2606290001',
      'customerPhone': '0901234567',
      'customerType': 'BUSINESS',
      'customerTypeLabel': 'Doanh nghiệp',
      'paymentMethods': ['cash', 'bank_transfer'],
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
    expect(check.customerType, 'BUSINESS');
    expect(check.customerPhone, '0901234567');
    expect(check.paymentMethods, ['cash', 'bank_transfer']);
  });

  test('SalesReportQuery serializes admin date filters and export type', () {
    final query = SalesReportQuery(
      reportType: 'PURCHASED',
      exportType: 'REVENUE',
      startDate: DateTime(2026, 6, 1, 15, 30),
      endDate: DateTime(2026, 6, 30, 23, 59),
      reporter: 'sale.cp01@phongvu.vn',
      storeIds: const ['CP01'],
      page: 2,
      limit: 50,
    );

    expect(query.toQueryParameters(), {
      'reportType': 'PURCHASED',
      'exportType': 'REVENUE',
      'startDate': '2026-06-01',
      'endDate': '2026-06-30',
      'reporter': 'sale.cp01@phongvu.vn',
      'storeIds': 'CP01',
      'page': '2',
      'limit': '50',
    });
  });

  test(
    'SalesReportOrdersQuery serializes report date range, pages and limit',
    () {
      final query = SalesReportOrdersQuery(
        startDate: DateTime(2026, 6, 25, 9, 30),
        endDate: DateTime(2026, 7, 1, 23, 59),
        reportedPage: 2,
        unreportedPage: 3,
        limit: 75,
        storeCode: 'CP01',
        userEmail: 'sale.cp01@phongvu.vn',
      );

      expect(query.toQueryParameters(), {
        'startDate': '2026-06-25',
        'endDate': '2026-07-01',
        'storeCode': 'CP01',
        'userEmail': 'sale.cp01@phongvu.vn',
        'reportedPage': '2',
        'unreportedPage': '3',
        'limit': '75',
      });
    },
  );

  test('SalesReportOrderCockpit parses reported and unreported orders', () {
    final cockpit = SalesReportOrderCockpit.fromJson({
      'date': '2026-07-01',
      'startDate': '2026-06-25',
      'endDate': '2026-07-01',
      'syncSucceeded': true,
      'syncCount': 2,
      'scope': 'MANAGED_SCOPE',
      'selectedStoreCode': 'CP01',
      'selectedUserEmail': 'sale.cp01@phongvu.vn',
      'storeOptions': [
        {'value': 'CP01', 'label': 'CP01 - Phong Vu CP01'},
      ],
      'userOptions': [
        {
          'value': 'sale.cp01@phongvu.vn',
          'label': 'Sale CP01 - sale.cp01@phongvu.vn',
        },
      ],
      'limit': 20,
      'reportedPage': 1,
      'reportedTotal': 21,
      'unreportedPage': 2,
      'unreportedTotal': 42,
      'reportedOrders': [
        {'status': 'REPORTED', 'orderCode': '2607010001'},
      ],
      'unreportedOrders': [
        {'status': 'UNREPORTED', 'orderCode': '2607010002'},
      ],
    });

    expect(cockpit.startDate, '2026-06-25');
    expect(cockpit.endDate, '2026-07-01');

    expect(cockpit.scope, 'MANAGED_SCOPE');
    expect(cockpit.selectedStoreCode, 'CP01');
    expect(cockpit.selectedUserEmail, 'sale.cp01@phongvu.vn');
    expect(cockpit.storeOptions.single.value, 'CP01');
    expect(cockpit.userOptions.single.value, 'sale.cp01@phongvu.vn');
    expect(cockpit.limit, 20);
    expect(cockpit.reportedPage, 1);
    expect(cockpit.reportedTotal, 21);
    expect(cockpit.unreportedPage, 2);
    expect(cockpit.unreportedTotal, 42);
    expect(cockpit.reportedOrders.single.isReported, isTrue);
    expect(cockpit.unreportedOrders.single.orderCode, '2607010002');
  });

  test(
    'SalesReportProvider filters and coalesces shared realtime v2 events',
    () async {
      final repository = _FakeSalesReportRepository(managedScope: true);
      final realtime = _FakeRealtimeClient();
      final provider = SalesReportProvider(
        repository,
        now: () => DateTime(2026, 7, 1, 9),
        realtimeClient: realtime,
        realtimeDebounce: const Duration(milliseconds: 15),
        realtimeMaxWait: const Duration(milliseconds: 80),
      );

      await provider.initialize(
        const User(
          id: 'manager-1',
          email: 'manager.cp01@phongvu.vn',
          role: 'USER',
          jobRoleCode: 'STORE_MANAGER',
          storeId: 'CP01',
          featureAccess: {'SALES_REPORT': true, 'ADMIN_SALES_REPORTS': true},
        ),
        orders: true,
        categories: false,
      );
      expect(repository.fetchOrdersCount, 1);

      realtime.addEvent(
        _salesReportEnvelope(
          id: 'wrong-topic',
          topic: 'home.summary',
          dates: const ['2026-07-01'],
        ),
      );
      realtime.addEvent(
        _salesReportEnvelope(id: 'relevant-1', dates: const ['2026-07-01']),
      );
      realtime.addEvent(
        _salesReportEnvelope(id: 'relevant-2', dates: const ['2026-07-01']),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(repository.fetchOrdersCount, 1);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(repository.fetchOrdersCount, 2);

      realtime.addEvent(
        _salesReportEnvelope(id: 'outside-date', dates: const ['2026-07-02']),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(repository.fetchOrdersCount, 2);

      realtime.requestSync(RealtimeSyncReason.reconnected);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(repository.fetchOrdersCount, 3);

      provider.dispose();
      await realtime.dispose();
    },
  );
}

RealtimeEnvelope _salesReportEnvelope({
  required String id,
  String topic = 'sales-report.orders',
  List<String> dates = const [],
}) {
  return RealtimeEnvelope(
    version: 2,
    kind: 'SALES_REPORT_ORDERS_UPDATED',
    id: id,
    topic: topic,
    sequence: id.hashCode.abs(),
    timestamp: DateTime(2026, 7, 1, 9),
    data: {
      'dates': dates,
      'newOrderCount': 1,
      'mappedOrderCount': 0,
      'storeCodes': ['CP01'],
      'recipientUserIds': ['manager-1'],
    },
  );
}

Future<void> _pumpNotPurchasedForm(
  WidgetTester tester,
  _FakeSalesReportRepository repository,
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

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<SalesReportProvider>(
          create: (_) => SalesReportProvider(repository),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SalesReportFormScreen.notPurchased()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _checkboxTileByKey(String key) {
  return find.byWidgetPredicate(
    (widget) => widget is CheckboxListTile && widget.key == ValueKey(key),
  );
}

Finder _textFormFieldByParentKey(String key) {
  return find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(TextFormField),
  );
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class _FakeAuthProvider extends AuthProvider {
  final User currentUser;

  _FakeAuthProvider(this.currentUser) : super(AuthRepository(ApiClient()));

  @override
  User? get user => currentUser;
}

class _FakeStoreAuthRepository extends AuthRepository {
  final List<StoreBranch> stores;
  int getStoresCount = 0;

  _FakeStoreAuthRepository(this.stores) : super(ApiClient());

  @override
  Future<List<StoreBranch>> getStores({String? query}) async {
    getStoresCount += 1;
    return stores;
  }
}

class _FakeSalesReportRepository extends SalesReportRepository {
  final bool managedScope;
  final int unreportedTotal;
  final Map<String, dynamic> orderCheckOverrides;
  bool createCalled = false;
  int fetchListCount = 0;
  int fetchOrdersCount = 0;
  int checkOrderCount = 0;
  SalesReportInput? lastInput;
  SalesReportQuery? lastListQuery;
  SalesReportOrdersQuery? lastOrdersQuery;

  _FakeSalesReportRepository({
    this.managedScope = false,
    this.unreportedTotal = 21,
    this.orderCheckOverrides = const {},
  }) : super(ApiClient());

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
  Future<Map<String, dynamic>> create(
    SalesReportInput input, {
    String? followUpCaseId,
  }) async {
    createCalled = true;
    lastInput = input;
    return const {};
  }

  @override
  Future<Map<String, dynamic>> fetchList(SalesReportQuery query) async {
    fetchListCount += 1;
    lastListQuery = query;
    return {
      'items': const [],
      'page': query.page,
      'limit': query.limit,
      'total': 0,
    };
  }

  @override
  Future<SalesReportOrderCheck> checkOrder(
    String orderCode, {
    String? followUpCaseId,
  }) async {
    checkOrderCount += 1;
    return SalesReportOrderCheck.fromJson({
      'orderCode': orderCode,
      'isCancelled': false,
      'customerName': 'Trần Thị B',
      'customerNeed': 'Laptop trả góp',
      'customerType': 'PERSONAL',
      'categoryGroups': [
        {
          'id': 'NH08',
          'catGroupName': 'Network and Security equipment',
          'catGroupNameVi': 'Thiết bị mạng và an ninh',
        },
      ],
      'items': [
        {'sku': 'SKU-1', 'name': 'Laptop', 'quantity': 1},
      ],
      'payments': [
        {'method': 'cash'},
      ],
      'order': {
        'orderCode': orderCode,
        'grandTotal': 2500000,
        'paymentStatus': 'PAID',
        'terminalName': 'CP62',
      },
      ...orderCheckOverrides,
    });
  }

  @override
  Future<SalesReportOrderCockpit> fetchOrders(
    SalesReportOrdersQuery query,
  ) async {
    fetchOrdersCount += 1;
    lastOrdersQuery = query;
    return SalesReportOrderCockpit.fromJson({
      'date': '2026-07-01',
      'refreshedAt': '2026-07-01T09:03:00.000Z',
      'syncSucceeded': true,
      'syncCount': 2,
      'scope': managedScope ? 'MANAGED_SCOPE' : 'OWN',
      'selectedStoreCode': query.storeCode,
      'selectedUserEmail': query.userEmail,
      'storeOptions': managedScope
          ? [
              {'value': 'CP01', 'label': 'CP01 - Phong Vu CP01'},
            ]
          : const [],
      'userOptions': managedScope
          ? [
              {
                'value': 'sale.cp01@phongvu.vn',
                'label': 'Sale CP01 - sale.cp01@phongvu.vn',
              },
            ]
          : const [],
      'limit': query.limit,
      'reportedPage': query.reportedPage,
      'reportedTotal': 1,
      'unreportedPage': query.unreportedPage,
      'unreportedTotal': unreportedTotal,
      'reportedOrders': [
        {
          'status': 'REPORTED',
          'orderCode': '2607010001',
          'customerName': 'Nguyễn Văn A',
          'grandTotal': 1200000,
          'storeCode': 'CP62',
          'terminalName':
              'CP62 - ĐỊA ĐIỂM KINH DOANH 62 - CÔNG TY CỔ PHẦN THƯƠNG MẠI',
          'reportedAt': '2026-07-01T02:30:00.000Z',
        },
      ],
      'unreportedOrders': [
        {
          'status': 'UNREPORTED',
          'orderCode': '2607010002',
          'customerName': 'Trần Thị B',
          'grandTotal': 2500000,
          'storeCode': 'CP62',
          'terminalName':
              'CP62 - ĐỊA ĐIỂM KINH DOANH 62 - CÔNG TY CỔ PHẦN THƯƠNG MẠI',
          'consultantName': 'Tư vấn CP62',
          'sellerName': 'Sale CP62',
        },
      ],
    });
  }
}

class _FakeRealtimeClient implements RealtimeClient {
  final _events = StreamController<RealtimeEnvelope>.broadcast();
  final _syncRequests = StreamController<RealtimeSyncReason>.broadcast();

  @override
  Stream<RealtimeEnvelope> get events => _events.stream;

  @override
  Stream<RealtimeSyncReason> get syncRequests => _syncRequests.stream;

  void addEvent(RealtimeEnvelope event) => _events.add(event);

  void requestSync(RealtimeSyncReason reason) => _syncRequests.add(reason);

  @override
  Future<void> syncSession(String? sessionKey) async {}

  Future<void> dispose() async {
    await _events.close();
    await _syncRequests.close();
  }
}
