import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/api_constants.dart';
import '../network/api_client.dart';
import '../storage/app_storage_keys.dart';
import 'daily_activity_log.dart';
import 'app_log_file.dart';

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  final ApiClient _apiClient = ApiClient();
  File? _logFile;
  String? _clientId;
  bool _uploadsEnabled = true;
  bool _dailyUploadInFlight = false;
  Future<void> _fileOperation = Future<void>.value();

  static const _clientIdPreferenceKey = 'payment_monitor_client_id';
  static const _dailyUploadSuccessKey =
      'app_logger_daily_activity_last_success_date';
  static const _dailyUploadSuccessAtKey =
      'app_logger_daily_activity_last_success_at';

  static String _sharedKey(String key) => AppStorageKeys.shared(key);

  @visibleForTesting
  void setUploadsEnabledForTesting(bool enabled) {
    _uploadsEnabled = enabled;
  }

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
      await _runSerializedFileOperation(
        () => _withLogFileLock(_normalizeAndTrimExistingLog),
      );
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
    if (!_uploadsEnabled) return;
    try {
      await _apiClient.post(
        ApiConstants.appLogsEndpoint,
        body: {
          'level': _sanitize(level),
          'source': _sanitize(source),
          'message': _sanitize(message),
          'environment': AppStorageKeys.environment,
          if (_clientId != null) 'clientId': _sanitize(_clientId!),
          if (storeCode != null) 'storeCode': _sanitize(storeCode),
          if (context != null) 'context': _sanitizeJson(context),
        },
      );
    } catch (error) {
      if (kDebugMode) debugPrint('[AppLogger] upload failed: $error');
    }
  }

  Future<void> uploadDailyActivityLogIfDue({
    String? storeCode,
    DateTime? now,
    bool force = false,
  }) async {
    if (kIsWeb || !_uploadsEnabled || _dailyUploadInFlight) return;
    _dailyUploadInFlight = true;
    String? targetDateKey;
    try {
      final effectiveNow = now ?? DateTime.now();
      final today = DateTime(
        effectiveNow.year,
        effectiveNow.month,
        effectiveNow.day,
      );
      final targetDate = today.subtract(const Duration(days: 1));
      targetDateKey = formatLogDate(targetDate);
      final prefs = await SharedPreferences.getInstance();

      if (!force &&
          prefs.getString(_sharedKey(_dailyUploadSuccessKey)) ==
              targetDateKey) {
        return;
      }
      if (_apiClient.authToken == null) {
        await info(
          'AppLogger',
          'Daily activity log upload skipped',
          context: {'logDate': targetDateKey, 'reason': 'missing_auth_token'},
        );
        return;
      }

      final clientId = await _ensureClientId();
      final file = _logFile;
      final lines = file != null && await file.exists()
          ? await file.readAsLines()
          : const <String>[];
      final summary = buildDailyActivityLogSummary(
        lines,
        targetDate: targetDate,
      );
      final packageInfo = await _packageInfoOrNull();

      await info(
        'AppLogger',
        'Daily activity log upload started',
        context: {
          'logDate': targetDateKey,
          'storeCode': storeCode,
          'matchedLines': summary.matchedLines,
        },
      );

      await uploadLog(
        'info',
        'ClientDailyActivity',
        'Client daily activity log summary',
        storeCode: storeCode,
        context: {
          ...summary.toContext(
            platform: Platform.operatingSystem,
            appVersion: packageInfo?.version,
            buildNumber: packageInfo?.buildNumber,
          ),
          'clientId': clientId,
        },
      );
      await prefs.setString(_sharedKey(_dailyUploadSuccessKey), targetDateKey);
      await prefs.setString(
        _sharedKey(_dailyUploadSuccessAtKey),
        DateTime.now().toIso8601String(),
      );
      await info(
        'AppLogger',
        'Daily activity log upload succeeded',
        context: {
          'logDate': targetDateKey,
          'storeCode': storeCode,
          'matchedLines': summary.matchedLines,
        },
      );
    } catch (error, stackTrace) {
      await warn(
        'AppLogger',
        'Daily activity log upload failed',
        context: {
          if (targetDateKey != null) 'logDate': targetDateKey,
          'storeCode': storeCode,
          'error': error.toString(),
          'stackTrace': stackTrace.toString().split('\n').take(6).join('\n'),
        },
      );
    } finally {
      _dailyUploadInFlight = false;
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
      'level': _sanitize(level),
      'source': _sanitize(source),
      'message': _sanitize(message),
      'environment': AppStorageKeys.environment,
      if (_clientId != null) 'clientId': _sanitize(_clientId!),
      if (context != null) 'context': _sanitizeJson(context),
    });
    if (kDebugMode) debugPrint(entry);
    final file = _logFile;
    if (file == null) return;
    try {
      await _runSerializedFileOperation(
        () => _withLogFileLock(() async {
          await file.writeAsString(
            '$entry\n',
            mode: FileMode.append,
            flush: false,
          );
          if (await file.length() > appLogMaxBytes) {
            await _normalizeAndTrimExistingLog();
          }
        }),
      );
    } catch (_) {
      // Local logging must never break user flows.
    }
  }

  Future<void> _normalizeAndTrimExistingLog() async {
    final file = _logFile;
    if (file == null) return;
    await compactAppLogFile(file);
  }

  Future<void> _runSerializedFileOperation(Future<void> Function() operation) {
    final next = _fileOperation.then((_) => operation());
    _fileOperation = next.catchError((Object _) {});
    return next;
  }

  Future<void> _withLogFileLock(Future<void> Function() operation) async {
    final file = _logFile;
    if (file == null) return;
    final lockFile = File('${file.path}.lock');
    final lockHandle = await lockFile.open(mode: FileMode.append);
    try {
      await lockHandle.lock(FileLock.exclusive);
      await operation();
    } finally {
      await lockHandle.unlock();
      await lockHandle.close();
    }
  }

  Future<String> _ensureClientId() async {
    final current = _clientId;
    if (current != null && current.isNotEmpty) return current;
    final prefs = await SharedPreferences.getInstance();
    var value = prefs.getString(_sharedKey(_clientIdPreferenceKey));
    if (value == null || value.isEmpty) {
      value = 'pc-${DateTime.now().microsecondsSinceEpoch}';
      await prefs.setString(_sharedKey(_clientIdPreferenceKey), value);
    }
    _clientId = value;
    if (_logFile == null) {
      await initialize(clientId: value);
    }
    return value;
  }

  Future<PackageInfo?> _packageInfoOrNull() async {
    try {
      return await PackageInfo.fromPlatform();
    } catch (_) {
      return null;
    }
  }

  Object? _sanitizeJson(Object? value) {
    return sanitizeLogValue(value);
  }

  String _sanitize(String value) {
    return sanitizeLogText(value, maxLength: 4000);
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
