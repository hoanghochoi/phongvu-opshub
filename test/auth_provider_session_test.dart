import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/storage/app_storage_keys.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/store_branch.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
    ApiClient().setAuthToken(null);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  test(
    'refreshes assigned store scope when restoring a saved session',
    () async {
      SharedPreferences.setMockInitialValues({
        AppStorageKeys.shared('user_email'): 'staging.user0012@phongvu.vn',
        AppStorageKeys.shared('user_name'): 'Staging',
        AppStorageKeys.shared('user_role'): 'USER',
        AppStorageKeys.shared('user_storeId'): 'CP75',
        AppStorageKeys.shared('user_storeName'): 'CP75',
        AppStorageKeys.shared('user_workScopeType'): 'STORE',
        AppStorageKeys.shared('user_organizationNodeId'): 'node-cp75',
        AppStorageKeys.shared('user_organizationNodeName'): 'Quản lý CP75',
      });
      FlutterSecureStorage.setMockInitialValues({
        AppStorageKeys.secure('user_jwt_token'): 'jwt-token',
      });
      final repository = _RefreshingAuthRepository(
        const User(
          id: 'user-12',
          email: 'staging.user0012@phongvu.vn',
          name: 'Staging',
          role: 'USER',
          storeId: 'CP75',
          storeName: 'CP75',
          workScopeType: 'STORE',
          organizationNodeId: 'node-cp75',
          organizationNodeIds: ['node-cp75', 'node-cp62'],
          organizationAssignments: [
            UserOrganizationAssignment(
              id: 'assignment-75',
              organizationNodeId: 'node-cp75',
              organizationNodeName: 'Quản lý CP75',
              storeId: 'CP75',
              storeName: 'CP75',
              isPrimary: true,
            ),
            UserOrganizationAssignment(
              id: 'assignment-62',
              organizationNodeId: 'node-cp62',
              organizationNodeName: 'Quản lý CP62',
              storeId: 'CP62',
              storeName: 'CP62',
            ),
          ],
          assignedStores: [
            StoreBranch(id: 'store-75', storeId: 'CP75', storeName: 'CP75'),
            StoreBranch(id: 'store-62', storeId: 'CP62', storeName: 'CP62'),
          ],
        ),
      );

      final provider = AuthProvider(repository);
      await _waitForInitialization(provider);

      expect(repository.getUserDataCount, 1);
      expect(provider.user?.assignedStoreIds, ['CP75', 'CP62']);
      expect(provider.user?.canUseFeature('PAYMENT_MONITOR'), isTrue);

      final prefs = await SharedPreferences.getInstance();
      final savedStores =
          jsonDecode(
                prefs.getString(AppStorageKeys.shared('user_assignedStores'))!,
              )
              as List<dynamic>;
      expect(
        savedStores.map((item) => (item as Map<String, dynamic>)['storeId']),
        ['CP75', 'CP62'],
      );

      provider.dispose();
    },
  );
}

Future<void> _waitForInitialization(AuthProvider provider) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (provider.isInitialized) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('AuthProvider did not initialize');
}

class _RefreshingAuthRepository extends AuthRepository {
  final User refreshedUser;
  int getUserDataCount = 0;

  _RefreshingAuthRepository(this.refreshedUser) : super(ApiClient());

  @override
  Future<User> getUserData(String email) async {
    getUserDataCount += 1;
    return refreshedUser;
  }

  @override
  Future<Map<String, bool>> getMyFeatureAccess() async {
    return const {'PAYMENT_MONITOR': true, 'BANK_STATEMENTS': true};
  }

  @override
  Future<Map<String, bool>> getMyPolicyAccess() async {
    return const {'BANK_STATEMENT_ALL_SCOPE': false};
  }
}
