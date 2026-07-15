import 'dart:convert';

import '../logging/app_logger.dart';

/// Stable identity for a cached read. Callers should include the environment,
/// authenticated user and every parameter that can change the response.
class AppQueryKey {
  final String value;

  const AppQueryKey(this.value) : assert(value != '');

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AppQueryKey && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

class AppQueryPolicy {
  final Duration ttl;
  final bool serveStaleOnError;

  const AppQueryPolicy({required this.ttl, this.serveStaleOnError = true});
}

enum AppQuerySource { memory, persistence, network, staleFallback }

class AppQuerySnapshot<T> {
  final T data;
  final DateTime fetchedAt;
  final Duration ttl;
  final AppQuerySource source;

  const AppQuerySnapshot({
    required this.data,
    required this.fetchedAt,
    required this.ttl,
    required this.source,
  });

  DateTime get expiresAt => fetchedAt.add(ttl);

  bool isFreshAt(DateTime value) => value.isBefore(expiresAt);

  bool isStaleAt(DateTime value) => !isFreshAt(value);

  AppQuerySnapshot<T> copyWith({Duration? ttl, AppQuerySource? source}) {
    return AppQuerySnapshot<T>(
      data: data,
      fetchedAt: fetchedAt,
      ttl: ttl ?? this.ttl,
      source: source ?? this.source,
    );
  }
}

/// Optional raw persistence boundary. Implementations can use
/// SharedPreferences, a file store or a database without coupling the cache to
/// a platform package.
abstract interface class AppQueryPersistence {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> remove(String key);
}

class AppQueryCodec<T> {
  final Object? Function(T value) encode;
  final T Function(Object? value) decode;

  const AppQueryCodec({required this.encode, required this.decode});
}

typedef AppQueryLoader<T> = Future<T> Function();

/// Small cache-aside store with per-key in-flight request deduplication.
class AppQueryCache {
  final AppQueryPersistence? _persistence;
  final DateTime Function() _now;
  final Map<AppQueryKey, AppQuerySnapshot<Object?>> _memory = {};
  final Map<AppQueryKey, Future<AppQuerySnapshot<dynamic>>> _inFlight = {};
  final Map<String, Set<AppQueryKey>> _keysByTag = {};

  AppQueryCache({AppQueryPersistence? persistence, DateTime Function()? now})
    : _persistence = persistence,
      _now = now ?? DateTime.now;

  AppQuerySnapshot<T>? peek<T>(AppQueryKey key) {
    final snapshot = _memory[key];
    if (snapshot == null) return null;
    return _castSnapshot<T>(snapshot);
  }

  Future<AppQuerySnapshot<T>> getOrLoad<T>({
    required AppQueryKey key,
    required AppQueryPolicy policy,
    required AppQueryLoader<T> loader,
    AppQueryCodec<T>? codec,
    bool forceRefresh = false,
    Iterable<String> tags = const [],
  }) async {
    _registerTags(key, tags);
    final memory = peek<T>(key);
    if (!forceRefresh && memory != null && memory.isFreshAt(_now())) {
      return memory.copyWith(source: AppQuerySource.memory);
    }

    final running = _inFlight[key];
    if (running != null) {
      return _castSnapshot<T>(await running);
    }

    final future = _load<T>(
      key: key,
      policy: policy,
      loader: loader,
      codec: codec,
      forceRefresh: forceRefresh,
      memory: memory,
    );
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<AppQuerySnapshot<T>> _load<T>({
    required AppQueryKey key,
    required AppQueryPolicy policy,
    required AppQueryLoader<T> loader,
    required AppQueryCodec<T>? codec,
    required bool forceRefresh,
    required AppQuerySnapshot<T>? memory,
  }) async {
    var cached = memory;
    if (cached == null && codec != null && _persistence != null) {
      cached = await _readPersisted<T>(key, policy, codec);
      if (cached != null) {
        _memory[key] = _eraseType(cached);
        if (!forceRefresh && cached.isFreshAt(_now())) return cached;
      }
    }

    try {
      final data = await loader();
      final snapshot = AppQuerySnapshot<T>(
        data: data,
        fetchedAt: _now(),
        ttl: policy.ttl,
        source: AppQuerySource.network,
      );
      _memory[key] = _eraseType(snapshot);
      if (codec != null && _persistence != null) {
        await _persistBestEffort(key, snapshot, codec);
      }
      return snapshot;
    } catch (_) {
      if (cached != null && policy.serveStaleOnError) {
        return cached.copyWith(
          ttl: policy.ttl,
          source: AppQuerySource.staleFallback,
        );
      }
      rethrow;
    }
  }

  Future<AppQuerySnapshot<T>?> _readPersisted<T>(
    AppQueryKey key,
    AppQueryPolicy policy,
    AppQueryCodec<T> codec,
  ) async {
    String? raw;
    try {
      raw = await _persistence!.read(key.value);
    } catch (error) {
      await _logPersistenceFailure('read', error);
      return null;
    }
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final fetchedAt = DateTime.tryParse(
        decoded['fetchedAt']?.toString() ?? '',
      );
      if (fetchedAt == null) return null;
      return AppQuerySnapshot<T>(
        data: codec.decode(decoded['data']),
        fetchedAt: fetchedAt,
        ttl: policy.ttl,
        source: AppQuerySource.persistence,
      );
    } catch (_) {
      try {
        await _persistence.remove(key.value);
      } catch (error) {
        await _logPersistenceFailure('remove_invalid', error);
      }
      return null;
    }
  }

  Future<void> put<T>({
    required AppQueryKey key,
    required T data,
    required AppQueryPolicy policy,
    AppQueryCodec<T>? codec,
    Iterable<String> tags = const [],
  }) async {
    _registerTags(key, tags);
    final snapshot = AppQuerySnapshot<T>(
      data: data,
      fetchedAt: _now(),
      ttl: policy.ttl,
      source: AppQuerySource.network,
    );
    _memory[key] = _eraseType(snapshot);
    if (codec != null && _persistence != null) {
      await _persistBestEffort(key, snapshot, codec);
    }
  }

  Future<void> _persistBestEffort<T>(
    AppQueryKey key,
    AppQuerySnapshot<T> snapshot,
    AppQueryCodec<T> codec,
  ) async {
    try {
      await _persistence!.write(
        key.value,
        jsonEncode({
          'fetchedAt': snapshot.fetchedAt.toUtc().toIso8601String(),
          'data': codec.encode(snapshot.data),
        }),
      );
    } catch (error) {
      await _logPersistenceFailure('write', error);
    }
  }

  Future<void> _logPersistenceFailure(String operation, Object error) {
    return AppLogger.instance.warn(
      'AppQueryCache',
      'Query cache persistence operation failed; memory result retained',
      context: {
        'operation': operation,
        'errorType': error.runtimeType.toString(),
      },
    );
  }

  Future<void> invalidate(AppQueryKey key) async {
    _memory.remove(key);
    for (final keys in _keysByTag.values) {
      keys.remove(key);
    }
    _keysByTag.removeWhere((_, keys) => keys.isEmpty);
    await _persistence?.remove(key.value);
  }

  Future<void> invalidateTag(String tag) async {
    final normalized = tag.trim();
    if (normalized.isEmpty) return;
    final keys = Set<AppQueryKey>.from(_keysByTag[normalized] ?? const {});
    for (final key in keys) {
      await invalidate(key);
    }
  }

  Future<void> clear(Iterable<AppQueryKey> keys) async {
    for (final key in keys) {
      await invalidate(key);
    }
  }

  AppQuerySnapshot<Object?> _eraseType<T>(AppQuerySnapshot<T> snapshot) {
    return AppQuerySnapshot<Object?>(
      data: snapshot.data,
      fetchedAt: snapshot.fetchedAt,
      ttl: snapshot.ttl,
      source: snapshot.source,
    );
  }

  AppQuerySnapshot<T> _castSnapshot<T>(AppQuerySnapshot<Object?> snapshot) {
    return AppQuerySnapshot<T>(
      data: snapshot.data as T,
      fetchedAt: snapshot.fetchedAt,
      ttl: snapshot.ttl,
      source: snapshot.source,
    );
  }

  void _registerTags(AppQueryKey key, Iterable<String> tags) {
    for (final rawTag in tags) {
      final tag = rawTag.trim();
      if (tag.isEmpty) continue;
      (_keysByTag[tag] ??= <AppQueryKey>{}).add(key);
    }
  }
}
