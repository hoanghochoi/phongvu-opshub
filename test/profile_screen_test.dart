import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/legacy_widget_finders.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/storage/app_storage_keys.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/auth/presentation/screens/profile_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets(
    'Profile shows tree assignment instead of legacy personnel fields',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        AppStorageKeys.shared('user_email'): 'hoang.nv1@phongvu-mna.vn',
        AppStorageKeys.shared('user_name'): 'Hoàng',
        AppStorageKeys.shared('user_lastName'): 'Nguyễn',
        AppStorageKeys.shared('user_role'): 'USER',
        AppStorageKeys.shared('user_departmentCode'): 'MANAGEMENT',
        AppStorageKeys.shared('user_jobRoleCode'): 'STORE_MANAGER',
        AppStorageKeys.shared('user_workScopeType'): 'STORE',
        AppStorageKeys.shared('user_personnelCode'):
            'STORE_MANAGER_CP62_HCM1_HCM_BD',
        AppStorageKeys.shared('user_organizationNodeId'):
            'org-store-cp62-pos-manager',
        AppStorageKeys.shared('user_organizationNodeName'): 'Quản lý Cửa hàng',
        AppStorageKeys.shared('user_storeId'): 'CP62',
        AppStorageKeys.shared('user_storeName'): 'Phan Đăng Lưu',
        AppStorageKeys.shared('user_assignedStores'): jsonEncode([
          {'id': 'store-62', 'storeId': 'CP62', 'storeName': 'Phan Đăng Lưu'},
          {'id': 'store-75', 'storeId': 'CP75', 'storeName': 'Phan Đăng Lưu 2'},
        ]),
      });
      _seedSecureToken();

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(AuthRepository(ApiClient())),
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsNothing);
      expect(findsLegacyGradientHeader(), findsNothing);
      expect(find.byKey(const Key('profile-header')), findsOneWidget);
      expect(find.byKey(const Key('profile-session-card')), findsOneWidget);
      expect(find.byKey(const Key('profile-logout-button')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('profile-session-card')),
          matching: find.byKey(const Key('profile-logout-button')),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('profile-edit-card')), findsOneWidget);
      expect(find.byKey(const Key('profile-info-card')), findsOneWidget);
      expect(find.text('Thông tin hiển thị'), findsOneWidget);
      expect(find.text('Thông tin tài khoản'), findsOneWidget);
      expect(find.text('Phiên đăng nhập'), findsOneWidget);
      expect(find.text('Đăng xuất'), findsOneWidget);
      expect(find.text('Quản lý Cửa hàng'), findsWidgets);
      expect(find.text('Cây tổ chức'), findsOneWidget);
      expect(find.textContaining('CP62 - Phan Đăng Lưu'), findsOneWidget);
      expect(find.textContaining('CP75 - Phan Đăng Lưu 2'), findsOneWidget);
      expect(find.text('Showroom được gán'), findsOneWidget);
      expect(find.textContaining('Phòng ban'), findsNothing);
      expect(find.textContaining('Chức danh'), findsNothing);
      expect(find.textContaining('Phạm vi'), findsNothing);
      expect(find.text('STORE_MANAGER_CP62_HCM1_HCM_BD'), findsNothing);
    },
  );

  testWidgets('Profile asks before logging out', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      AppStorageKeys.shared('user_email'): 'hoang.nv1@phongvu-mna.vn',
      AppStorageKeys.shared('user_name'): 'Hoàng',
      AppStorageKeys.shared('user_role'): 'USER',
      AppStorageKeys.shared('user_workScopeType'): 'STORE',
      AppStorageKeys.shared('user_organizationNodeId'):
          'org-store-cp62-pos-manager',
      AppStorageKeys.shared('user_organizationNodeName'): 'Quản lý Cửa hàng',
      AppStorageKeys.shared('user_storeId'): 'CP62',
      AppStorageKeys.shared('user_storeName'): 'Phan Đăng Lưu',
    });
    _seedSecureToken();

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(AuthRepository(ApiClient())),
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profile-logout-button')));
    await tester.pumpAndSettle();

    expect(find.text('Xác nhận đăng xuất'), findsOneWidget);
    expect(
      find.text(
        'Bạn có chắc chắn muốn đăng xuất khỏi OpsHub? Bạn sẽ cần đăng nhập lại để tiếp tục làm việc trên thiết bị này.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Ở lại'));
    await tester.pumpAndSettle();

    expect(find.text('Xác nhận đăng xuất'), findsNothing);
    expect(find.byKey(const Key('profile-session-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _seedSecureToken() {
  FlutterSecureStorage.setMockInitialValues({
    AppStorageKeys.secure('user_jwt_token'): 'widget-test-token',
  });
}
