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
    expect(find.text('warranty-route-marker'), findsNothing);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const MaterialApp(
          home: AppShell(
            location: '/warranty-main',
            child: _RouteMarker(label: 'warranty-route-marker'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('route-/home')), findsNothing);
    expect(find.byKey(const ValueKey('route-/warranty-main')), findsOneWidget);
    expect(find.text('home-route-marker'), findsNothing);
    expect(find.text('warranty-route-marker'), findsOneWidget);
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
    expect(find.text('Tác vụ BH / SC'), findsOneWidget);
    expect(find.text('Lưu hình ảnh'), findsOneWidget);
    expect(find.text('Xem lại hình ảnh'), findsOneWidget);
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

  _FakeAuthProvider(this.currentUser) : super(AuthRepository(ApiClient()));

  @override
  User? get user => currentUser;

  @override
  bool get isInitialized => true;

  @override
  bool get isAuthenticated => true;
}
