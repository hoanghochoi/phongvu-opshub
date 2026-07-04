import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phongvu_opshub/app/navigation/app_shell.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/storage/app_storage_keys.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/home/presentation/screens/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Home header renders avatar from saved user session', (
    WidgetTester tester,
  ) async {
    const avatarUrl = 'https://cdn.example.test/avatar.png';

    SharedPreferences.setMockInitialValues({
      AppStorageKeys.shared('user_email'): 'dai.ca@example.com',
      AppStorageKeys.shared('user_name'): 'Dai Ca',
      AppStorageKeys.shared('user_avatarUrl'): avatarUrl,
      AppStorageKeys.shared('user_storeId'): 'PV001',
      AppStorageKeys.shared('user_storeName'): 'PV Test',
      AppStorageKeys.shared('user_workScopeType'): 'STORE',
    });
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PhongVu OpsHub',
      packageName: 'com.example.phongvu_opshub',
      version: '1.1.1',
      buildNumber: '2',
      buildSignature: '',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(AuthRepository(ApiClient())),
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey(avatarUrl)), findsOneWidget);
  });

  testWidgets('App info dialog shows OpsHub summary from account menu', (
    WidgetTester tester,
  ) async {
    _useDesktopSurface(tester);
    SharedPreferences.setMockInitialValues({
      AppStorageKeys.shared('user_email'): 'dai.ca@example.com',
      AppStorageKeys.shared('user_name'): 'Dai Ca',
      AppStorageKeys.shared('user_storeId'): 'PV001',
      AppStorageKeys.shared('user_storeName'): 'PV Test',
      AppStorageKeys.shared('user_workScopeType'): 'STORE',
    });
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PhongVu OpsHub',
      packageName: 'com.example.phongvu_opshub',
      version: '1.1.1',
      buildNumber: '2',
      buildSignature: '',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(AuthRepository(ApiClient())),
        child: const MaterialApp(
          home: AppShell(location: '/home', child: HomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Tài khoản'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thông tin ứng dụng'));
    await tester.pumpAndSettle();

    expect(find.text('Thông tin ứng dụng'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Kết nối nguồn lực. Đồng bộ vận hành.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('AppShell keeps logout in the account menu', (
    WidgetTester tester,
  ) async {
    _useDesktopSurface(tester);
    SharedPreferences.setMockInitialValues({
      AppStorageKeys.shared('user_email'): 'dai.ca@example.com',
      AppStorageKeys.shared('user_name'): 'Dai Ca',
      AppStorageKeys.shared('user_storeId'): 'PV001',
      AppStorageKeys.shared('user_storeName'): 'PV Test',
      AppStorageKeys.shared('user_workScopeType'): 'STORE',
    });
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PhongVu OpsHub',
      packageName: 'com.example.phongvu_opshub',
      version: '1.1.1',
      buildNumber: '2',
      buildSignature: '',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(AuthRepository(ApiClient())),
        child: const MaterialApp(
          home: AppShell(location: '/home', child: HomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Đăng xuất'), findsNothing);

    await tester.tap(find.byTooltip('Tài khoản'));
    await tester.pumpAndSettle();

    expect(find.text('Đăng xuất'), findsOneWidget);
  });

  testWidgets('AppShell account menu no longer duplicates the help page link', (
    WidgetTester tester,
  ) async {
    _useDesktopSurface(tester);
    SharedPreferences.setMockInitialValues({
      AppStorageKeys.shared('user_email'): 'dai.ca@example.com',
      AppStorageKeys.shared('user_name'): 'Dai Ca',
      AppStorageKeys.shared('user_storeId'): 'PV001',
      AppStorageKeys.shared('user_storeName'): 'PV Test',
      AppStorageKeys.shared('user_workScopeType'): 'STORE',
    });
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PhongVu OpsHub',
      packageName: 'com.example.phongvu_opshub',
      version: '1.1.1',
      buildNumber: '2',
      buildSignature: '',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(AuthRepository(ApiClient())),
        child: const MaterialApp(
          home: AppShell(location: '/home', child: HomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Tài khoản'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'Hướng dẫn'), findsNothing);
  });
}

void _useDesktopSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1366, 768);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
