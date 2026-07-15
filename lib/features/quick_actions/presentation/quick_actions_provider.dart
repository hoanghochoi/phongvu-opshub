import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/logging/app_logger.dart';
import '../../auth/domain/entities/user.dart';
import '../data/quick_actions_local_cache.dart';
import '../data/quick_actions_repository.dart';

class QuickActionsProvider extends ChangeNotifier {
  static const defaultScopeCacheTtl = Duration(hours: 24);
  static const defaultQrCacheTtl = Duration(days: 7);
  static const _scopeCacheKey = '__scope__';

  final QuickActionsRepository _repository;
  final QuickActionsCacheStore _localCache;
  final Duration scopeCacheTtl;
  final Duration qrCacheTtl;
  final DateTime Function() _now;
  QuickActionsPayload? _payload;
  bool _loading = false;
  final Map<String, QuickActionsCacheRecord> _cache = {};
  final Map<String, Future<QuickActionsPayload?>> _refreshInFlight = {};
  Object? _error;
  String? _userKey;
  String? _ownerId;
  int _userGeneration = 0;

  QuickActionsProvider(
    this._repository, {
    QuickActionsCacheStore? localCache,
    this.scopeCacheTtl = defaultScopeCacheTtl,
    this.qrCacheTtl = defaultQrCacheTtl,
    DateTime Function()? now,
  }) : _localCache = localCache ?? SharedPreferencesQuickActionsCacheStore(),
       _now = now ?? DateTime.now;

  QuickActionsPayload? get payload => _payload;
  bool get isLoading => _loading;
  Object? get error => _error;

  Future<void> syncUser(User? user) async {
    final nextUserKey = _cacheIdentityFor(user);
    if (_userKey == nextUserKey) return;
    _userKey = nextUserKey;
    _ownerId = user == null ? null : (user.id ?? user.email.toLowerCase());
    _userGeneration += 1;
    final generation = _userGeneration;
    _payload = null;
    _loading = false;
    _error = null;
    _cache.clear();
    _refreshInFlight.clear();
    if (user?.canUseFeature('QUICK_ACTIONS') != true ||
        nextUserKey == null ||
        _ownerId == null) {
      notifyListeners();
      return;
    }

    final persisted = await _readPersistent(_scopeCacheKey);
    if (generation != _userGeneration) return;
    if (persisted == null) {
      await refresh(force: true);
      return;
    }
    _cache[_scopeCacheKey] = persisted;
    _payload = persisted.payload;
    notifyListeners();
    if (!_isFresh(persisted, scopeCacheTtl)) {
      unawaited(refresh(force: true));
    }
  }

  Future<QuickActionsPayload?> refresh({
    String? storeCode,
    bool force = false,
  }) async {
    final normalizedStoreCode = _normalizeStoreCode(storeCode);
    final cacheKey = normalizedStoreCode ?? _scopeCacheKey;
    final ttl = normalizedStoreCode == null ? scopeCacheTtl : qrCacheTtl;
    if (!force) {
      final memory = _cache[cacheKey];
      if (memory != null && _isFresh(memory, ttl)) {
        return _useCache(cacheKey, memory, source: 'memory');
      }
    }

    final running = _refreshInFlight[cacheKey];
    if (running != null) return running;

    QuickActionsCacheRecord? persisted;
    if (!force) {
      persisted = await _readPersistent(cacheKey);
      if (persisted != null) {
        _cache[cacheKey] = persisted;
        if (_isFresh(persisted, ttl)) {
          return _useCache(cacheKey, persisted, source: 'disk');
        }
      }
    }

    final runningAfterDiskRead = _refreshInFlight[cacheKey];
    if (runningAfterDiskRead != null) return runningAfterDiskRead;

    final request = _load(
      storeCode: normalizedStoreCode,
      userGeneration: _userGeneration,
      staleFallback: persisted ?? _cache[cacheKey],
    );
    _refreshInFlight[cacheKey] = request;
    try {
      return await request;
    } finally {
      if (identical(_refreshInFlight[cacheKey], request)) {
        _refreshInFlight.remove(cacheKey);
      }
    }
  }

  void revalidateScopeIfStale() {
    if (_userKey == null) return;
    final cached = _cache[_scopeCacheKey];
    if (cached != null && _isFresh(cached, scopeCacheTtl)) return;
    unawaited(refresh());
  }

  Future<QuickActionsPayload?> _load({
    required String? storeCode,
    required int userGeneration,
    required QuickActionsCacheRecord? staleFallback,
  }) async {
    final startedAt = _now();
    _loading = true;
    _error = null;
    notifyListeners();
    await AppLogger.instance.info(
      'QuickActions',
      'Quick actions load started',
      context: {'storeCode': storeCode},
    );
    try {
      final loaded = await _repository.load(storeCode: storeCode);
      if (userGeneration != _userGeneration) return null;
      final loadedAt = _now();
      final scopeRecord = QuickActionsCacheRecord(
        payload: QuickActionsPayload(
          stores: loaded.stores,
          selectedStoreCode: null,
          availableActionCodes: loaded.availableActionCodes,
          links: const {},
        ),
        loadedAt: loadedAt,
      );
      _cache[_scopeCacheKey] = scopeRecord;
      await _writePersistent(_scopeCacheKey, scopeRecord);
      if (userGeneration != _userGeneration) return null;

      final selectedStoreCode = _normalizeStoreCode(
        loaded.selectedStoreCode ?? storeCode,
      );
      if (selectedStoreCode != null) {
        final storeRecord = QuickActionsCacheRecord(
          payload: loaded,
          loadedAt: loadedAt,
        );
        _cache[selectedStoreCode] = storeRecord;
        await _writePersistent(selectedStoreCode, storeRecord);
        if (userGeneration != _userGeneration) return null;
      }
      _payload = loaded;
      await AppLogger.instance.info(
        'QuickActions',
        'Quick actions load succeeded',
        context: {
          'storeCode': loaded.selectedStoreCode,
          'storeCount': loaded.stores.length,
          'availableCount': loaded.availableActionCodes.length,
          'durationMs': _now().difference(startedAt).inMilliseconds,
        },
      );
      return loaded;
    } catch (error, stackTrace) {
      if (userGeneration != _userGeneration) return null;
      _error = error;
      await AppLogger.instance.error(
        'QuickActions',
        'Quick actions load failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'storeCode': storeCode,
          'hasStaleFallback': staleFallback != null,
          'durationMs': _now().difference(startedAt).inMilliseconds,
        },
      );
      if (staleFallback != null) {
        _payload = staleFallback.payload;
        return staleFallback.payload;
      }
      return null;
    } finally {
      if (userGeneration == _userGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<QuickActionsPayload?> _useCache(
    String cacheKey,
    QuickActionsCacheRecord record, {
    required String source,
  }) async {
    final changed = !identical(_payload, record.payload);
    _payload = record.payload;
    _error = null;
    if (changed) notifyListeners();
    unawaited(
      AppLogger.instance.info(
        'QuickActions',
        'Quick actions cache hit',
        context: {
          'storeCode': cacheKey == _scopeCacheKey ? null : cacheKey,
          'source': source,
          'cacheAgeSeconds': _now().difference(record.loadedAt).inSeconds,
        },
      ),
    );
    return record.payload;
  }

  Future<QuickActionsCacheRecord?> _readPersistent(String cacheKey) async {
    final ownerId = _ownerId;
    final cacheIdentity = _userKey;
    if (ownerId == null || cacheIdentity == null) return null;
    return _localCache.read(
      ownerId: ownerId,
      cacheIdentity: cacheIdentity,
      cacheKey: cacheKey,
    );
  }

  Future<void> _writePersistent(
    String cacheKey,
    QuickActionsCacheRecord record,
  ) async {
    final ownerId = _ownerId;
    final cacheIdentity = _userKey;
    if (ownerId == null || cacheIdentity == null) return;
    try {
      await _localCache.write(
        ownerId: ownerId,
        cacheIdentity: cacheIdentity,
        cacheKey: cacheKey,
        record: record,
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'QuickActions',
        'Quick actions local cache write failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'cacheType': cacheKey == _scopeCacheKey ? 'scope' : 'showroom',
        },
      );
    }
  }

  bool _isFresh(QuickActionsCacheRecord record, Duration ttl) =>
      _now().difference(record.loadedAt) < ttl;

  String? _normalizeStoreCode(String? storeCode) {
    final normalized = storeCode?.trim().toUpperCase();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  String? _cacheIdentityFor(User? user) {
    if (user == null) return null;
    final permissionEntries = user.featureAccess.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final assignmentIds =
        user.organizationAssignments
            .map((item) => item.organizationNodeId)
            .toList()
          ..sort();
    return [
      user.id ?? user.email,
      user.storeId ?? '',
      user.organizationNodeId ?? '',
      assignmentIds.join(','),
      permissionEntries
          .map((entry) => '${entry.key}:${entry.value ? 1 : 0}')
          .join(','),
    ].join('|');
  }
}
