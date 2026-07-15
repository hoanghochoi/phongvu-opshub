import 'package:shared_preferences/shared_preferences.dart';

import 'app_query_cache.dart';

/// SharedPreferences-backed storage for the small, explicitly approved query
/// snapshots. An index lets logout remove every persisted query atomically from
/// the application's point of view.
class SharedPreferencesQueryPersistence implements AppQueryPersistence {
  const SharedPreferencesQueryPersistence();

  static const _prefix = 'app_query_cache_v1:';
  static const _indexKey = '${_prefix}index';

  @override
  Future<String?> read(String key) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_storageKey(key));
  }

  @override
  Future<void> write(String key, String value) async {
    final preferences = await SharedPreferences.getInstance();
    final storageKey = _storageKey(key);
    await preferences.setString(storageKey, value);
    final keys = preferences.getStringList(_indexKey)?.toSet() ?? <String>{};
    if (keys.add(storageKey)) {
      await preferences.setStringList(_indexKey, keys.toList()..sort());
    }
  }

  @override
  Future<void> remove(String key) async {
    final preferences = await SharedPreferences.getInstance();
    final storageKey = _storageKey(key);
    await preferences.remove(storageKey);
    final keys = preferences.getStringList(_indexKey)?.toSet() ?? <String>{};
    if (keys.remove(storageKey)) {
      await preferences.setStringList(_indexKey, keys.toList()..sort());
    }
  }

  static Future<void> clearAll() async {
    final preferences = await SharedPreferences.getInstance();
    final keys = preferences.getStringList(_indexKey) ?? const <String>[];
    for (final key in keys) {
      await preferences.remove(key);
    }
    await preferences.remove(_indexKey);
  }

  static String _storageKey(String key) =>
      '$_prefix${Uri.encodeComponent(key)}';
}
