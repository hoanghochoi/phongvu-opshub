import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/app_storage_keys.dart';
import 'quick_actions_repository.dart';

class QuickActionsCacheRecord {
  final QuickActionsPayload payload;
  final DateTime loadedAt;

  const QuickActionsCacheRecord({
    required this.payload,
    required this.loadedAt,
  });
}

abstract class QuickActionsCacheStore {
  Future<QuickActionsCacheRecord?> read({
    required String ownerId,
    required String cacheIdentity,
    required String cacheKey,
  });

  Future<void> write({
    required String ownerId,
    required String cacheIdentity,
    required String cacheKey,
    required QuickActionsCacheRecord record,
  });
}

class SharedPreferencesQuickActionsCacheStore
    implements QuickActionsCacheStore {
  static const _storagePrefix = 'quick_actions_cache.v2';

  @override
  Future<QuickActionsCacheRecord?> read({
    required String ownerId,
    required String cacheIdentity,
    required String cacheKey,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey(ownerId, cacheKey));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final json = Map<String, dynamic>.from(decoded);
      if (json['cacheIdentity']?.toString() != cacheIdentity) return null;
      final payloadJson = json['payload'];
      final loadedAtMs = int.tryParse(json['loadedAtMs']?.toString() ?? '');
      if (payloadJson is! Map || loadedAtMs == null) return null;
      return QuickActionsCacheRecord(
        payload: QuickActionsPayload.fromJson(
          Map<String, dynamic>.from(payloadJson),
        ),
        loadedAt: DateTime.fromMillisecondsSinceEpoch(loadedAtMs),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write({
    required String ownerId,
    required String cacheIdentity,
    required String cacheKey,
    required QuickActionsCacheRecord record,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey(ownerId, cacheKey),
      jsonEncode({
        'cacheIdentity': cacheIdentity,
        'loadedAtMs': record.loadedAt.millisecondsSinceEpoch,
        'payload': record.payload.toJson(),
      }),
    );
  }

  String _storageKey(String ownerId, String cacheKey) {
    final ownerHash = sha256.convert(utf8.encode(ownerId)).toString();
    final cacheHash = sha256.convert(utf8.encode(cacheKey)).toString();
    return AppStorageKeys.shared('$_storagePrefix.$ownerHash.$cacheHash');
  }
}
