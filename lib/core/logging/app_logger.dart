import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../constants/api_constants.dart';
import '../network/api_client.dart';

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  final ApiClient _apiClient = ApiClient();
  File? _logFile;
  String? _clientId;

  Future<void> initialize({String? clientId}) async {
    _clientId = clientId;
    if (kIsWeb) return;
    try {
      final directory = await getApplicationSupportDirectory();
      final logDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}logs',
      );
      await logDirectory.create(recursive: true);
      _logFile = File(
        '${logDirectory.path}${Platform.pathSeparator}opshub.log',
      );
      await _trimIfNeeded();
    } catch (error) {
      if (kDebugMode) debugPrint('[AppLogger] init failed: $error');
    }
  }

  Future<void> info(
    String source,
    String message, {
    Map<String, Object?>? context,
  }) {
    return _write('info', source, message, context: context);
  }

  Future<void> warn(
    String source,
    String message, {
    Map<String, Object?>? context,
  }) {
    return _write('warn', source, message, context: context);
  }

  Future<void> error(
    String source,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
    bool upload = false,
  }) async {
    final nextContext = {
      if (context != null) ...context,
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stackTrace': stackTrace.toString(),
    };
    await _write('error', source, message, context: nextContext);
    if (upload) {
      await uploadLog('error', source, message, context: nextContext);
    }
  }

  Future<void> uploadLog(
    String level,
    String source,
    String message, {
    Map<String, Object?>? context,
    String? storeCode,
  }) async {
    try {
      await _apiClient.post(
        ApiConstants.appLogsEndpoint,
        body: {
          'level': level,
          'source': source,
          'message': message,
          if (_clientId != null) 'clientId': _clientId,
          if (storeCode != null) 'storeCode': storeCode,
          if (context != null) 'context': _sanitizeJson(context),
        },
      );
    } catch (error) {
      if (kDebugMode) debugPrint('[AppLogger] upload failed: $error');
    }
  }

  Future<void> _write(
    String level,
    String source,
    String message, {
    Map<String, Object?>? context,
  }) async {
    final entry = jsonEncode({
      'ts': DateTime.now().toIso8601String(),
      'level': level,
      'source': source,
      'message': _sanitize(message),
      if (_clientId != null) 'clientId': _clientId,
      if (context != null) 'context': _sanitizeJson(context),
    });
    if (kDebugMode) debugPrint(entry);
    final file = _logFile;
    if (file == null) return;
    try {
      await file.writeAsString('$entry\n', mode: FileMode.append, flush: false);
    } catch (_) {
      // Local logging must never break user flows.
    }
  }

  Future<void> _trimIfNeeded() async {
    final file = _logFile;
    if (file == null || !await file.exists()) return;
    final bytes = await file.length();
    const maxBytes = 2 * 1024 * 1024;
    if (bytes <= maxBytes) return;
    final content = await file.readAsString();
    final keepFrom = (content.length * 0.5).floor();
    await file.writeAsString(content.substring(keepFrom));
  }

  Object? _sanitizeJson(Object? value) {
    if (value is Map) {
      return value.map((key, dynamic item) {
        final keyText = key.toString();
        if (RegExp(
          'token|password|secret|authorization',
          caseSensitive: false,
        ).hasMatch(keyText)) {
          return MapEntry(keyText, '[redacted]');
        }
        return MapEntry(keyText, _sanitizeJson(item));
      });
    }
    if (value is List) return value.map(_sanitizeJson).toList();
    if (value is String) return _sanitize(value);
    return value;
  }

  String _sanitize(String value) {
    return value.replaceAll(
      RegExp(
        r'(Bearer\s+)[A-Za-z0-9._-]+|("?(?:password|token|secret|authorization)"?\s*[:=]\s*)("[^"]+"|[^\s,}]+)',
        caseSensitive: false,
      ),
      '[redacted]',
    );
  }
}

Future<void> runWithAppLogging(FutureOr<void> Function() body) async {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      AppLogger.instance.error(
        'FlutterError',
        details.exceptionAsString(),
        stackTrace: details.stack,
        upload: true,
      ),
    );
  };

  await runZonedGuarded<Future<void>>(() async => body(), (error, stackTrace) {
    unawaited(
      AppLogger.instance.error(
        'Zone',
        'Uncaught async error',
        error: error,
        stackTrace: stackTrace,
        upload: true,
      ),
    );
  });
}
