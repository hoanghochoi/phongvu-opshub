import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/realtime_connection_manager.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/quick_actions/data/quick_actions_local_cache.dart';
import 'package:phongvu_opshub/features/quick_actions/data/quick_actions_repository.dart';
import 'package:phongvu_opshub/features/quick_actions/presentation/quick_actions_provider.dart';

void main() {
  const user = User(
    id: 'user-1',
    email: 'staff@phongvu.vn',
    featureAccess: {'QUICK_ACTIONS': true},
  );

  test('reuses persistent scope cache after app restart', () async {
    final repository = _FakeQuickActionsRepository(singleStore: false);
    final localCache = _FakeQuickActionsCacheStore();
    final firstSession = QuickActionsProvider(
      repository,
      localCache: localCache,
    );
    await firstSession.syncUser(user);
    expect(repository.loadCount, 1);

    final secondSession = QuickActionsProvider(
      repository,
      localCache: localCache,
    );
    await secondSession.syncUser(user);
    await secondSession.refresh();

    expect(repository.loadCount, 1);
    expect(secondSession.payload?.availableActionCodes, {'APP_DOWNLOAD'});
  });

  test(
    'single-store bootstrap persists QR without a second API call',
    () async {
      final repository = _FakeQuickActionsRepository(singleStore: true);
      final localCache = _FakeQuickActionsCacheStore();
      final firstSession = QuickActionsProvider(
        repository,
        localCache: localCache,
      );
      await firstSession.syncUser(user);

      final secondSession = QuickActionsProvider(
        repository,
        localCache: localCache,
      );
      await secondSession.syncUser(user);
      final selected = await secondSession.refresh(storeCode: 'cp75');

      expect(repository.loadCount, 1);
      expect(selected?.links['APP_DOWNLOAD'], 'https://example.com/app');
    },
  );

  test('showroom QR remains local for seven days then reloads once', () async {
    var now = DateTime(2026, 7, 15, 10);
    final repository = _FakeQuickActionsRepository(singleStore: false);
    final localCache = _FakeQuickActionsCacheStore();
    final provider = QuickActionsProvider(
      repository,
      localCache: localCache,
      now: () => now,
    );

    await provider.syncUser(user);
    await provider.refresh(storeCode: 'CP75');
    await provider.refresh(storeCode: 'cp75');
    expect(repository.loadCount, 2);

    now = now.add(const Duration(days: 7));
    await provider.refresh(storeCode: 'CP75');
    expect(repository.loadCount, 3);
  });

  test(
    'expired showroom QR falls back to disk when API is unavailable',
    () async {
      var now = DateTime(2026, 7, 15, 10);
      final repository = _FakeQuickActionsRepository(singleStore: true);
      final localCache = _FakeQuickActionsCacheStore();
      final provider = QuickActionsProvider(
        repository,
        localCache: localCache,
        now: () => now,
      );
      await provider.syncUser(user);

      now = now.add(const Duration(days: 7));
      repository.failLoads = true;
      final selected = await provider.refresh(storeCode: 'CP75');

      expect(repository.loadCount, 2);
      expect(selected?.links['APP_DOWNLOAD'], 'https://example.com/app');
    },
  );

  test('permission change rejects the previous persistent cache', () async {
    final repository = _FakeQuickActionsRepository(singleStore: true);
    final localCache = _FakeQuickActionsCacheStore();
    final firstSession = QuickActionsProvider(
      repository,
      localCache: localCache,
    );
    await firstSession.syncUser(user);

    final secondSession = QuickActionsProvider(
      repository,
      localCache: localCache,
    );
    await secondSession.syncUser(
      const User(
        id: 'user-1',
        email: 'staff@phongvu.vn',
        featureAccess: {
          'QUICK_ACTIONS': true,
          'QUICK_ACTION_APP_DOWNLOAD': true,
        },
      ),
    );

    expect(repository.loadCount, 2);
  });

  test('deduplicates concurrent showroom cache misses', () async {
    final repository = _FakeQuickActionsRepository(singleStore: false);
    final provider = QuickActionsProvider(
      repository,
      localCache: _FakeQuickActionsCacheStore(),
    );
    await provider.syncUser(user);
    repository.loadGate = Completer<void>();

    final first = provider.refresh(storeCode: 'CP75');
    final second = provider.refresh(storeCode: 'cp75');
    await Future<void>.delayed(Duration.zero);

    expect(repository.loadCount, 2);
    repository.loadGate!.complete();
    await Future.wait([first, second]);
    expect(repository.loadCount, 2);
  });

  test(
    'force refresh bypasses disk and memory cache after admin save',
    () async {
      final repository = _FakeQuickActionsRepository(singleStore: true);
      final provider = QuickActionsProvider(
        repository,
        localCache: _FakeQuickActionsCacheStore(),
      );
      await provider.syncUser(user);

      await provider.refresh(storeCode: 'CP75', force: true);

      expect(repository.loadCount, 2);
    },
  );

  test(
    'defers initial API load until the launcher surface is active',
    () async {
      final repository = _FakeQuickActionsRepository(singleStore: false);
      final provider = QuickActionsProvider(
        repository,
        localCache: _FakeQuickActionsCacheStore(),
      );

      await provider.syncUser(user, isSurfaceActive: false);
      await provider.syncUser(user, isSurfaceActive: false);
      expect(repository.loadCount, 0);
      expect(provider.payload, isNull);

      await provider.syncUser(user, isSurfaceActive: true);
      await provider.syncUser(user, isSurfaceActive: true);
      expect(repository.loadCount, 1);
    },
  );

  test(
    'realtime store update invalidates scope and QR then reloads exactly once',
    () async {
      final repository = _FakeQuickActionsRepository(singleStore: false)
        ..availableActionCodes = const {};
      final localCache = _FakeQuickActionsCacheStore();
      final realtime = _FakeRealtimeClient();
      final provider = QuickActionsProvider(
        repository,
        localCache: localCache,
        realtimeClient: realtime,
      );
      addTearDown(provider.dispose);
      addTearDown(realtime.dispose);
      await provider.syncUser(user);
      expect(repository.loadCount, 1);

      realtime.add(_quickActionLinksUpdated('CP99'));
      await _flushAsyncWork();
      expect(repository.loadCount, 1);
      expect(localCache.removedKeys, isEmpty);

      repository.availableActionCodes = const {'APP_DOWNLOAD'};
      realtime.add(_quickActionLinksUpdated('CP75'));
      await _flushAsyncWork();

      expect(repository.loadCount, 2);
      expect(provider.payload?.availableActionCodes, {'APP_DOWNLOAD'});
      expect(localCache.removedKeys, {'user-1|__scope__', 'user-1|CP75'});
    },
  );

  test(
    'realtime update defers the single reload while surface is inactive',
    () async {
      final repository = _FakeQuickActionsRepository(singleStore: true);
      final localCache = _FakeQuickActionsCacheStore();
      final realtime = _FakeRealtimeClient();
      final provider = QuickActionsProvider(
        repository,
        localCache: localCache,
        realtimeClient: realtime,
      );
      addTearDown(provider.dispose);
      addTearDown(realtime.dispose);

      await provider.syncUser(user, isSurfaceActive: false);
      realtime.add(_quickActionLinksUpdated('CP75'));
      await _flushAsyncWork();
      expect(repository.loadCount, 0);

      await provider.syncUser(user, isSurfaceActive: true);
      expect(repository.loadCount, 1);
    },
  );
}

RealtimeEnvelope _quickActionLinksUpdated(String storeCode) => RealtimeEnvelope(
  version: 2,
  kind: 'QUICK_ACTION_LINKS_UPDATED',
  id: 'quick-action-$storeCode',
  topic: 'quick-actions.links',
  sequence: 1,
  timestamp: DateTime.utc(2026, 7, 17),
  data: {'storeCode': storeCode, 'configuredCount': 1},
);

Future<void> _flushAsyncWork() async {
  for (var index = 0; index < 8; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _FakeQuickActionsRepository extends QuickActionsRepository {
  final bool singleStore;
  int loadCount = 0;
  bool failLoads = false;
  Completer<void>? loadGate;
  Set<String> availableActionCodes = const {'APP_DOWNLOAD'};

  _FakeQuickActionsRepository({required this.singleStore}) : super(ApiClient());

  @override
  Future<QuickActionsPayload> load({String? storeCode}) async {
    loadCount += 1;
    await loadGate?.future;
    if (failLoads) throw StateError('network unavailable');
    final selectedStoreCode =
        storeCode?.toUpperCase() ?? (singleStore ? 'CP75' : null);
    return QuickActionsPayload(
      stores: const [
        QuickActionStore(storeCode: 'CP75', storeName: 'Showroom 75'),
        QuickActionStore(storeCode: 'CP01', storeName: 'Showroom 1'),
      ].take(singleStore ? 1 : 2).toList(growable: false),
      selectedStoreCode: selectedStoreCode,
      availableActionCodes: availableActionCodes,
      links: {
        'APP_DOWNLOAD': selectedStoreCode == null
            ? null
            : 'https://example.com/app',
      },
    );
  }
}

class _FakeQuickActionsCacheStore implements QuickActionsCacheStore {
  final Map<String, ({String identity, QuickActionsCacheRecord record})>
  _records = {};
  final Set<String> removedKeys = {};

  @override
  Future<QuickActionsCacheRecord?> read({
    required String ownerId,
    required String cacheIdentity,
    required String cacheKey,
  }) async {
    final saved = _records['$ownerId|$cacheKey'];
    return saved?.identity == cacheIdentity ? saved?.record : null;
  }

  @override
  Future<void> write({
    required String ownerId,
    required String cacheIdentity,
    required String cacheKey,
    required QuickActionsCacheRecord record,
  }) async {
    _records['$ownerId|$cacheKey'] = (identity: cacheIdentity, record: record);
  }

  @override
  Future<void> remove({
    required String ownerId,
    required String cacheKey,
  }) async {
    removedKeys.add('$ownerId|$cacheKey');
    _records.remove('$ownerId|$cacheKey');
  }
}

class _FakeRealtimeClient implements RealtimeClient {
  final StreamController<RealtimeEnvelope> _events =
      StreamController<RealtimeEnvelope>.broadcast();

  @override
  Stream<RealtimeEnvelope> get events => _events.stream;

  @override
  Stream<RealtimeSyncReason> get syncRequests => const Stream.empty();

  void add(RealtimeEnvelope event) => _events.add(event);

  @override
  Future<void> syncSession(String? sessionKey) async {}

  Future<void> dispose() => _events.close();
}
