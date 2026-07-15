import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/realtime_connection_manager.dart';
import 'package:phongvu_opshub/core/runtime/app_runtime_coordinator.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_access_refresh_coordinator.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() => AppLogger.instance.setUploadsEnabledForTesting(true));

  test(
    'refreshes expired access only on an authenticated foreground route',
    () async {
      final now = DateTime(2026, 7, 15, 10);
      final auth = _FakeLifecycleAuthProvider(
        lastSyncedAt: now.subtract(const Duration(minutes: 16)),
        retryResult: true,
      );
      final runtime = AppRuntimeCoordinator()..setActiveRoute('/home');
      final coordinator = AuthAccessRefreshCoordinator(now: () => now);
      addTearDown(runtime.dispose);
      addTearDown(coordinator.dispose);

      coordinator.sync(auth, runtime);
      await _flushAsyncWork();

      expect(auth.retryCalls, 1);
    },
  );

  test(
    'does not refresh a fresh snapshot or retry-loop after failure',
    () async {
      final now = DateTime(2026, 7, 15, 10);
      final runtime = AppRuntimeCoordinator()..setActiveRoute('/home');
      final fresh = _FakeLifecycleAuthProvider(
        lastSyncedAt: now.subtract(const Duration(minutes: 2)),
        retryResult: true,
      );
      final freshCoordinator = AuthAccessRefreshCoordinator(now: () => now);
      addTearDown(runtime.dispose);
      addTearDown(freshCoordinator.dispose);

      freshCoordinator.sync(fresh, runtime);
      await _flushAsyncWork();
      expect(fresh.retryCalls, 0);

      final stale = _FakeLifecycleAuthProvider(
        lastSyncedAt: now.subtract(const Duration(minutes: 20)),
        retryResult: false,
      );
      final staleCoordinator = AuthAccessRefreshCoordinator(now: () => now);
      addTearDown(staleCoordinator.dispose);
      staleCoordinator.sync(stale, runtime);
      await _flushAsyncWork();
      staleCoordinator.sync(stale, runtime);
      await _flushAsyncWork();

      expect(stale.retryCalls, 1);
    },
  );

  test('refreshes only for the strict access.changed v2 envelope', () async {
    final now = DateTime(2026, 7, 15, 10);
    final auth = _FakeLifecycleAuthProvider(
      lastSyncedAt: now.subtract(const Duration(minutes: 2)),
      retryResult: true,
    );
    final runtime = AppRuntimeCoordinator()..setActiveRoute('/home');
    final realtime = _FakeRealtimeClient();
    final coordinator = AuthAccessRefreshCoordinator(
      now: () => now,
      realtimeClient: realtime,
    );
    addTearDown(runtime.dispose);
    addTearDown(coordinator.dispose);
    addTearDown(realtime.dispose);
    coordinator.sync(auth, runtime);

    realtime.addEvent(_accessEnvelope(kind: 'OTHER', topic: 'access.changed'));
    realtime.addEvent(
      _accessEnvelope(kind: 'ACCESS_CHANGED', topic: 'home.summary'),
    );
    realtime.addEvent(_accessEnvelope(kind: 'OTHER', topic: 'auth.access'));
    await _flushAsyncWork();
    expect(auth.retryCalls, 0);

    realtime.addEvent(
      _accessEnvelope(kind: 'ACCESS_CHANGED', topic: 'access.changed'),
    );
    await _flushAsyncWork();
    expect(auth.retryCalls, 1);
  });
}

RealtimeEnvelope _accessEnvelope({
  required String kind,
  required String topic,
}) {
  return RealtimeEnvelope(
    version: 2,
    kind: kind,
    id: '$kind-$topic',
    topic: topic,
    sequence: 1,
    timestamp: DateTime.utc(2026, 7, 15),
    data: const {},
  );
}

Future<void> _flushAsyncWork() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeLifecycleAuthProvider extends AuthProvider {
  _FakeLifecycleAuthProvider({
    required this.lastSyncedAt,
    required this.retryResult,
  }) : super(AuthRepository(ApiClient()));

  static const _user = User(id: 'user-1', email: 'staff@phongvu.vn');

  final DateTime? lastSyncedAt;
  final bool retryResult;
  int retryCalls = 0;

  @override
  User? get user => _user;

  @override
  bool get isInitialized => true;

  @override
  bool get isAuthenticated => true;

  @override
  bool get isAccessSyncing => false;

  @override
  DateTime? get accessLastSyncedAt => lastSyncedAt;

  @override
  Future<bool> retryAccessSync() async {
    retryCalls += 1;
    return retryResult;
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

  @override
  Future<void> syncSession(String? sessionKey) async {}

  Future<void> dispose() async {
    await _events.close();
    await _syncRequests.close();
  }
}
