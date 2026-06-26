import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/storage/app_storage_keys.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/auth/presentation/screens/profile_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      FlutterSecureStorage.setMockInitialValues({});

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(AuthRepository(ApiClient())),
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Quản lý Cửa hàng'), findsOneWidget);
      expect(find.text('Cây tổ chức'), findsOneWidget);
      expect(find.textContaining('CP62 - Phan Đăng Lưu'), findsOneWidget);
      expect(find.textContaining('CP75 - Phan Đăng Lưu 2'), findsOneWidget);
      expect(find.text('SR được gán'), findsOneWidget);
      expect(find.textContaining('Phòng ban'), findsNothing);
      expect(find.textContaining('Chức danh'), findsNothing);
      expect(find.textContaining('Phạm vi'), findsNothing);
      expect(find.text('STORE_MANAGER_CP62_HCM1_HCM_BD'), findsNothing);
    },
  );
}
