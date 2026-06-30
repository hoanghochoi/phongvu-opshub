import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/storage/app_storage_keys.dart';
import '../../domain/entities/vietqr_transfer.dart';

class VietQrHistoryStore {
  static const _storagePrefix = 'vietqr_history';
  static const _maxEntries = 20;

  Future<List<VietQrHistoryEntry>> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey(userId));
    if (jsonStr == null || jsonStr.trim().isEmpty) {
      return const <VietQrHistoryEntry>[];
    }

    final decoded = jsonDecode(jsonStr);
    if (decoded is! List) {
      return const <VietQrHistoryEntry>[];
    }

    return decoded
        .whereType<Map>()
        .map(
          (entry) =>
              VietQrHistoryEntry.fromJson(Map<String, dynamic>.from(entry)),
        )
        .toList(growable: false);
  }

  Future<void> save(String userId, List<VietQrHistoryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = entries.length > _maxEntries
        ? entries.sublist(0, _maxEntries)
        : entries;
    await prefs.setString(
      _storageKey(userId),
      jsonEncode(
        trimmed.map((entry) => entry.toJson()).toList(growable: false),
      ),
    );
  }

  String _storageKey(String userId) {
    final normalizedUserId = _normalize(userId);
    return AppStorageKeys.shared('$_storagePrefix.$normalizedUserId');
  }

  String _normalize(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return 'guest';
    return normalized.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }
}
