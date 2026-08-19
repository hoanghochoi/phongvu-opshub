import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/storage/app_storage_keys.dart';
import 'package:phongvu_opshub/features/auth/data/auth_credential_store.dart';

void main() {
  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  test('empty storage returns null', () async {
    final storage = _MemorySecureStorage();
    final store = AuthCredentialStore(storage: storage);

    expect(await store.read(), isNull);
    expect(storage.values, isEmpty);
  });

  test('save/read/clear uses the environment-scoped secure key', () async {
    final storage = _MemorySecureStorage();
    final store = AuthCredentialStore(storage: storage);

    await store.save(email: 'staff@phongvu.vn', password: 'Password 1!');

    final raw = storage.values[store.namespacedStorageKey];
    expect(raw, isNotNull);
    expect(jsonDecode(raw!)['email'], 'staff@phongvu.vn');
    expect(jsonDecode(raw)['password'], 'Password 1!');
    expect(
      await store.read(),
      const RememberedLogin(email: 'staff@phongvu.vn', password: 'Password 1!'),
    );

    await store.clear();
    expect(storage.values, isEmpty);
    expect(
      AppStorageKeys.secure(AuthCredentialStore.storageKey),
      store.namespacedStorageKey,
    );
  });

  test('partial or corrupt values are deleted and treated as empty', () async {
    final storage = _MemorySecureStorage();
    final store = AuthCredentialStore(storage: storage);

    storage.values[store.namespacedStorageKey] = jsonEncode({
      'version': AuthCredentialStore.schemaVersion,
      'email': 'staff@phongvu.vn',
    });
    expect(await store.read(), isNull);
    expect(storage.values, isEmpty);

    storage.values[store.namespacedStorageKey] = '{not-json';
    expect(await store.read(), isNull);
    expect(storage.values, isEmpty);
  });

  test('storage failures propagate without a plaintext fallback', () async {
    final storage = _MemorySecureStorage()..readError = StateError('locked');
    final store = AuthCredentialStore(storage: storage);

    await expectLater(store.read(), throwsStateError);
    expect(storage.values, isEmpty);
  });

  test('invalid credentials are rejected before writing', () async {
    final storage = _MemorySecureStorage();
    final store = AuthCredentialStore(storage: storage);

    await expectLater(
      store.save(email: ' ', password: 'secret'),
      throwsArgumentError,
    );
    await expectLater(
      store.save(email: 'staff@phongvu.vn', password: ''),
      throwsArgumentError,
    );
    expect(storage.values, isEmpty);
  });
}

class _MemorySecureStorage implements AuthSecureStorage {
  final Map<String, String> values = {};
  Object? readError;
  Object? writeError;
  Object? deleteError;

  @override
  Future<String?> read({required String key}) async {
    final error = readError;
    if (error != null) throw error;
    return values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    final error = writeError;
    if (error != null) throw error;
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    final error = deleteError;
    if (error != null) throw error;
    values.remove(key);
  }
}
