import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/data/app_query_cache.dart';

void main() {
  test('fresh cache hit does not call loader again', () async {
    final now = DateTime.utc(2026, 7, 15, 8);
    final cache = AppQueryCache(now: () => now);
    var calls = 0;

    final first = await cache.getOrLoad<int>(
      key: const AppQueryKey('production:user-1:summary'),
      policy: const AppQueryPolicy(ttl: Duration(minutes: 1)),
      loader: () async => ++calls,
    );
    final second = await cache.getOrLoad<int>(
      key: const AppQueryKey('production:user-1:summary'),
      policy: const AppQueryPolicy(ttl: Duration(minutes: 1)),
      loader: () async => ++calls,
    );

    expect(first.source, AppQuerySource.network);
    expect(second.source, AppQuerySource.memory);
    expect(second.data, 1);
    expect(calls, 1);
  });

  test('concurrent reads deduplicate the in-flight loader by key', () async {
    final cache = AppQueryCache();
    final response = Completer<String>();
    var calls = 0;

    Future<String> loader() {
      calls += 1;
      return response.future;
    }

    final first = cache.getOrLoad<String>(
      key: const AppQueryKey('production:user-1:access'),
      policy: const AppQueryPolicy(ttl: Duration(minutes: 15)),
      loader: loader,
    );
    final second = cache.getOrLoad<String>(
      key: const AppQueryKey('production:user-1:access'),
      policy: const AppQueryPolicy(ttl: Duration(minutes: 15)),
      loader: loader,
    );
    response.complete('ready');

    expect((await first).data, 'ready');
    expect((await second).data, 'ready');
    expect(calls, 1);
  });

  test('stale snapshot is retained when revalidation fails', () async {
    var now = DateTime.utc(2026, 7, 15, 8);
    final cache = AppQueryCache(now: () => now);
    const key = AppQueryKey('production:user-1:menu');
    const policy = AppQueryPolicy(ttl: Duration(minutes: 1));

    await cache.getOrLoad<Map<String, bool>>(
      key: key,
      policy: policy,
      loader: () async => {'HOME': true},
    );
    now = now.add(const Duration(minutes: 2));
    final stale = await cache.getOrLoad<Map<String, bool>>(
      key: key,
      policy: policy,
      loader: () async => throw StateError('offline'),
    );

    expect(stale.data, {'HOME': true});
    expect(stale.source, AppQuerySource.staleFallback);
    expect(stale.isStaleAt(now), isTrue);
  });

  test('optional persistence restores a fresh snapshot without HTTP', () async {
    final now = DateTime.utc(2026, 7, 15, 8);
    final persistence = _MemoryPersistence();
    const key = AppQueryKey('production:user-1:scope-options');
    const policy = AppQueryPolicy(ttl: Duration(hours: 24));
    const codec = AppQueryCodec<List<String>>(
      encode: _encodeStrings,
      decode: _decodeStrings,
    );
    await AppQueryCache(
      persistence: persistence,
      now: () => now,
    ).getOrLoad<List<String>>(
      key: key,
      policy: policy,
      codec: codec,
      loader: () async => ['CP01', 'CP02'],
    );

    var calls = 0;
    final restored =
        await AppQueryCache(
          persistence: persistence,
          now: () => now,
        ).getOrLoad<List<String>>(
          key: key,
          policy: policy,
          codec: codec,
          loader: () async {
            calls += 1;
            return const [];
          },
        );

    expect(restored.data, ['CP01', 'CP02']);
    expect(restored.source, AppQuerySource.persistence);
    expect(calls, 0);
  });

  test('tag invalidation removes every related query key', () async {
    final cache = AppQueryCache();
    var calls = 0;
    const policy = AppQueryPolicy(ttl: Duration(minutes: 5));

    for (final key in const [
      AppQueryKey('production:user-1:home:today'),
      AppQueryKey('production:user-1:home:week'),
    ]) {
      await cache.getOrLoad<int>(
        key: key,
        policy: policy,
        tags: const ['home.summary'],
        loader: () async => ++calls,
      );
    }
    await cache.invalidateTag('home.summary');
    for (final key in const [
      AppQueryKey('production:user-1:home:today'),
      AppQueryKey('production:user-1:home:week'),
    ]) {
      await cache.getOrLoad<int>(
        key: key,
        policy: policy,
        tags: const ['home.summary'],
        loader: () async => ++calls,
      );
    }

    expect(calls, 4);
  });
}

Object? _encodeStrings(List<String> values) => values;

List<String> _decodeStrings(Object? value) =>
    (value as List).map((item) => item.toString()).toList(growable: false);

class _MemoryPersistence implements AppQueryPersistence {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
