import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phongvu_opshub/app/navigation/app_router.dart';
import 'package:phongvu_opshub/app/navigation/app_shell.dart';
import 'package:phongvu_opshub/app/theme/app_colors.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/bank_statement/data/bank_statement_repository.dart';
import 'package:phongvu_opshub/features/bank_statement/domain/bank_statement_transaction.dart';
import 'package:phongvu_opshub/features/notifications/presentation/providers/app_notifications_provider.dart';
import 'package:phongvu_opshub/features/offset_adjustment/data/offset_adjustment_repository.dart';
import 'package:phongvu_opshub/features/offset_adjustment/domain/offset_adjustment.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PhongVu OpsHub',
      packageName: 'com.example.phongvu_opshub',
      version: '2026.07.03.87',
      buildNumber: '200087',
      buildSignature: '',
    );
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets('AppShell replaces the route viewport when location changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = _FakeAuthProvider(_shellUser);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const MaterialApp(
          home: AppShell(
            location: '/home',
            child: _RouteMarker(label: 'home-route-marker'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('route-/home')), findsOneWidget);
    expect(find.text('home-route-marker'), findsOneWidget);
    expect(find.text('operations-route-marker'), findsNothing);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const MaterialApp(
          home: AppShell(
            location: '/operations',
            child: _RouteMarker(label: 'operations-route-marker'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('route-/home')), findsNothing);
    expect(find.byKey(const ValueKey('route-/operations')), findsOneWidget);
    expect(find.text('home-route-marker'), findsNothing);
    expect(find.text('operations-route-marker'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy tasks route redirects to home', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = _FakeAuthProvider(_shellUser);
    final router = AppRouter.createRouter(authProvider);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    router.go('/tasks');
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/home');
    expect(find.byKey(const ValueKey('route-/home')), findsOneWidget);
    expect(find.text('Trang chủ vận hành'), findsOneWidget);
    expect(find.text('Tác vụ của bạn'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('public /help stays reachable when the user is logged out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = _LoggedOutAuthProvider();
    final router = AppRouter.createRouter(
      authProvider,
      helpScreen: const _RouteMarker(label: 'help-route-marker'),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    router.go('/help');
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/help');
    expect(find.text('help-route-marker'), findsOneWidget);
    expect(find.text('Email check'), findsNothing);
  });

  testWidgets(
    'mobile shell routes to /operations and keeps notifications shell-owned',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final authProvider = _FakeAuthProvider(_shellUser);
      final notificationsProvider = _FakeAppNotificationsProvider();
      final router = AppRouter.createRouter(authProvider);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<AppNotificationsProvider>.value(
              value: notificationsProvider,
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trang chủ'), findsWidgets);
      expect(find.text('Vận hành'), findsOneWidget);
      expect(find.text('Thông báo'), findsOneWidget);
      expect(find.text('Tài khoản'), findsOneWidget);

      await tester.tap(find.text('Vận hành'));
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/operations');
      expect(find.byKey(const ValueKey('route-/operations')), findsOneWidget);
      expect(find.text('Công cụ theo quyền'), findsOneWidget);

      await tester.tap(find.text('Thông báo'));
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/operations');
      expect(notificationsProvider.loadCalls, 1);
      expect(notificationsProvider.markReadCalls, 1);
      expect(find.text('Chưa có thông báo.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('account logout waits for confirmation', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = _FakeAuthProvider(_shellUser);
    final router = AppRouter.createRouter(authProvider);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Tài khoản'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đăng xuất'));
    await tester.pumpAndSettle();

    expect(find.text('Xác nhận đăng xuất'), findsOneWidget);
    expect(authProvider.logoutCalls, 0);

    await tester.tap(find.text('Ở lại'));
    await tester.pumpAndSettle();

    expect(find.text('Xác nhận đăng xuất'), findsNothing);
    expect(authProvider.logoutCalls, 0);

    await tester.tap(find.byTooltip('Tài khoản'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đăng xuất'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đăng xuất'));
    await tester.pumpAndSettle();

    expect(authProvider.logoutCalls, 1);
    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(tester.takeException(), isNull);
  });

  testWidgets('account help entry opens the in-app help route', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = _FakeAuthProvider(_shellUser);
    final router = AppRouter.createRouter(
      authProvider,
      helpScreen: const _RouteMarker(label: 'help-route-marker'),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Tài khoản'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hướng dẫn sử dụng'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/help');
    expect(find.text('help-route-marker'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shell routes do not keep the previous page for a transition', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = _FakeAuthProvider(_shellUser);
    final router = AppRouter.createRouter(authProvider);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    expect(find.text('Trang chủ vận hành'), findsOneWidget);
    expect(find.byKey(const ValueKey('route-/home')), findsOneWidget);

    router.go('/warranty-main');
    await tester.pump();

    expect(find.byKey(const ValueKey('route-/home')), findsNothing);
    expect(find.text('Trang chủ vận hành'), findsNothing);
    expect(find.byKey(const ValueKey('route-/warranty-main')), findsOneWidget);
    expect(find.byKey(const Key('warranty-main-header')), findsNothing);
    expect(find.text('Tác vụ bảo hành'), findsOneWidget);
    expect(find.text('Lưu hình ảnh'), findsOneWidget);
    expect(find.text('Xem lại hình ảnh'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile notifications tab opens the notifications panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = _FakeAuthProvider(_shellUser);
    final notificationsProvider = _FakeAppNotificationsProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<AppNotificationsProvider>.value(
            value: notificationsProvider,
          ),
        ],
        child: const MaterialApp(
          home: AppShell(
            location: '/home',
            child: _RouteMarker(label: 'home-route-marker'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Thông báo'), findsOneWidget);

    await tester.tap(find.text('Thông báo'));
    await tester.pumpAndSettle();

    expect(notificationsProvider.loadCalls, 1);
    expect(notificationsProvider.markReadCalls, 1);
    expect(find.text('Chưa có thông báo.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop sidebar uses a left indicator for selected route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = _FakeAuthProvider(_shellUser);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const MaterialApp(
          home: AppShell(
            location: '/home',
            child: _RouteMarker(label: 'home-route-marker'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selectedIndicatorFinder = find.byKey(
      const ValueKey('sidebar-selected-indicator-home'),
    );
    final selectedItem = tester.widget<Material>(
      find.byKey(const ValueKey('sidebar-item-home')),
    );
    final selectedIndicator = _sidebarIndicator(tester, 'home');
    final unselectedIndicator = _sidebarIndicator(tester, 'fifo');
    final rootGroup = find.byKey(const ValueKey('sidebar-group-root'));
    final workspaceGroup = find.byKey(
      const ValueKey('sidebar-group-workspace'),
    );
    final accountGroup = find.byKey(const ValueKey('sidebar-group-account'));

    expect(find.text('Tổng quan'), findsOneWidget);
    expect(find.text('Nghiệp vụ'), findsOneWidget);
    expect(find.text('Cấu hình'), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar-item-operations')), findsNothing);
    expect(
      tester.getTopLeft(rootGroup).dy,
      lessThan(tester.getTopLeft(workspaceGroup).dy),
    );
    expect(
      tester.getTopLeft(workspaceGroup).dy,
      lessThan(tester.getTopLeft(accountGroup).dy),
    );
    expect(selectedItem.color, AppColors.transparent);
    expect(tester.getSize(selectedIndicatorFinder), const Size(4, 28));
    expect(_indicatorColor(selectedIndicator), isNot(AppColors.transparent));
    expect(_indicatorColor(unselectedIndicator), AppColors.transparent);
  });
}

class _RouteMarker extends StatelessWidget {
  final String label;

  const _RouteMarker({required this.label});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(child: Text(label)),
    );
  }
}

Container _sidebarIndicator(WidgetTester tester, String id) {
  return tester.widget<Container>(
    find.byKey(ValueKey('sidebar-selected-indicator-$id')),
  );
}

Color? _indicatorColor(Container indicator) {
  final decoration = indicator.decoration;
  return decoration is BoxDecoration ? decoration.color : null;
}

const _shellUser = User(
  id: 'shell-user-1',
  email: 'shell@example.com',
  role: 'USER',
  organizationNodeId: 'org-store-cp01',
  featureAccess: {
    'FIFO': true,
    'WARRANTY': true,
    'VIETQR': true,
    'BANK_STATEMENTS': true,
    'FEEDBACK': true,
  },
);

class _FakeAuthProvider extends AuthProvider {
  final User currentUser;
  int logoutCalls = 0;
  bool _loggedOut = false;

  _FakeAuthProvider(this.currentUser) : super(AuthRepository(ApiClient()));

  @override
  User? get user => _loggedOut ? null : currentUser;

  @override
  bool get isInitialized => true;

  @override
  bool get isAuthenticated => !_loggedOut;

  @override
  Future<void> logout() async {
    logoutCalls += 1;
    _loggedOut = true;
    notifyListeners();
  }
}

class _LoggedOutAuthProvider extends AuthProvider {
  _LoggedOutAuthProvider() : super(AuthRepository(ApiClient()));

  @override
  User? get user => null;

  @override
  bool get isInitialized => true;

  @override
  bool get isAuthenticated => false;
}

class _FakeAppNotificationsProvider extends AppNotificationsProvider {
  int loadCalls = 0;
  int markReadCalls = 0;

  _FakeAppNotificationsProvider()
    : super(
        BankStatementRepository(ApiClient()),
        offsetAdjustmentRepository: OffsetAdjustmentRepository(ApiClient()),
      );

  @override
  bool get isEnabled => true;

  @override
  bool get isLoading => false;

  @override
  int get count => 0;

  @override
  int get totalCount => 0;

  @override
  bool get canReviewStatementOrderTransfers => false;

  @override
  List<BankStatementOrderTransferRequest> get statementOrderRequests =>
      const [];

  @override
  List<OffsetAdjustment> get offsetAdjustmentRequests => const [];

  @override
  Future<void> load({bool silent = false}) async {
    loadCalls += 1;
  }

  @override
  Future<void> markVisibleNotificationsRead() async {
    markReadCalls += 1;
  }
}
