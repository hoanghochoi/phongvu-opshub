import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/api_exception.dart';
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
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  test('hydrates cached access before bootstrap refresh completes', () async {
    final bootstrap = Completer<AuthBootstrapResult>();
    _seedSavedSnapshot(
      featureAccess: const {'PAYMENT_MONITOR': true},
      policyAccess: const {'BANK_STATEMENT_ALL_SCOPE': false},
      etag: '"access-v1"',
    );
    final repository = _FakeAuthRepository(bootstrapFuture: bootstrap.future);

    final provider = AuthProvider(repository);
    await _waitForInitialization(provider);

    expect(provider.user?.canUseFeature('PAYMENT_MONITOR'), isTrue);
    expect(provider.user?.policyAccess, {'BANK_STATEMENT_ALL_SCOPE': false});
    expect(provider.accessSyncState, AuthAccessSyncState.syncing);
    expect(repository.bootstrapIfNoneMatch, '"access-v1"');

    bootstrap.completeError(ApiException('Hệ thống đang bận.', 503));
    await _waitForSync(provider, repository);

    expect(provider.user?.canUseFeature('PAYMENT_MONITOR'), isTrue);
    expect(provider.accessSyncState, AuthAccessSyncState.stale);
    expect(
      provider.accessSyncWarning,
      'Đang dùng quyền đã lưu. Chưa đồng bộ được thay đổi mới.',
    );
    expect(repository.getUserDataCount, 0);
    expect(repository.featureAccessCount, 0);
    expect(repository.policyAccessCount, 0);
    provider.dispose();
  });

  test(
    'bootstrap 200 replaces and persists the full access snapshot',
    () async {
      _seedSavedSnapshot(
        featureAccess: const {'PAYMENT_MONITOR': true},
        policyAccess: const {},
        etag: '"access-v1"',
      );
      final repository = _FakeAuthRepository(
        bootstrapResult: AuthBootstrapResult.data(
          data: AuthBootstrapData(
            schemaVersion: 1,
            generatedAt: DateTime.utc(2026, 7, 15, 8),
            version: 'access-v2',
            user: _refreshedUser,
            featureAccess: const {
              'PAYMENT_MONITOR': false,
              'BANK_STATEMENTS': true,
            },
            policyAccess: const {'BANK_STATEMENT_ALL_SCOPE': true},
            capabilities: const AuthBootstrapCapabilities(
              conditionalGet: true,
              realtimeV2Topics: ['access.changed', 'home.summary'],
            ),
          ),
          etag: '"access-v2"',
        ),
      );

      final provider = AuthProvider(repository);
      await _waitForSync(provider, repository);

      expect(provider.accessSyncState, AuthAccessSyncState.fresh);
      expect(provider.user?.canUseFeature('PAYMENT_MONITOR'), isFalse);
      expect(provider.user?.canUseFeature('BANK_STATEMENTS'), isTrue);
      expect(provider.user?.canUsePolicy('BANK_STATEMENT_ALL_SCOPE'), isTrue);
      expect(provider.bootstrapVersion, 'access-v2');
      expect(provider.bootstrapConditionalGet, isTrue);
      expect(provider.realtimeV2Topics, ['access.changed', 'home.summary']);

      final prefs = await SharedPreferences.getInstance();
      final saved =
          jsonDecode(
                prefs.getString(
                  AppStorageKeys.shared('auth_session_snapshot_v2'),
                )!,
              )
              as Map<String, dynamic>;
      final savedUser = saved['user'] as Map<String, dynamic>;
      final savedBootstrap = saved['bootstrap'] as Map<String, dynamic>;
      expect(savedUser['featureAccess'], {
        'PAYMENT_MONITOR': false,
        'BANK_STATEMENTS': true,
      });
      expect(savedUser['policyAccess'], {'BANK_STATEMENT_ALL_SCOPE': true});
      expect(savedBootstrap['etag'], '"access-v2"');
      expect(savedBootstrap['lastSuccessAt'], isNotNull);
      provider.dispose();
    },
  );

  test('bootstrap 304 retains cached access and marks sync fresh', () async {
    _seedSavedSnapshot(
      featureAccess: const {'PAYMENT_MONITOR': true},
      policyAccess: const {'BANK_STATEMENT_ALL_SCOPE': true},
      etag: '"access-v1"',
    );
    final repository = _FakeAuthRepository(
      bootstrapResult: const AuthBootstrapResult.notModified(
        etag: '"access-v1"',
      ),
    );

    final provider = AuthProvider(repository);
    await _waitForSync(provider, repository);

    expect(repository.bootstrapCount, 1);
    expect(provider.user?.canUseFeature('PAYMENT_MONITOR'), isTrue);
    expect(provider.user?.canUsePolicy('BANK_STATEMENT_ALL_SCOPE'), isTrue);
    expect(provider.accessSyncState, AuthAccessSyncState.fresh);
    expect(provider.accessLastSyncedAt, isNotNull);
    expect(repository.getUserDataCount, 0);
    provider.dispose();
  });

  test(
    'manual retry replaces stale access after connectivity recovers',
    () async {
      _seedSavedSnapshot(
        featureAccess: const {'PAYMENT_MONITOR': true},
        policyAccess: const {},
        etag: '"access-v1"',
      );
      final repository = _FakeAuthRepository(
        bootstrapError: ApiException('Hệ thống đang bận.', 503),
      );
      final provider = AuthProvider(repository);
      await _waitForSync(provider, repository);
      expect(provider.accessSyncState, AuthAccessSyncState.stale);

      repository
        ..bootstrapError = null
        ..bootstrapResult = AuthBootstrapResult.data(
          data: AuthBootstrapData(
            schemaVersion: 1,
            generatedAt: DateTime.utc(2026, 7, 15, 8),
            version: 'access-v2',
            user: _refreshedUser,
            featureAccess: const {'PAYMENT_MONITOR': false},
            policyAccess: const {},
            capabilities: const AuthBootstrapCapabilities(
              conditionalGet: true,
              realtimeV2Topics: ['access.changed'],
            ),
          ),
          etag: '"access-v2"',
        );

      expect(await provider.retryAccessSync(), isTrue);
      expect(repository.bootstrapCount, 2);
      expect(provider.accessSyncState, AuthAccessSyncState.fresh);
      expect(provider.user?.canUseFeature('PAYMENT_MONITOR'), isFalse);
      expect(provider.accessSyncWarning, isNull);
      provider.dispose();
    },
  );

  test('bootstrap 401 clears cached user, access and token', () async {
    _seedSavedSnapshot(
      featureAccess: const {'PAYMENT_MONITOR': true},
      policyAccess: const {},
      etag: '"access-v1"',
    );
    final repository = _FakeAuthRepository(
      bootstrapError: ApiException('Unauthorized', 401),
    );

    final provider = AuthProvider(repository);
    await _waitForSync(provider, repository);

    expect(provider.user, isNull);
    expect(provider.isAuthenticated, isFalse);
    expect(provider.sessionExpiredDialogMessage, isNotNull);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(AppStorageKeys.shared('auth_session_snapshot_v2')),
      isNull,
    );
    expect(
      await const FlutterSecureStorage().read(
        key: AppStorageKeys.secure('user_jwt_token'),
      ),
      isNull,
    );
    provider.dispose();
  });

  test('logout clears the persisted access snapshot and token', () async {
    _seedSavedSnapshot(
      featureAccess: const {'PAYMENT_MONITOR': true},
      policyAccess: const {},
      etag: '"access-v1"',
    );
    final repository = _FakeAuthRepository(
      bootstrapResult: const AuthBootstrapResult.notModified(
        etag: '"access-v1"',
      ),
    );
    final provider = AuthProvider(repository);
    await _waitForSync(provider, repository);

    await provider.logout();

    expect(repository.logoutCount, 1);
    expect(provider.user, isNull);
    expect(provider.accessLastSyncedAt, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(AppStorageKeys.shared('auth_session_snapshot_v2')),
      isNull,
    );
    expect(
      await const FlutterSecureStorage().read(
        key: AppStorageKeys.secure('user_jwt_token'),
      ),
      isNull,
    );
    provider.dispose();
  });

  test('saved user without a secure token is discarded as orphaned', () async {
    _seedSavedSnapshot(
      featureAccess: const {'PAYMENT_MONITOR': true},
      policyAccess: const {},
      etag: '"access-v1"',
    );
    FlutterSecureStorage.setMockInitialValues({});
    final provider = AuthProvider(
      _FakeAuthRepository(
        bootstrapResult: const AuthBootstrapResult.notModified(),
      ),
    );
    await _waitForInitialization(provider);

    expect(provider.user, isNull);
    expect(provider.isAuthenticated, isFalse);
    expect(ApiClient().authToken, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(AppStorageKeys.shared('auth_session_snapshot_v2')),
      isNull,
    );
    provider.dispose();
  });

  test('logout wins over a bootstrap response that completes later', () async {
    final bootstrap = Completer<AuthBootstrapResult>();
    _seedSavedSnapshot(
      featureAccess: const {'PAYMENT_MONITOR': true},
      policyAccess: const {},
      etag: '"access-v1"',
    );
    final repository = _FakeAuthRepository(bootstrapFuture: bootstrap.future);
    final provider = AuthProvider(repository);
    await _waitForInitialization(provider);
    expect(provider.isAccessSyncing, isTrue);

    await provider.logout();
    bootstrap.complete(
      AuthBootstrapResult.data(
        data: AuthBootstrapData(
          schemaVersion: 1,
          generatedAt: DateTime.utc(2026, 7, 15, 8),
          version: 'late-access',
          user: _refreshedUser,
          featureAccess: const {'PAYMENT_MONITOR': true},
          policyAccess: const {},
          capabilities: const AuthBootstrapCapabilities(
            conditionalGet: true,
            realtimeV2Topics: ['access.changed'],
          ),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(provider.user, isNull);
    expect(ApiClient().authToken, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(AppStorageKeys.shared('auth_session_snapshot_v2')),
      isNull,
    );
    provider.dispose();
  });

  test(
    'legacy three-call refresh is used only for bootstrap 404/501',
    () async {
      for (final statusCode in [404, 501]) {
        _seedSavedSnapshot(
          featureAccess: const {'PAYMENT_MONITOR': false},
          policyAccess: const {},
          etag: '"access-v1"',
        );
        final repository = _FakeAuthRepository(
          bootstrapError: ApiException('Unavailable', statusCode),
        );

        final provider = AuthProvider(repository);
        await _waitForSync(provider, repository);

        expect(repository.bootstrapCount, 1, reason: 'HTTP $statusCode');
        expect(repository.getUserDataCount, 1, reason: 'HTTP $statusCode');
        expect(repository.featureAccessCount, 1, reason: 'HTTP $statusCode');
        expect(repository.policyAccessCount, 1, reason: 'HTTP $statusCode');
        expect(provider.user?.canUseFeature('PAYMENT_MONITOR'), isTrue);
        expect(provider.accessSyncState, AuthAccessSyncState.fresh);
        provider.dispose();
        ApiClient().setAuthToken(null);
      }
    },
  );

  test('refreshes assigned store scope through legacy compatibility', () async {
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
    final repository = _FakeAuthRepository(
      bootstrapError: ApiException('Unavailable', 404),
    );

    final provider = AuthProvider(repository);
    await _waitForSync(provider, repository);

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
  });
}

void _seedSavedSnapshot({
  required Map<String, bool> featureAccess,
  required Map<String, bool> policyAccess,
  String? etag,
}) {
  final user = {
    'id': 'cached-user',
    'email': 'staging.user0012@phongvu.vn',
    'name': 'Cached',
    'role': 'USER',
    'storeId': 'CP75',
    'storeName': 'CP75',
    'workScopeType': 'STORE',
    'organizationNodeId': 'node-cp75',
    'organizationNodeIds': ['node-cp75'],
    'featureAccess': featureAccess,
    'policyAccess': policyAccess,
  };
  SharedPreferences.setMockInitialValues({
    AppStorageKeys.shared('user_email'): user['email']!,
    AppStorageKeys.shared('auth_session_snapshot_v2'): jsonEncode({
      'schemaVersion': 2,
      'user': user,
      'bootstrap': {
        'etag': etag,
        'generatedAt': '2026-07-15T07:55:00.000Z',
        'lastSuccessAt': '2026-07-15T07:55:00.000Z',
        'version': 'access-v1',
        'schemaVersion': 1,
        'conditionalGet': true,
        'realtimeV2Topics': ['access.changed'],
      },
    }),
  });
  FlutterSecureStorage.setMockInitialValues({
    AppStorageKeys.secure('user_jwt_token'): 'jwt-token',
  });
}

Future<void> _waitForInitialization(AuthProvider provider) async {
  for (var attempt = 0; attempt < 200; attempt += 1) {
    if (provider.isInitialized) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('AuthProvider did not initialize');
}

Future<void> _waitForSync(
  AuthProvider provider,
  _FakeAuthRepository repository,
) async {
  for (var attempt = 0; attempt < 400; attempt += 1) {
    if (repository.bootstrapCount > 0 && !provider.isAccessSyncing) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('AuthProvider did not finish access sync');
}

const _refreshedUser = User(
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
);

class _FakeAuthRepository extends AuthRepository {
  AuthBootstrapResult? bootstrapResult;
  Object? bootstrapError;
  final Future<AuthBootstrapResult>? bootstrapFuture;
  int bootstrapCount = 0;
  int getUserDataCount = 0;
  int featureAccessCount = 0;
  int policyAccessCount = 0;
  int logoutCount = 0;
  String? bootstrapIfNoneMatch;

  _FakeAuthRepository({
    this.bootstrapResult,
    this.bootstrapError,
    this.bootstrapFuture,
  }) : super(ApiClient());

  @override
  Future<AuthBootstrapResult> getBootstrap({String? ifNoneMatch}) async {
    bootstrapCount += 1;
    bootstrapIfNoneMatch = ifNoneMatch;
    if (bootstrapFuture != null) return bootstrapFuture!;
    if (bootstrapError != null) throw bootstrapError!;
    return bootstrapResult!;
  }

  @override
  Future<User> getUserData(String email) async {
    getUserDataCount += 1;
    return _refreshedUser;
  }

  @override
  Future<Map<String, bool>> getMyFeatureAccess() async {
    featureAccessCount += 1;
    return const {'PAYMENT_MONITOR': true, 'BANK_STATEMENTS': true};
  }

  @override
  Future<Map<String, bool>> getMyPolicyAccess() async {
    policyAccessCount += 1;
    return const {'BANK_STATEMENT_ALL_SCOPE': false};
  }

  @override
  Future<void> logout() async {
    logoutCount += 1;
  }
}
