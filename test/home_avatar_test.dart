import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
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

  testWidgets('App info dialog shows developer credit', (
    WidgetTester tester,
  ) async {
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
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thông tin ứng dụng'));
    await tester.pumpAndSettle();

    expect(find.text('Dev by Hoang Nguyen aka Hoàng Học Hỏi'), findsOneWidget);
  });
}
