import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/app_storage_keys.dart';

class AppNotificationReadStore {
  const AppNotificationReadStore();

  Future<void> markRead({
    required String source,
    required Set<String> ids,
  }) async {
    final values =
        ids
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList()
          ..sort();
    if (values.isEmpty) return;
    await ApiClient().post(
      ApiConstants.notificationsReadEndpoint,
      body: {'source': source, 'ids': values},
    );
  }

  Future<Set<String>> loadSeenIds({
    required String userKey,
    required String source,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_storageKey(userKey, source)) ?? [];
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  Future<void> saveSeenIds({
    required String userKey,
    required String source,
    required Set<String> ids,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final values =
        ids
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList()
          ..sort();
    await prefs.setStringList(_storageKey(userKey, source), values);
  }

  static String? userKey({String? id, String? email}) {
    final raw = (id?.trim().isNotEmpty == true ? id : email)?.trim() ?? '';
    if (raw.isEmpty) return null;
    final sanitized = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return sanitized.isEmpty ? null : sanitized;
  }

  String _storageKey(String userKey, String source) {
    return AppStorageKeys.shared('notifications.seen.$source.$userKey');
  }
}
