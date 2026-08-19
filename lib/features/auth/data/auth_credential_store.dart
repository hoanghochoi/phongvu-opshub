import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/storage/app_storage_keys.dart';

/// The opt-in credential pair that can be restored on the login screen.
///
/// This value is deliberately separate from the authenticated session. A
/// remembered password never grants access by itself and is only used to
/// pre-fill the public login form.
class RememberedLogin {
  const RememberedLogin({required this.email, required this.password});

  final String email;
  final String password;

  @override
  bool operator ==(Object other) =>
      other is RememberedLogin &&
      other.email == email &&
      other.password == password;

  @override
  int get hashCode => Object.hash(email, password);
}

abstract interface class AuthSecureStorage {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class FlutterAuthSecureStorage implements AuthSecureStorage {
  FlutterAuthSecureStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

/// Secure, versioned storage for the optional login credential pair.
///
/// The JSON envelope is stored only in the platform secure-storage backend.
/// SharedPreferences is intentionally not used because it is not an
/// appropriate place for a password, even when the user opted in.
class AuthCredentialStore {
  AuthCredentialStore({AuthSecureStorage? storage})
    : _storage = storage ?? FlutterAuthSecureStorage();

  static const storageKey = 'auth.remembered_login.v1';
  static const schemaVersion = 1;

  final AuthSecureStorage _storage;

  String get namespacedStorageKey => AppStorageKeys.secure(storageKey);

  Future<RememberedLogin?> read() async {
    final stopwatch = Stopwatch()..start();
    try {
      final raw = await _storage.read(key: namespacedStorageKey);
      if (raw == null || raw.trim().isEmpty) {
        await _log(
          'Remembered credential read completed',
          context: _logContext(stopwatch, status: 'empty'),
        );
        return null;
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        return _discardCorruptValue(stopwatch);
      } on TypeError {
        return _discardCorruptValue(stopwatch);
      }
      if (decoded is! Map) return _discardCorruptValue(stopwatch);
      late final Map<String, dynamic> data;
      try {
        data = Map<String, dynamic>.from(decoded);
      } on TypeError {
        return _discardCorruptValue(stopwatch);
      }
      final emailValue = data['email'];
      final passwordValue = data['password'];
      if (data['version'] != schemaVersion ||
          emailValue is! String ||
          passwordValue is! String) {
        return _discardCorruptValue(stopwatch);
      }
      final email = emailValue.trim();
      final password = passwordValue;
      if (email.isEmpty || password.isEmpty) {
        return _discardCorruptValue(stopwatch);
      }
      await _log(
        'Remembered credential read completed',
        context: _logContext(
          stopwatch,
          status: 'loaded',
          email: email,
          passwordLength: password.length,
        ),
      );
      return RememberedLogin(email: email, password: password);
    } catch (error, stackTrace) {
      await _log(
        'Remembered credential read failed',
        level: 'error',
        error: error,
        stackTrace: stackTrace,
        context: _logContext(stopwatch, status: 'failed'),
      );
      rethrow;
    }
  }

  Future<void> save({required String email, required String password}) async {
    final stopwatch = Stopwatch()..start();
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      await _log(
        'Remembered credential save rejected',
        level: 'warn',
        context: _logContext(
          stopwatch,
          status: 'invalid',
          email: normalizedEmail,
          passwordLength: password.length,
        ),
      );
      throw ArgumentError('Remembered login requires email and password.');
    }
    try {
      await _storage.write(
        key: namespacedStorageKey,
        value: jsonEncode({
          'version': schemaVersion,
          'email': normalizedEmail,
          'password': password,
        }),
      );
      await _log(
        'Remembered credential save completed',
        context: _logContext(
          stopwatch,
          status: 'saved',
          email: normalizedEmail,
          passwordLength: password.length,
        ),
      );
    } catch (error, stackTrace) {
      await _log(
        'Remembered credential save failed',
        level: 'error',
        error: error,
        stackTrace: stackTrace,
        context: _logContext(
          stopwatch,
          status: 'failed',
          email: normalizedEmail,
          passwordLength: password.length,
        ),
      );
      rethrow;
    }
  }

  Future<void> clear() async {
    final stopwatch = Stopwatch()..start();
    try {
      await _storage.delete(key: namespacedStorageKey);
      await _log(
        'Remembered credential clear completed',
        context: _logContext(stopwatch, status: 'cleared'),
      );
    } catch (error, stackTrace) {
      await _log(
        'Remembered credential clear failed',
        level: 'error',
        error: error,
        stackTrace: stackTrace,
        context: _logContext(stopwatch, status: 'failed'),
      );
      rethrow;
    }
  }

  Future<RememberedLogin?> _discardCorruptValue(Stopwatch stopwatch) async {
    await clear();
    await _log(
      'Remembered credential discarded',
      context: _logContext(stopwatch, status: 'corrupt_deleted'),
    );
    return null;
  }

  Map<String, Object?> _logContext(
    Stopwatch stopwatch, {
    required String status,
    String? email,
    int? passwordLength,
  }) {
    return {
      'status': status,
      'durationMs': stopwatch.elapsedMilliseconds,
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'environment': AppStorageKeys.environment,
      'accountRef': _emailSummary(email),
      if (passwordLength != null) 'credentialLength': passwordLength,
    };
  }

  Future<void> _log(
    String message, {
    String level = 'info',
    Object? error,
    StackTrace? stackTrace,
    required Map<String, Object?> context,
  }) {
    return switch (level) {
      'error' => AppLogger.instance.error(
        'AuthCredentialStore',
        message,
        error: error,
        stackTrace: stackTrace,
        context: context,
      ),
      'warn' => AppLogger.instance.warn(
        'AuthCredentialStore',
        message,
        context: context,
      ),
      _ => AppLogger.instance.info(
        'AuthCredentialStore',
        message,
        context: context,
      ),
    };
  }
}

String _emailSummary(String? email) {
  final normalized = email?.trim() ?? '';
  final at = normalized.indexOf('@');
  if (at <= 0 || at == normalized.length - 1) return 'unknown';
  final local = normalized.substring(0, at);
  final domain = normalized.substring(at + 1).toLowerCase();
  return '${local.substring(0, 1)}***@$domain';
}
