import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/realtime_connection_manager.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/warranty/data/repositories/warranty_repository.dart';
import 'package:phongvu_opshub/features/warranty/presentation/providers/warranty_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  test(
    'refreshes warranty only for typed v2 events and coalesces bursts',
    () async {
      final repository = _FakeWarrantyRepository();
      final realtime = _FakeRealtimeClient();
      final provider = WarrantyProvider(
        repository,
        realtimeClient: realtime,
        realtimeRefreshDebounce: const Duration(milliseconds: 10),
        realtimeRefreshMaxWait: const Duration(milliseconds: 40),
      );
      provider.syncRuntime(isRouteActive: true, isForeground: true);
      provider.syncAuth(_warrantyUser, isInitialized: true);

      await provider.showAllWarranty(_warrantyUser.email);
      expect(repository.fetchCount, 1);

      realtime.addEvent(
        _envelope(kind: 'WARRANTY_EVENT', topic: 'payment.transactions'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(repository.fetchCount, 1);

      repository.status = 'APPROVED';
      realtime.addEvent(_envelope(kind: 'WARRANTY_EVENT', topic: 'warranty'));
      await _waitUntil(() => repository.fetchCount == 2);
      expect(provider.receipts.single['status'], 'APPROVED');

      for (var index = 0; index < 8; index += 1) {
        realtime.addEvent(_envelope(kind: 'WARRANTY_EVENT', topic: 'warranty'));
      }
      await _waitUntil(() => repository.fetchCount == 3);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(repository.fetchCount, 3);

      realtime.addEvent(_envelope(kind: 'WARRANTY_EVENT', topic: 'warranty'));
      await Future<void>.delayed(Duration.zero);
      await provider.showAllWarranty(_warrantyUser.email);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(repository.fetchCount, 4);

      realtime.addSync(RealtimeSyncReason.reconnected);
      await _waitUntil(() => repository.fetchCount == 5);

      provider.dispose();
      await realtime.dispose();
    },
  );

  test(
    'same-user revoke clears data and rejects an in-flight response',
    () async {
      final repository = _FakeWarrantyRepository();
      final realtime = _FakeRealtimeClient();
      final provider = WarrantyProvider(repository, realtimeClient: realtime);
      addTearDown(provider.dispose);
      addTearDown(realtime.dispose);
      provider.syncRuntime(isRouteActive: true, isForeground: true);
      provider.syncAuth(_warrantyUser, isInitialized: true);
      await provider.showAllWarranty(_warrantyUser.email);
      expect(provider.receipts, isNotEmpty);

      repository.pendingFetch = Completer<List<Map<String, dynamic>>>();
      final staleRequest = provider.showAllWarranty(_warrantyUser.email);
      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(
        const User(
          id: 'warranty-1',
          email: 'warranty@example.com',
          role: 'USER',
          featureAccess: {'WARRANTY': false},
        ),
        isInitialized: true,
      );
      repository.pendingFetch!.complete([
        {'id': 'warranty-1', 'status': 'STALE'},
      ]);

      expect(await staleRequest, isFalse);
      expect(provider.receipts, isEmpty);
      realtime.addEvent(_envelope(kind: 'WARRANTY_EVENT', topic: 'warranty'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(repository.fetchCount, 2);
    },
  );
}

const _warrantyUser = User(
  id: 'warranty-1',
  email: 'warranty@example.com',
  role: 'USER',
  featureAccess: {'WARRANTY': true},
);

RealtimeEnvelope _envelope({required String kind, required String topic}) {
  return RealtimeEnvelope(
    version: 2,
    kind: kind,
    id: 'warranty-event-1',
    topic: topic,
    sequence: 1,
    timestamp: DateTime.utc(2026, 7, 15),
    data: const {'warrantyId': 'warranty-1', 'newStatus': 'APPROVED'},
  );
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var index = 0; index < 40; index += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition was not reached before timeout.');
}

class _FakeWarrantyRepository extends WarrantyRepository {
  int fetchCount = 0;
  String status = 'PENDING';
  Completer<List<Map<String, dynamic>>>? pendingFetch;

  _FakeWarrantyRepository() : super(ApiClient());

  @override
  Future<List<Map<String, dynamic>>> showAllWarranty(String userEmail) async {
    fetchCount += 1;
    final pending = pendingFetch;
    if (pending != null) return pending.future;
    return [
      {'id': 'warranty-1', 'status': status},
    ];
  }
}

class _FakeRealtimeClient implements RealtimeClient {
  final _events = StreamController<RealtimeEnvelope>.broadcast();
  final _syncRequests = StreamController<RealtimeSyncReason>.broadcast();

  @override
  Stream<RealtimeEnvelope> get events => _events.stream;

  @override
  Stream<RealtimeSyncReason> get syncRequests => _syncRequests.stream;

  void addEvent(RealtimeEnvelope envelope) => _events.add(envelope);

  void addSync(RealtimeSyncReason reason) => _syncRequests.add(reason);

  @override
  Future<void> syncSession(String? sessionKey) async {}

  Future<void> dispose() async {
    await _events.close();
    await _syncRequests.close();
  }
}
