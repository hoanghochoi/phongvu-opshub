import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/realtime_connection_manager.dart';
import 'package:phongvu_opshub/core/runtime/app_runtime_coordinator.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/authenticated_realtime_coordinator.dart';

void main() {
  testWidgets(
    'Authenticated realtime session follows app auth instead of the Home route',
    (tester) async {
      final realtime = _FakeRealtimeClient();
      final runtime = AppRuntimeCoordinator()..setActiveRoute('/home');
      final auth = _FakeAuthProvider();
      final coordinator = AuthenticatedRealtimeCoordinator(
        realtimeClient: realtime,
      );
      addTearDown(runtime.dispose);
      addTearDown(coordinator.dispose);
      addTearDown(realtime.dispose);

      coordinator.sync(auth, runtime);
      await tester.pump();
      expect(realtime.sessionKeys, isEmpty);

      auth
        ..currentUser = const User(
          id: 'user-1',
          email: 'staff@phongvu.vn',
          name: 'Nhân viên',
          role: 'USER',
        )
        ..initialized = true
        ..accessReady = true
        ..currentAccessIdentity = 'version:1';
      coordinator.sync(auth, runtime);
      await tester.pump();
      expect(realtime.sessionKeys, hasLength(1));
      expect(realtime.sessionKeys.single, contains('version:1'));

      coordinator.sync(auth, runtime);
      await tester.pump();
      expect(realtime.sessionKeys, hasLength(1));

      auth.currentAccessIdentity = 'version:2';
      coordinator.sync(auth, runtime);
      await tester.pump();
      expect(realtime.sessionKeys, hasLength(2));
      expect(realtime.sessionKeys.last, contains('version:2'));

      runtime.setActiveRoute('/login');
      coordinator.sync(auth, runtime);
      await tester.pump();
      expect(realtime.sessionKeys.last, isNull);
    },
  );
}

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider() : super(AuthRepository(ApiClient()));

  User? currentUser;
  bool initialized = false;
  bool accessReady = false;
  String? currentAccessIdentity;

  @override
  User? get user => currentUser;

  @override
  bool get isAuthenticated => currentUser != null;

  @override
  bool get isInitialized => initialized;

  @override
  bool get hasUsableAccessSnapshot => accessReady;

  @override
  String? get accessIdentity => currentAccessIdentity;
}

class _FakeRealtimeClient implements RealtimeClient {
  final eventsController = StreamController<RealtimeEnvelope>.broadcast();
  final syncController = StreamController<RealtimeSyncReason>.broadcast();
  final List<String?> sessionKeys = [];

  @override
  Stream<RealtimeEnvelope> get events => eventsController.stream;

  @override
  Stream<RealtimeSyncReason> get syncRequests => syncController.stream;

  @override
  Future<void> syncSession(String? sessionKey) async {
    sessionKeys.add(sessionKey);
  }

  Future<void> dispose() async {
    await eventsController.close();
    await syncController.close();
  }
}
