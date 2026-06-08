import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/platform/app_platform_capabilities.dart';
import '../../../../core/network/api_exception.dart' as api;
import '../../../../core/platform/app_restart_service.dart';
import '../../../../core/storage/app_storage_keys.dart';
import '../../../auth/domain/entities/user.dart';
import '../../data/payment_speaker.dart';
import '../../data/repositories/payment_monitor_repository.dart';
import '../../domain/map_payment_transaction.dart';
import '../../domain/payment_notification.dart';

class PaymentSpeakerError {
  final String storeCode;
  final String notificationId;
  final int amount;
  final DateTime occurredAt;
  final String message;

  const PaymentSpeakerError({
    required this.storeCode,
    required this.notificationId,
    required this.amount,
    required this.occurredAt,
    required this.message,
  });
}

class PaymentMonitorProvider extends ChangeNotifier {
  static const _pollInterval = Duration(seconds: 5);
  static const _startupNotificationLookback = Duration(minutes: 15);
  static const _speakerEnabledPreferenceKey = 'payment_monitor_enabled';
  static const _clientIdPreferenceKey = 'payment_monitor_client_id';
  static const _maxAudioPlaybackAttempts = 3;
  static const _defaultPlaybackRetryDelay = Duration(seconds: 10);
  static const _pollBackoffSchedule = <Duration>[
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 40),
    Duration(minutes: 1),
  ];

  static String _sharedKey(String key) => AppStorageKeys.shared(key);

  final PaymentMonitorRepository _repository;
  final PaymentSpeaker _speaker;
  final AppRestartService _restartService;
  final Duration _playbackRetryDelay;
  final Set<String> _terminalNotificationIds = {};
  final List<MapPaymentTransaction> _latestTransactions = [];

  Timer? _timer;
  User? _user;
  String? _storeOverride;
  String? _clientId;
  DateTime? _notificationCheckpointAt;
  bool _isActive = false;
  bool _isLoading = false;
  String? _errorMessage;
  DateTime? _lastCheckedAt;
  DateTime _rangeStartDate = _todayInVietnam();
  DateTime _rangeEndDate = _todayInVietnam();
  int _pageIndex = 0;
  int _pageSize = 10;
  int _totalTransactions = 0;
  bool _loggedMonitorStarted = false;
  bool _isSpeakerEnabled = true;
  bool _isSpeakerPreferenceLoaded = false;
  int _pollFailureCount = 0;
  DateTime? _nextPollAllowedAt;
  PaymentSpeakerError? _speakerError;

  PaymentMonitorProvider(
    this._repository,
    this._speaker, [
    AppRestartService? restartService,
    Duration playbackRetryDelay = _defaultPlaybackRetryDelay,
  ]) : _restartService = restartService ?? AppRestartService(),
       _playbackRetryDelay = playbackRetryDelay {
    _loadEnabledPreference();
  }

  bool get isActive => _isActive;
  bool get isSpeakerEnabled => _isSpeakerEnabled;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime? get lastCheckedAt => _lastCheckedAt;
  String? get storeOverride => _storeOverride;
  DateTime get selectedDate => _rangeStartDate;
  DateTime get rangeStartDate => _rangeStartDate;
  DateTime get rangeEndDate => _rangeEndDate;
  int get pageIndex => _pageIndex;
  int get pageSize => _pageSize;
  int get totalTransactions => _totalTransactions;
  PaymentSpeakerError? get speakerError => _speakerError;
  bool get canGoPreviousPage => _pageIndex > 0;
  bool get canGoNextPage => (_pageIndex + 1) * _pageSize < _totalTransactions;
  bool get canMonitorOnThisDevice => _canMonitorOnThisDevice;
  bool get hasMonitorScope => _hasMonitorScope;
  List<MapPaymentTransaction> get latestTransactions =>
      List.unmodifiable(_latestTransactions);

  void syncAuth(User? user, {required bool isInitialized}) {
    _user = user;
    if (!_isSpeakerPreferenceLoaded) return;
    if (!isInitialized || user == null || !_canMonitorOnThisDevice) {
      _stop(reason: 'auth_or_device_unavailable');
      return;
    }
    _reconcile();
  }

  Future<void> setSpeakerEnabled(bool value) async {
    if (_isSpeakerEnabled == value) return;
    _isSpeakerEnabled = value;
    _isSpeakerPreferenceLoaded = true;
    _errorMessage = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sharedKey(_speakerEnabledPreferenceKey), value);
    await AppLogger.instance.info(
      'PaymentMonitor',
      value
          ? 'Payment notification speaker enabled'
          : 'Payment notification speaker muted',
      context: {
        'storeId': _requestStoreId ?? _user?.storeId,
        'hasScope': _hasMonitorScope,
        'syncActive': _isActive,
      },
    );

    _reconcile();
  }

  Future<void> restartApp() async {
    await AppLogger.instance.info(
      'PaymentMonitor',
      'Payment monitor restart requested from speaker error card',
      context: {
        'storeId': _requestStoreId ?? _user?.storeId,
        'notificationId': _speakerError?.notificationId,
      },
    );
    await _restartService.restart();
  }

  void setStoreOverride(String value) {
    final normalized = value.trim().toUpperCase();
    if (_storeOverride == normalized) return;
    _storeOverride = normalized.isEmpty ? null : normalized;
    _pageIndex = 0;
    _restart();
  }

  void setSelectedDate(DateTime value) {
    setDateRange(value, value);
  }

  void setDateRange(DateTime start, DateTime end) {
    var normalizedStart = _normalizeVietnamDate(start);
    var normalizedEnd = _normalizeVietnamDate(end);
    if (normalizedEnd.isBefore(normalizedStart)) {
      final swap = normalizedStart;
      normalizedStart = normalizedEnd;
      normalizedEnd = swap;
    }
    if (_isSameDate(_rangeStartDate, normalizedStart) &&
        _isSameDate(_rangeEndDate, normalizedEnd)) {
      return;
    }
    _rangeStartDate = normalizedStart;
    _rangeEndDate = normalizedEnd;
    _pageIndex = 0;
    unawaited(
      AppLogger.instance.info(
        'PaymentMonitor',
        'Payment monitor date range changed',
        context: {
          'storeId': _requestStoreId ?? _user?.storeId,
          'startDate': _formatDateForApi(_rangeStartDate),
          'endDate': _formatDateForApi(_rangeEndDate),
        },
      ),
    );
    _poll(force: true);
  }

  void setPageSize(int value) {
    if (_pageSize == value) return;
    _pageSize = value;
    _pageIndex = 0;
    unawaited(
      AppLogger.instance.info(
        'PaymentMonitor',
        'Payment monitor page size changed',
        context: {
          'storeId': _requestStoreId ?? _user?.storeId,
          'limit': _pageSize,
        },
      ),
    );
    _poll(force: true);
  }

  void nextPage() {
    if (!canGoNextPage) return;
    _pageIndex += 1;
    unawaited(_logPageChanged('next'));
    _poll(force: true);
  }

  void previousPage() {
    if (!canGoPreviousPage) return;
    _pageIndex -= 1;
    unawaited(_logPageChanged('previous'));
    _poll(force: true);
  }

  Future<void> _loadEnabledPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_sharedKey(_speakerEnabledPreferenceKey));
      _isSpeakerEnabled = enabled ?? true;
      _isSpeakerPreferenceLoaded = true;
      _reconcile();
      notifyListeners();
    } catch (error, stackTrace) {
      await AppLogger.instance.warn(
        'PaymentMonitor',
        'Payment monitor preference load failed',
        context: {
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        },
      );
    }
  }

  bool get _canMonitorOnThisDevice =>
      AppPlatformCapabilities.isPaymentMonitorSupported();

  bool get _hasMonitorScope {
    final user = _user;
    if (user == null) return false;
    if (user.role == 'SUPER_ADMIN') return _storeOverride?.isNotEmpty == true;
    return user.storeId?.isNotEmpty == true;
  }

  String? get _requestStoreId {
    final user = _user;
    if (user?.role == 'SUPER_ADMIN') return _storeOverride;
    return null;
  }

  void _reconcile() {
    if (!_canMonitorOnThisDevice) {
      _stop(reason: 'unsupported_device');
      return;
    }
    if (!_hasMonitorScope) {
      _stop(reason: 'missing_scope');
      return;
    }
    if (_isActive) return;
    _isActive = true;
    _notificationCheckpointAt = DateTime.now().toUtc().subtract(
      _startupNotificationLookback,
    );
    _loggedMonitorStarted = false;
    _terminalNotificationIds.clear();
    _speakerError = null;
    _latestTransactions.clear();
    _poll(force: true);
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
    notifyListeners();
  }

  void _restart() {
    _stop(reason: 'restart');
    _reconcile();
  }

  void _stop({required String reason, bool clearError = true}) {
    _timer?.cancel();
    _timer = null;
    if (!_isActive &&
        !_isLoading &&
        _latestTransactions.isEmpty &&
        _errorMessage == null &&
        _speakerError == null) {
      return;
    }
    _isActive = false;
    _isLoading = false;
    _notificationCheckpointAt = null;
    _loggedMonitorStarted = false;
    _pollFailureCount = 0;
    _nextPollAllowedAt = null;
    _terminalNotificationIds.clear();
    _latestTransactions.clear();
    if (clearError) _errorMessage = null;
    _speakerError = null;
    AppLogger.instance.info(
      'PaymentMonitor',
      'Payment monitor stopped',
      context: {'reason': reason, 'storeId': _requestStoreId ?? _user?.storeId},
    );
    notifyListeners();
  }

  Future<void> _poll({bool force = false}) async {
    if (_isLoading || !_canMonitorOnThisDevice || !_hasMonitorScope) return;
    final nextPollAllowedAt = _nextPollAllowedAt;
    if (!force && nextPollAllowedAt != null) {
      final now = DateTime.now();
      if (now.isBefore(nextPollAllowedAt)) return;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    var phase = 'client_id';
    try {
      final clientId = await _ensureClientId();
      if (!_loggedMonitorStarted) {
        _loggedMonitorStarted = true;
        await AppLogger.instance.info(
          'PaymentMonitor',
          'Payment monitor started',
          context: {
            'storeId': _requestStoreId ?? _user?.storeId,
            'checkpointAt': _notificationCheckpointAt?.toIso8601String(),
          },
        );
      }
      phase = 'stored_transactions';
      final transactionPage = await _repository.fetchStoredTransactions(
        storeId: _requestStoreId,
        startDate: _formatDateForApi(_rangeStartDate),
        endDate: _formatDateForApi(_rangeEndDate),
        page: _pageIndex,
        limit: _pageSize,
      );
      phase = 'ready_notifications';
      final notifications = await _repository.fetchReadyNotifications(
        clientId: clientId,
        storeId: _requestStoreId,
        afterCreatedAt: _notificationCheckpointAt,
        limit: 3,
      );
      if (notifications.isNotEmpty) {
        await AppLogger.instance.info(
          'PaymentMonitor',
          'Payment notifications fetched',
          context: {
            'count': notifications.length,
            'notificationIds': notifications
                .map((notification) => notification.notificationId)
                .toList(),
          },
        );
        await AppLogger.instance.uploadLog(
          'info',
          'PaymentMonitor',
          'Payment notifications fetched',
          context: {'count': notifications.length},
          storeCode: _requestStoreId,
        );
      }
      phase = 'playback';
      await _handleReadyNotifications(notifications, clientId);

      _lastCheckedAt = DateTime.now();
      _pollFailureCount = 0;
      _nextPollAllowedAt = null;
      _pageIndex = transactionPage.page;
      _pageSize = transactionPage.limit;
      _totalTransactions = transactionPage.total;
      _latestTransactions
        ..clear()
        ..addAll(transactionPage.transactions);
    } catch (error) {
      final pollError = _classifyPollError(error);
      final failureCount = _pollFailureCount + 1;
      _pollFailureCount = failureCount;
      final nextRetryAt = pollError.isAuthFailure
          ? null
          : DateTime.now().add(_pollBackoffForFailure(failureCount));
      _nextPollAllowedAt = nextRetryAt;
      _errorMessage = pollError.message;
      await AppLogger.instance.error(
        'PaymentMonitor',
        'Payment monitor poll failed',
        error: error,
        upload: true,
        context: {
          'storeId': _requestStoreId ?? _user?.storeId,
          'phase': phase,
          'errorType': pollError.errorType,
          if (pollError.statusCode != null) 'statusCode': pollError.statusCode,
          'failureCount': failureCount,
          'authFailure': pollError.isAuthFailure,
          if (nextRetryAt != null) 'nextRetryAt': nextRetryAt.toIso8601String(),
          'startDate': _formatDateForApi(_rangeStartDate),
          'endDate': _formatDateForApi(_rangeEndDate),
          'page': _pageIndex,
          'limit': _pageSize,
        },
      );
      if (pollError.isAuthFailure) {
        _stop(reason: 'auth_failed', clearError: false);
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<String> _ensureClientId() async {
    if (_clientId != null) return _clientId!;
    final prefs = await SharedPreferences.getInstance();
    var value = prefs.getString(_sharedKey(_clientIdPreferenceKey));
    if (value == null || value.isEmpty) {
      value = 'pc-${DateTime.now().microsecondsSinceEpoch}';
      await prefs.setString(_sharedKey(_clientIdPreferenceKey), value);
    }
    _clientId = value;
    await AppLogger.instance.initialize(clientId: value);
    return value;
  }

  Future<void> _handleReadyNotifications(
    List<PaymentNotification> notifications,
    String clientId,
  ) async {
    if (notifications.isEmpty) return;
    if (!_isSpeakerEnabled) {
      await _silenceReadyNotifications(notifications, clientId);
      return;
    }
    await _playReadyNotifications(notifications, clientId);
  }

  Future<void> _silenceReadyNotifications(
    List<PaymentNotification> notifications,
    String clientId,
  ) async {
    final storeCode = _requestStoreId ?? _user?.storeId;
    await AppLogger.instance.info(
      'PaymentMonitor',
      'Payment notifications silenced while transaction sync remains active',
      context: {
        'count': notifications.length,
        'clientId': clientId,
        'storeCode': storeCode,
        'notificationIds': notifications
            .map((notification) => notification.notificationId)
            .toList(),
      },
    );

    for (final notification in notifications) {
      if (_terminalNotificationIds.contains(notification.notificationId)) {
        continue;
      }
      await _acknowledgeNotificationEvent(
        notificationId: notification.notificationId,
        clientId: clientId,
        event: 'SILENCED',
      );
      _setTerminalNotification(notification.notificationId);
    }
  }

  Future<void> _playReadyNotifications(
    List<PaymentNotification> notifications,
    String clientId,
  ) async {
    final storeCode = _requestStoreId ?? _user?.storeId;
    await AppLogger.instance.info(
      'PaymentMonitor',
      'Payment notification play loop started',
      context: {
        'count': notifications.length,
        'clientId': clientId,
        'storeCode': storeCode,
        'notificationIds': notifications
            .map((notification) => notification.notificationId)
            .toList(),
      },
    );
    await AppLogger.instance.uploadLog(
      'info',
      'PaymentMonitor',
      'Payment notification play loop started',
      context: {'count': notifications.length},
      storeCode: storeCode,
    );

    for (final notification in notifications) {
      if (_terminalNotificationIds.contains(notification.notificationId)) {
        await AppLogger.instance.warn(
          'PaymentMonitor',
          'Payment notification skipped as already terminal locally',
          context: {
            'notificationId': notification.notificationId,
            'transactionId': notification.transactionId,
            'storeCode': notification.storeCode,
          },
        );
        continue;
      }
      try {
        await _playNotificationWithRetry(notification, clientId);
        await AppLogger.instance.info(
          'PaymentMonitor',
          'Acknowledging payment notification played',
          context: {'notificationId': notification.notificationId},
        );
        await _acknowledgeNotificationEvent(
          notificationId: notification.notificationId,
          clientId: clientId,
          event: 'PLAYED',
        );
        _setTerminalNotification(notification.notificationId);
        _speakerError = null;
        await AppLogger.instance.info(
          'PaymentMonitor',
          'Payment notification audio played',
          context: {
            'notificationId': notification.notificationId,
            'transactionId': notification.transactionId,
            'storeCode': notification.storeCode,
            'amount': notification.amount,
          },
        );
        await AppLogger.instance.uploadLog(
          'info',
          'PaymentMonitor',
          'Payment notification audio played',
          context: {
            'notificationId': notification.notificationId,
            'transactionId': notification.transactionId,
            'amount': notification.amount,
          },
          storeCode: notification.storeCode,
        );
        await Future<void>.delayed(const Duration(milliseconds: 250));
      } catch (error) {
        final safeError = _safeSpeakerError(error);
        _speakerError = PaymentSpeakerError(
          storeCode: notification.storeCode,
          notificationId: notification.notificationId,
          amount: notification.amount,
          occurredAt: DateTime.now(),
          message: _buildSpeakerErrorMessage(safeError),
        );
        notifyListeners();
      }
    }
  }

  Future<void> _playNotificationWithRetry(
    PaymentNotification notification,
    String clientId,
  ) async {
    if (notification.audioStatus != 'READY') {
      throw StateError(
        'Server audio is not ready: ${notification.audioStatus}',
      );
    }

    final audioBytes = await _downloadNotificationAudio(notification);
    for (var attempt = 1; attempt <= _maxAudioPlaybackAttempts; attempt += 1) {
      try {
        final startedAt = DateTime.now();
        await AppLogger.instance.info(
          'PaymentSpeaker',
          'Payment speaker playback started',
          context: {
            'notificationId': notification.notificationId,
            'transactionId': notification.transactionId,
            'storeCode': notification.storeCode,
            'clientId': clientId,
            'amount': notification.amount,
            'attempt': attempt,
            'bytes': audioBytes.length,
          },
        );
        await AppLogger.instance.uploadLog(
          'info',
          'PaymentSpeaker',
          'Payment speaker playback started',
          context: {
            'notificationId': notification.notificationId,
            'transactionId': notification.transactionId,
            'clientId': clientId,
            'amount': notification.amount,
            'attempt': attempt,
            'bytes': audioBytes.length,
          },
          storeCode: notification.storeCode,
        );
        final result = await _playNotificationOnce(
          notification: notification,
          clientId: clientId,
          attempt: attempt,
          audioBytes: audioBytes,
        );
        await AppLogger.instance.info(
          'PaymentSpeaker',
          'Payment speaker playback succeeded',
          context: {
            'notificationId': notification.notificationId,
            'transactionId': notification.transactionId,
            'storeCode': notification.storeCode,
            'clientId': clientId,
            'amount': notification.amount,
            'attempt': attempt,
            'backend': result.backend,
            'extension': result.extension,
            'durationMs': result.durationMs,
            'reportedSuccess': result.reportedSuccess,
            'audibleVerified': result.audibleVerified,
            'normalized': result.normalized,
            if (result.sampleRateHz != null)
              'sampleRateHz': result.sampleRateHz,
            if (result.channels != null) 'channels': result.channels,
            if (result.bitsPerSample != null)
              'bitsPerSample': result.bitsPerSample,
            if (result.audioPreflightStatus != null)
              'audioPreflightStatus': result.audioPreflightStatus,
            'startedAt': startedAt.toIso8601String(),
          },
        );
        await AppLogger.instance.uploadLog(
          'info',
          'PaymentSpeaker',
          'Payment speaker playback succeeded',
          context: {
            'notificationId': notification.notificationId,
            'transactionId': notification.transactionId,
            'clientId': clientId,
            'amount': notification.amount,
            'attempt': attempt,
            'backend': result.backend,
            'extension': result.extension,
            'durationMs': result.durationMs,
            'reportedSuccess': result.reportedSuccess,
            'audibleVerified': result.audibleVerified,
            'normalized': result.normalized,
            if (result.sampleRateHz != null)
              'sampleRateHz': result.sampleRateHz,
            if (result.channels != null) 'channels': result.channels,
            if (result.bitsPerSample != null)
              'bitsPerSample': result.bitsPerSample,
            if (result.audioPreflightStatus != null)
              'audioPreflightStatus': result.audioPreflightStatus,
            'startedAt': startedAt.toIso8601String(),
          },
          storeCode: notification.storeCode,
        );
        return;
      } catch (error, stackTrace) {
        final safeError = _safeSpeakerError(error);
        final retryable = error is! PaymentSpeakerException || error.retryable;
        final isFinalAttempt =
            attempt >= _maxAudioPlaybackAttempts || !retryable;
        final nextRetryAt = isFinalAttempt
            ? null
            : DateTime.now().add(_playbackRetryDelay);
        final failureContext = {
          'notificationId': notification.notificationId,
          'transactionId': notification.transactionId,
          'storeCode': notification.storeCode,
          'clientId': clientId,
          'amount': notification.amount,
          'attempt': attempt,
          'attempts': _maxAudioPlaybackAttempts,
          'final': isFinalAttempt,
          'retryable': retryable,
          'error': safeError,
          if (nextRetryAt != null) 'nextRetryAt': nextRetryAt.toIso8601String(),
          if (error is PaymentSpeakerException &&
              error.backendErrors.isNotEmpty)
            'backendErrors': error.backendErrors,
        };
        await AppLogger.instance.error(
          'PaymentSpeaker',
          'Payment speaker playback failed',
          error: error,
          stackTrace: stackTrace,
          context: failureContext,
        );
        await AppLogger.instance.uploadLog(
          'error',
          'PaymentSpeaker',
          'Payment speaker playback failed',
          context: failureContext,
          storeCode: notification.storeCode,
        );

        if (isFinalAttempt) {
          await _acknowledgeNotificationEvent(
            notificationId: notification.notificationId,
            clientId: clientId,
            event: 'FAILED',
            error: safeError,
          );
          _setTerminalNotification(notification.notificationId);
          Error.throwWithStackTrace(error, stackTrace);
        }

        await _acknowledgeNotificationEvent(
          notificationId: notification.notificationId,
          clientId: clientId,
          event: 'PLAYBACK_FAILED',
          error: safeError,
        );
        await Future<void>.delayed(_playbackRetryDelay);
      }
    }
  }

  Future<List<int>> _downloadNotificationAudio(
    PaymentNotification notification,
  ) async {
    await AppLogger.instance.info(
      'PaymentMonitor',
      'Downloading payment notification audio',
      context: {
        'notificationId': notification.notificationId,
        'transactionId': notification.transactionId,
        'storeCode': notification.storeCode,
        'amount': notification.amount,
      },
    );
    final audioBytes = await _repository.downloadNotificationAudio(
      notification.notificationId,
    );
    if (audioBytes.isEmpty) {
      throw StateError('Server audio is empty');
    }
    await AppLogger.instance.info(
      'PaymentMonitor',
      'Payment notification audio downloaded',
      context: {
        'notificationId': notification.notificationId,
        'bytes': audioBytes.length,
      },
    );
    await AppLogger.instance.uploadLog(
      'info',
      'PaymentMonitor',
      'Payment notification audio downloaded',
      context: {
        'notificationId': notification.notificationId,
        'bytes': audioBytes.length,
      },
      storeCode: notification.storeCode,
    );
    return audioBytes;
  }

  Future<PaymentSpeakerResult> _playNotificationOnce({
    required PaymentNotification notification,
    required String clientId,
    required int attempt,
    required List<int> audioBytes,
  }) async {
    return _speaker.playServerAudio(
      amount: notification.amount,
      audioBytes: audioBytes,
      notificationId: notification.notificationId,
      transactionId: notification.transactionId,
      storeCode: notification.storeCode,
      clientId: clientId,
      attempt: attempt,
    );
  }

  Future<bool> _acknowledgeNotificationEvent({
    required String notificationId,
    required String clientId,
    required String event,
    String? error,
  }) async {
    try {
      await _repository.acknowledgeNotification(
        notificationId: notificationId,
        clientId: clientId,
        event: event,
        error: error,
      );
      return true;
    } catch (ackError, stackTrace) {
      await AppLogger.instance.error(
        'PaymentMonitor',
        'Payment notification acknowledgement failed',
        error: ackError,
        stackTrace: stackTrace,
        upload: true,
        context: {'notificationId': notificationId, 'event': event},
      );
      return false;
    }
  }

  void _setTerminalNotification(String notificationId) {
    _terminalNotificationIds.add(notificationId);
  }

  String _buildSpeakerErrorMessage(String safeError) {
    final lower = safeError.toLowerCase();
    if (lower.contains('audio output device') ||
        lower.contains('waveoutdevices=0') ||
        lower.contains('no wave device')) {
      return 'Windows không nhận thiết bị âm thanh. Kiểm tra loa/audio driver rồi bấm Khởi động lại app. Lỗi: $safeError';
    }
    return 'Không phát được loa sau $_maxAudioPlaybackAttempts lần thử. '
        'Bấm Khởi động lại app rồi thử lại. Lỗi: $safeError';
  }

  static DateTime _todayInVietnam() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime _normalizeVietnamDate(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  Future<void> _logPageChanged(String direction) {
    return AppLogger.instance.info(
      'PaymentMonitor',
      'Payment monitor page changed',
      context: {
        'storeId': _requestStoreId ?? _user?.storeId,
        'direction': direction,
        'page': _pageIndex,
        'limit': _pageSize,
        'startDate': _formatDateForApi(_rangeStartDate),
        'endDate': _formatDateForApi(_rangeEndDate),
      },
    );
  }

  static bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _formatDateForApi(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  static String _safeSpeakerError(Object error) {
    final normalized = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 180) return normalized;
    return '${normalized.substring(0, 177)}...';
  }

  static _PaymentPollError _classifyPollError(Object error) {
    final statusCode = error is api.ApiException ? error.statusCode : null;
    final rawMessage = error is api.ApiException
        ? error.message
        : error.toString();
    final message = rawMessage.trim();
    final lower = message.toLowerCase();
    final authFailure =
        statusCode == 401 ||
        statusCode == 403 ||
        lower.contains('unauthorized') ||
        lower.contains('phiên làm việc') ||
        lower.contains('dang nhap tren thiet bi khac') ||
        lower.contains('đăng nhập trên thiết bị khác');

    if (authFailure) {
      return _PaymentPollError(
        message: message.isNotEmpty
            ? message
            : 'Phiên làm việc đã hết hạn. Vui lòng đăng nhập lại.',
        errorType: error.runtimeType.toString(),
        statusCode: statusCode,
        isAuthFailure: true,
      );
    }
    if (error is api.NetworkException) {
      return _PaymentPollError(
        message: error.message,
        errorType: error.runtimeType.toString(),
        statusCode: statusCode,
      );
    }
    if (error is api.TimeoutException) {
      return _PaymentPollError(
        message: error.message,
        errorType: error.runtimeType.toString(),
        statusCode: statusCode,
      );
    }
    if (error is api.ServerException) {
      return _PaymentPollError(
        message: error.message,
        errorType: error.runtimeType.toString(),
        statusCode: statusCode,
      );
    }
    if (error is api.ApiException && message.isNotEmpty) {
      return _PaymentPollError(
        message: message,
        errorType: error.runtimeType.toString(),
        statusCode: statusCode,
      );
    }
    return _PaymentPollError(
      message: 'Chưa cập nhật được giao dịch. Vui lòng thử lại sau ít phút.',
      errorType: error.runtimeType.toString(),
      statusCode: statusCode,
    );
  }

  static Duration _pollBackoffForFailure(int failureCount) {
    final index = (failureCount - 1).clamp(0, _pollBackoffSchedule.length - 1);
    return _pollBackoffSchedule[index];
  }
}

class _PaymentPollError {
  final String message;
  final String errorType;
  final int? statusCode;
  final bool isAuthFailure;

  const _PaymentPollError({
    required this.message,
    required this.errorType,
    this.statusCode,
    this.isAuthFailure = false,
  });
}
