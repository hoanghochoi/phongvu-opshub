import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/platform/app_platform_capabilities.dart';
import '../../../../core/network/api_exception.dart' as api;
import '../../../../core/platform/app_restart_service.dart';
import '../../../../core/storage/app_storage_keys.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../bank_statement/domain/bank_statement_transaction.dart';
import '../../../bank_statement/domain/order_code_parser.dart';
import '../../data/payment_speaker.dart';
import '../../data/repositories/payment_monitor_repository.dart';
import '../../domain/map_payment_transaction.dart';
import '../../domain/payment_notification.dart';
import '../../domain/payment_poll_policy.dart';

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

class PaymentMonitorRowMessage {
  final String text;
  final bool success;

  const PaymentMonitorRowMessage({required this.text, required this.success});
}

class _DownloadedPaymentAudio {
  final List<int> bytes;
  final bool playLocalCue;
  final bool playLocalCuePrefix;
  final String mode;

  const _DownloadedPaymentAudio({
    required this.bytes,
    required this.playLocalCue,
    required this.playLocalCuePrefix,
    required this.mode,
  });
}

typedef PaymentRealtimeConnector = WebSocketChannel Function(Uri uri);

class PaymentMonitorProvider extends ChangeNotifier {
  static const _fallbackRefreshInterval = Duration(seconds: 30);
  static const _realtimeRefreshDebounce = Duration(milliseconds: 500);
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
  final PaymentRealtimeConnector _realtimeConnector;
  final Set<String> _terminalNotificationIds = {};
  final Set<String> _queuedStreamNotificationIds = {};
  final Queue<PaymentNotification> _streamNotificationQueue =
      Queue<PaymentNotification>();
  final List<MapPaymentTransaction> _latestTransactions = [];
  final Map<String, PaymentMonitorRowMessage> _rowMessages = {};
  final Map<String, Timer> _rowMessageTimers = {};

  Timer? _timer;
  Timer? _realtimeRefreshTimer;
  StreamSubscription<dynamic>? _realtimeSubscription;
  WebSocketChannel? _realtimeChannel;
  User? _user;
  String? _storeOverride;
  final Set<String> _selectedStoreIds = {};
  String? _clientId;
  String? _realtimeKey;
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
  String? _lastSpeakerEligibilityLogKey;
  bool _refreshQueuedWhileLoading = false;
  bool _queuedRefreshIncludeTotal = false;
  bool _isDrainingStreamNotifications = false;
  bool _canReviewOrderTransfers = false;

  PaymentMonitorProvider(
    this._repository,
    this._speaker, [
    AppRestartService? restartService,
    Duration playbackRetryDelay = _defaultPlaybackRetryDelay,
    PaymentRealtimeConnector? realtimeConnector,
  ]) : _restartService = restartService ?? AppRestartService(),
       _playbackRetryDelay = playbackRetryDelay,
       _realtimeConnector =
           realtimeConnector ?? ((uri) => WebSocketChannel.connect(uri)) {
    _loadEnabledPreference();
  }

  bool get isActive => _isActive;
  bool get isSpeakerEnabled => _isSpeakerEnabled;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime? get lastCheckedAt => _lastCheckedAt;
  String? get storeOverride => _storeOverride;
  Set<String> get selectedStoreIds => Set.unmodifiable(_selectedStoreIds);
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
  bool get canUsePaymentSpeaker => _canUsePaymentSpeaker;
  bool get canReviewOrderTransfers => _canReviewOrderTransfers;
  Map<String, PaymentMonitorRowMessage> get rowMessages =>
      Map.unmodifiable(_rowMessages);
  bool get isViewingMultipleStores => _effectiveListStoreIds.length > 1;
  String? get speakerSelectionNotice {
    if (!_canMonitorOnThisDevice ||
        !_canUseSpeakerOnThisDevice ||
        !_userCanUsePaymentSpeakerFeature(_user)) {
      return null;
    }
    final storeIds = _effectiveListStoreIds;
    if (storeIds.length > 1) {
      return 'Loa chỉ đọc khi chọn đúng 1 SR. Bạn đang xem ${storeIds.length} SR nên danh sách vẫn cập nhật, còn loa tạm dừng.';
    }
    if (storeIds.isEmpty) {
      return 'Chọn 1 SR để bật đọc loa tiền vào.';
    }
    return null;
  }

  List<MapPaymentTransaction> get latestTransactions =>
      List.unmodifiable(_latestTransactions);

  void syncAuth(User? user, {required bool isInitialized}) {
    final previousUserKey = _userSessionKey(_user);
    final nextUserKey = _userSessionKey(user);
    _user = user;
    if (previousUserKey != nextUserKey) {
      _lastSpeakerEligibilityLogKey = null;
      _latestTransactions.clear();
      _canReviewOrderTransfers = false;
      _clearRowMessages(notify: false);
      _selectedStoreIds.clear();
      _storeOverride = _defaultActiveStoreIdFor(user);
    }
    if (!_isSpeakerPreferenceLoaded) return;
    if (!isInitialized || user == null || !_canMonitorOnThisDevice) {
      _stop(reason: 'auth_or_device_unavailable');
      return;
    }
    _reconcile();
  }

  Future<void> setSpeakerEnabled(bool value) async {
    if (!_canUsePaymentSpeaker) {
      final reason = _speakerEligibilityReason();
      await AppLogger.instance.info(
        'PaymentMonitor',
        'Payment speaker preference change ignored',
        context: {
          'storeId': _requestStoreId ?? _user?.storeId,
          'reason': reason,
          'hasPaymentSpeakerFeature': _userCanUsePaymentSpeakerFeature(_user),
          'supportsPaymentMonitor': _canMonitorOnThisDevice,
          'supportsPaymentSpeaker': _canUseSpeakerOnThisDevice,
          'speakerEligible': false,
        },
      );
      return;
    }
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

  Future<void> refreshNow() async {
    await AppLogger.instance.info(
      'PaymentMonitor',
      'Payment monitor manual refresh requested',
      context: {
        'storeId': _requestStoreId ?? _user?.storeId,
        'page': _pageIndex,
        'limit': _pageSize,
      },
    );
    await _poll(
      force: true,
      bypassBackoff: true,
      includeTotal: true,
      reason: 'manual_refresh',
    );
  }

  void setStoreOverride(String value) {
    final normalized = value.trim().toUpperCase();
    if (_storeOverride == normalized) return;
    _storeOverride = normalized.isEmpty ? null : normalized;
    _selectedStoreIds
      ..clear()
      ..addAll([if (_storeOverride?.isNotEmpty == true) _storeOverride!]);
    _pageIndex = 0;
    _restart();
  }

  void setSelectedStoreIds(Set<String> values) {
    final normalized = values
        .map((value) => value.trim().toUpperCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (setEquals(_selectedStoreIds, normalized)) return;
    _selectedStoreIds
      ..clear()
      ..addAll(normalized);
    _storeOverride = normalized.length == 1 ? normalized.first : null;
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
    _poll(
      force: true,
      bypassBackoff: true,
      includeTotal: true,
      reason: 'date_range',
    );
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
    _poll(
      force: true,
      bypassBackoff: true,
      includeTotal: true,
      reason: 'page_size',
    );
  }

  void nextPage() {
    if (!canGoNextPage) return;
    _pageIndex += 1;
    unawaited(_logPageChanged('next'));
    _poll(
      force: true,
      bypassBackoff: true,
      includeTotal: true,
      reason: 'next_page',
    );
  }

  void previousPage() {
    if (!canGoPreviousPage) return;
    _pageIndex -= 1;
    unawaited(_logPageChanged('previous'));
    _poll(
      force: true,
      bypassBackoff: true,
      includeTotal: true,
      reason: 'previous_page',
    );
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

  bool get _canUseSpeakerOnThisDevice =>
      AppPlatformCapabilities.isPaymentSpeakerSupported();

  bool get _canUsePaymentSpeaker {
    return _canUseSpeakerOnThisDevice &&
        _userCanUsePaymentSpeakerFeature(_user) &&
        (_requestStoreId?.isNotEmpty == true);
  }

  bool get _hasMonitorScope {
    final user = _user;
    if (user == null) return false;
    if (user.isSuperAdmin) return _storeOverride?.isNotEmpty == true;
    return _assignedStoreIdsFor(user).isNotEmpty;
  }

  String? get _requestStoreId {
    final user = _user;
    if (user?.isSuperAdmin == true) return _storeOverride;
    return _storeOverride ?? _defaultActiveStoreIdFor(user);
  }

  String? get _listStoreIdsParam {
    final selected = _effectiveListStoreIds;
    if (selected.isEmpty) return null;
    return selected.join(',');
  }

  List<String> get _effectiveListStoreIds {
    final user = _user;
    if (user == null) return const [];
    if (user.isSuperAdmin) {
      final override = _storeOverride?.trim().toUpperCase();
      return override?.isNotEmpty == true ? [override!] : const [];
    }
    final selected = (_selectedStoreIds.isNotEmpty
        ? _selectedStoreIds
        : _assignedStoreIdsFor(user).toSet());
    if (selected.isEmpty) return const [];
    final normalized = selected
        .map((value) => value.trim().toUpperCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    normalized.sort();
    return normalized;
  }

  static bool _userCanUsePaymentSpeakerFeature(User? user) {
    return user?.canUseFeature('PAYMENT_SPEAKER') == true;
  }

  String _speakerEligibilityReason() {
    if (!_canMonitorOnThisDevice) return 'unsupported_platform';
    if (!_canUseSpeakerOnThisDevice) return 'unsupported_speaker_platform';
    if (!_userCanUsePaymentSpeakerFeature(_user)) {
      return 'missing_speaker_feature';
    }
    if (_effectiveListStoreIds.length > 1) return 'multiple_stores_selected';
    if (_requestStoreId?.isNotEmpty != true) return 'store_not_selected';
    return 'eligible';
  }

  static String? _userSessionKey(User? user) {
    if (user == null) return null;
    return [
      user.id ?? user.email,
      user.assignedStoreIds.join(','),
      user.role ?? '',
      _userCanUsePaymentSpeakerFeature(user).toString(),
    ].join('|');
  }

  void _logSpeakerEligibility({
    required bool eligible,
    required String reason,
  }) {
    final storeId = _requestStoreId ?? _user?.storeId;
    final hasPaymentSpeakerFeature = _userCanUsePaymentSpeakerFeature(_user);
    final key = [
      eligible,
      reason,
      _user?.id ?? _user?.email ?? '',
      storeId ?? '',
      hasPaymentSpeakerFeature,
      _canMonitorOnThisDevice,
      _canUseSpeakerOnThisDevice,
    ].join('|');
    if (_lastSpeakerEligibilityLogKey == key) return;
    _lastSpeakerEligibilityLogKey = key;
    unawaited(
      AppLogger.instance.info(
        'PaymentMonitor',
        eligible
            ? 'Payment speaker realtime eligible'
            : 'Payment speaker audio skipped',
        context: {
          'speakerEligible': eligible,
          'reason': reason,
          'storeId': storeId,
          'hasScope': _hasMonitorScope,
          'hasPaymentSpeakerFeature': hasPaymentSpeakerFeature,
          'supportsPaymentMonitor': _canMonitorOnThisDevice,
          'supportsPaymentSpeaker': _canUseSpeakerOnThisDevice,
          'listOnly': !eligible,
        },
      ),
    );
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
    final speakerEligible = _canUsePaymentSpeaker;
    _logSpeakerEligibility(
      eligible: speakerEligible,
      reason: _speakerEligibilityReason(),
    );
    _connectRealtime();
    if (_isActive) return;
    _isActive = true;
    _notificationCheckpointAt = speakerEligible
        ? DateTime.now().toUtc().subtract(_startupNotificationLookback)
        : null;
    _loggedMonitorStarted = false;
    _terminalNotificationIds.clear();
    _queuedStreamNotificationIds.clear();
    _streamNotificationQueue.clear();
    _isDrainingStreamNotifications = false;
    _speakerError = null;
    _latestTransactions.clear();
    _poll(force: true, includeTotal: true, reason: 'initial_load');
    _timer = Timer.periodic(
      _fallbackRefreshInterval,
      (_) => _poll(includeTotal: false, reason: 'fallback'),
    );
    notifyListeners();
  }

  void _restart() {
    _stop(reason: 'restart');
    _reconcile();
  }

  void _stop({required String reason, bool clearError = true}) {
    final hadConnection =
        _timer != null ||
        _realtimeRefreshTimer != null ||
        _realtimeChannel != null ||
        _realtimeKey != null;
    _timer?.cancel();
    _timer = null;
    _realtimeRefreshTimer?.cancel();
    _realtimeRefreshTimer = null;
    _disconnectRealtime(reason);
    if (!_isActive &&
        !_isLoading &&
        _latestTransactions.isEmpty &&
        _errorMessage == null &&
        _speakerError == null &&
        !hadConnection) {
      return;
    }
    _isActive = false;
    _isLoading = false;
    _notificationCheckpointAt = null;
    _loggedMonitorStarted = false;
    _pollFailureCount = 0;
    _nextPollAllowedAt = null;
    _lastSpeakerEligibilityLogKey = null;
    _refreshQueuedWhileLoading = false;
    _queuedRefreshIncludeTotal = false;
    _terminalNotificationIds.clear();
    _queuedStreamNotificationIds.clear();
    _streamNotificationQueue.clear();
    _isDrainingStreamNotifications = false;
    _latestTransactions.clear();
    _canReviewOrderTransfers = false;
    _clearRowMessages(notify: false);
    if (clearError) _errorMessage = null;
    _speakerError = null;
    AppLogger.instance.info(
      'PaymentMonitor',
      'Payment monitor stopped',
      context: {'reason': reason, 'storeId': _requestStoreId ?? _user?.storeId},
    );
    notifyListeners();
  }

  void _connectRealtime() {
    final user = _user;
    if (user == null || !_hasMonitorScope) {
      _disconnectRealtime('missing_scope');
      return;
    }
    final token = ApiClient().authToken;
    if (token == null || token.trim().isEmpty) {
      _disconnectRealtime('missing_token');
      return;
    }
    final storeCode = _requestStoreId;
    if (storeCode == null || storeCode.trim().isEmpty) {
      _disconnectRealtime('store_not_selected');
      return;
    }
    final nextKey = [user.id ?? user.email, storeCode, token].join('|');
    if (_realtimeKey == nextKey && _realtimeChannel != null) return;
    _disconnectRealtime('reconnect');

    final url = ApiConstants.realtimeWsUrl(
      storeId: storeCode,
      accessToken: token,
    );
    try {
      final channel = _realtimeConnector(Uri.parse(url));
      _realtimeChannel = channel;
      _realtimeKey = nextKey;
      _realtimeSubscription = channel.stream.listen(
        _handleRealtimeMessage,
        onError: (Object error, StackTrace stackTrace) {
          unawaited(
            AppLogger.instance.error(
              'PaymentMonitorRealtime',
              'Payment monitor realtime error',
              error: error,
              stackTrace: stackTrace,
              context: {'storeId': storeCode},
            ),
          );
        },
        onDone: () {
          unawaited(
            AppLogger.instance.info(
              'PaymentMonitorRealtime',
              'Payment monitor realtime disconnected',
              context: {'storeId': storeCode},
            ),
          );
          _realtimeSubscription = null;
          _realtimeChannel = null;
          _realtimeKey = null;
        },
      );
      unawaited(
        AppLogger.instance.info(
          'PaymentMonitorRealtime',
          'Payment monitor realtime connected',
          context: {'storeId': storeCode},
        ),
      );
    } catch (error, stackTrace) {
      unawaited(
        AppLogger.instance.error(
          'PaymentMonitorRealtime',
          'Payment monitor realtime connect failed',
          error: error,
          stackTrace: stackTrace,
          context: {'storeId': storeCode},
        ),
      );
      _disconnectRealtime('connect_failed');
    }
  }

  void _disconnectRealtime(String reason) {
    final hadConnection = _realtimeChannel != null || _realtimeKey != null;
    unawaited(_realtimeSubscription?.cancel());
    _realtimeSubscription = null;
    unawaited(_realtimeChannel?.sink.close());
    _realtimeChannel = null;
    _realtimeKey = null;
    if (hadConnection) {
      unawaited(
        AppLogger.instance.info(
          'PaymentMonitorRealtime',
          'Payment monitor realtime disconnected',
          context: {
            'reason': reason,
            'storeId': _requestStoreId ?? _user?.storeId,
          },
        ),
      );
    }
  }

  Future<void> _handleRealtimeMessage(dynamic message) async {
    try {
      final decoded = jsonDecode(message.toString());
      if (decoded is! Map<String, dynamic>) return;
      final eventType = decoded['type']?.toString();
      if (eventType != 'PAYMENT_NOTIFICATION' &&
          eventType != 'PAYMENT_SPEAKER_STREAM') {
        return;
      }
      final rawPayload = decoded['payload'];
      final payload = rawPayload is Map<String, dynamic>
          ? rawPayload
          : rawPayload is Map
          ? rawPayload.map((key, value) => MapEntry(key.toString(), value))
          : jsonDecode(rawPayload.toString()) as Map<String, dynamic>;
      final eventStore = payload['storeCode']?.toString().trim().toUpperCase();
      final expectedStore = (_requestStoreId ?? _user?.storeId)
          ?.trim()
          .toUpperCase();
      if (expectedStore != null &&
          expectedStore.isNotEmpty &&
          eventStore != null &&
          eventStore.isNotEmpty &&
          eventStore != expectedStore) {
        return;
      }
      await AppLogger.instance.info(
        'PaymentMonitorRealtime',
        eventType == 'PAYMENT_SPEAKER_STREAM'
            ? 'Payment speaker stream realtime event received'
            : 'Payment notification realtime event received',
        context: {
          'eventType': eventType,
          'storeId': eventStore,
          'notificationId': payload['notificationId']?.toString(),
          'transactionId': payload['transactionId']?.toString(),
          'audioStatus': payload['audioStatus']?.toString(),
          'speakerEligible': _canUsePaymentSpeaker,
          'speakerEnabled': _isSpeakerEnabled,
        },
      );
      _scheduleRealtimeRefresh();
      if (eventType == 'PAYMENT_SPEAKER_STREAM') {
        await _handleStreamNotificationPayload(payload);
      }
    } catch (error, stackTrace) {
      await AppLogger.instance.warn(
        'PaymentMonitorRealtime',
        'Payment notification realtime event ignored',
        context: {
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        },
      );
    }
  }

  @visibleForTesting
  Future<void> handleRealtimeMessageForTesting(dynamic message) {
    return _handleRealtimeMessage(message);
  }

  void _scheduleRealtimeRefresh() {
    _realtimeRefreshTimer?.cancel();
    _realtimeRefreshTimer = Timer(_realtimeRefreshDebounce, () {
      _poll(force: true, includeTotal: false, reason: 'realtime_event');
    });
  }

  Future<void> _handleStreamNotificationPayload(
    Map<String, dynamic> payload,
  ) async {
    final notificationPayload = Map<String, dynamic>.from(payload);
    notificationPayload['audioStatus'] =
        notificationPayload['audioStatus']?.toString().trim().isNotEmpty == true
        ? notificationPayload['audioStatus']
        : 'STREAMING';
    final notification = PaymentNotification.fromJson(notificationPayload);
    if (!notification.isValid) {
      await AppLogger.instance.warn(
        'PaymentMonitorRealtime',
        'Payment speaker stream event ignored because payload is invalid',
        context: {
          'notificationId': payload['notificationId']?.toString(),
          'storeCode': payload['storeCode']?.toString(),
        },
      );
      return;
    }
    if (!_canUsePaymentSpeaker) {
      await AppLogger.instance.info(
        'PaymentMonitorRealtime',
        'Payment speaker stream event ignored because speaker is unavailable',
        context: {
          'notificationId': notification.notificationId,
          'transactionId': notification.transactionId,
          'storeCode': notification.storeCode,
          'reason': _speakerEligibilityReason(),
          'hasPaymentSpeakerFeature': _userCanUsePaymentSpeakerFeature(_user),
          'supportsPaymentSpeaker': _canUseSpeakerOnThisDevice,
        },
      );
      return;
    }

    final clientId = await _ensureClientId();
    if (!_isSpeakerEnabled) {
      await _silenceStreamNotification(
        notification,
        clientId,
        reason: 'speaker_disabled',
      );
      return;
    }

    _enqueueStreamNotification(notification, clientId);
  }

  void _enqueueStreamNotification(
    PaymentNotification notification,
    String clientId,
  ) {
    if (_terminalNotificationIds.contains(notification.notificationId) ||
        _queuedStreamNotificationIds.contains(notification.notificationId)) {
      return;
    }
    _queuedStreamNotificationIds.add(notification.notificationId);
    _streamNotificationQueue.add(notification);
    unawaited(
      AppLogger.instance.info(
        'PaymentMonitor',
        'Payment speaker stream notification queued',
        context: {
          'notificationId': notification.notificationId,
          'transactionId': notification.transactionId,
          'storeCode': notification.storeCode,
          'queueLength': _streamNotificationQueue.length,
        },
      ),
    );
    unawaited(_drainStreamNotifications(clientId));
  }

  Future<void> _drainStreamNotifications(String clientId) async {
    if (_isDrainingStreamNotifications) return;
    _isDrainingStreamNotifications = true;
    try {
      while (_streamNotificationQueue.isNotEmpty) {
        final notification = _streamNotificationQueue.removeFirst();
        _queuedStreamNotificationIds.remove(notification.notificationId);
        if (_terminalNotificationIds.contains(notification.notificationId)) {
          continue;
        }
        if (!_canUsePaymentSpeaker) {
          await AppLogger.instance.info(
            'PaymentMonitor',
            'Queued payment stream skipped because speaker became unavailable',
            context: {
              'notificationId': notification.notificationId,
              'transactionId': notification.transactionId,
              'storeCode': notification.storeCode,
              'reason': _speakerEligibilityReason(),
            },
          );
          continue;
        }
        if (!_isSpeakerEnabled) {
          await _silenceStreamNotification(
            notification,
            clientId,
            reason: 'speaker_disabled_after_queue',
          );
          continue;
        }
        await _playReadyNotifications(
          [notification],
          clientId,
          useStreamEndpoint: true,
        );
      }
    } finally {
      _isDrainingStreamNotifications = false;
    }
  }

  Future<void> _poll({
    bool force = false,
    bool bypassBackoff = false,
    bool includeTotal = true,
    String reason = 'unknown',
  }) async {
    if (!_canMonitorOnThisDevice || !_hasMonitorScope) return;
    if (_isLoading) {
      if (force) {
        _refreshQueuedWhileLoading = true;
        _queuedRefreshIncludeTotal = _queuedRefreshIncludeTotal || includeTotal;
      }
      return;
    }
    final nextPollAllowedAt = _nextPollAllowedAt;
    if (shouldDeferPaymentPoll(
      now: DateTime.now(),
      nextPollAllowedAt: nextPollAllowedAt,
      bypassBackoff: bypassBackoff,
    )) {
      await AppLogger.instance.info(
        'PaymentMonitor',
        'Payment monitor poll deferred by backoff',
        context: {
          'reason': reason,
          'nextRetryAt': nextPollAllowedAt?.toIso8601String(),
          'failureCount': _pollFailureCount,
        },
      );
      return;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    var phase = 'stored_transactions';
    try {
      final speakerEligible = _canUsePaymentSpeaker;
      if (!_loggedMonitorStarted) {
        _loggedMonitorStarted = true;
        await AppLogger.instance.info(
          'PaymentMonitor',
          'Payment monitor started',
          context: {
            'storeId': _requestStoreId ?? _user?.storeId,
            'checkpointAt': _notificationCheckpointAt?.toIso8601String(),
            'hasPaymentSpeakerFeature': _userCanUsePaymentSpeakerFeature(_user),
            'supportsPaymentMonitor': _canMonitorOnThisDevice,
            'supportsPaymentSpeaker': _canUseSpeakerOnThisDevice,
            'speakerEligible': speakerEligible,
            'reason': reason,
          },
        );
      }
      String? clientId;
      if (speakerEligible) {
        phase = 'client_id';
        clientId = await _ensureClientId();
      }
      phase = 'stored_transactions';
      final transactionPage = await _repository.fetchStoredTransactions(
        storeId: _user?.isSuperAdmin == true ? _requestStoreId : null,
        storeIds: _user?.isSuperAdmin == true ? null : _listStoreIdsParam,
        startDate: _formatDateForApi(_rangeStartDate),
        endDate: _formatDateForApi(_rangeEndDate),
        page: _pageIndex,
        limit: _pageSize,
        includeTotal: includeTotal,
      );
      if (speakerEligible) {
        phase = 'ready_notifications';
        final notifications = await _repository.fetchReadyNotifications(
          clientId: clientId!,
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
      }

      _lastCheckedAt = DateTime.now();
      _pollFailureCount = 0;
      _nextPollAllowedAt = null;
      _pageIndex = transactionPage.page;
      _pageSize = transactionPage.limit;
      _canReviewOrderTransfers = transactionPage.canReviewOrderTransfers;
      final total = transactionPage.total;
      if (total != null) _totalTransactions = total;
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
          'reason': reason,
          'includeTotal': includeTotal,
        },
      );
      if (pollError.isAuthFailure) {
        _stop(reason: 'auth_failed', clearError: false);
      }
    } finally {
      _isLoading = false;
      notifyListeners();
      if (_refreshQueuedWhileLoading &&
          _canMonitorOnThisDevice &&
          _hasMonitorScope) {
        final queuedIncludeTotal = _queuedRefreshIncludeTotal;
        _refreshQueuedWhileLoading = false;
        _queuedRefreshIncludeTotal = false;
        unawaited(
          _poll(
            force: true,
            bypassBackoff: false,
            includeTotal: queuedIncludeTotal,
            reason: 'queued_after_loading',
          ),
        );
      }
    }
  }

  Future<void> updateOrders(String transactionId, String rawInput) async {
    try {
      final orders = parseStatementOrderInput(rawInput);
      await AppLogger.instance.info(
        'PaymentMonitor',
        'Payment monitor inline order save started',
        context: {'transactionId': transactionId, 'orderCount': orders.length},
      );
      final updated = await _repository.updateOrders(transactionId, orders);
      _replaceTransaction(updated);
      _showRowMessage(transactionId, 'Đã cập nhật mã đơn hàng.', true);
      await AppLogger.instance.info(
        'PaymentMonitor',
        'Payment monitor inline order save succeeded',
        context: {'transactionId': transactionId, 'orderCount': orders.length},
      );
    } catch (error) {
      _showRowMessage(
        transactionId,
        _orderInputErrorMessage(error, fallback: 'Chưa lưu được mã đơn.'),
        false,
      );
      await AppLogger.instance.error(
        'PaymentMonitor',
        'Payment monitor inline order save failed',
        error: error,
        context: {'transactionId': transactionId},
      );
    }
  }

  Future<bool> requestOrderTransfer(
    String transactionId,
    String rawInput,
  ) async {
    try {
      final orders = parseStatementOrderInput(rawInput);
      if (orders.isEmpty) {
        _showRowMessage(transactionId, 'Vui lòng nhập mã đơn hàng mới.', false);
        return false;
      }
      await AppLogger.instance.info(
        'PaymentMonitor',
        'Payment monitor order transfer request started',
        context: {'transactionId': transactionId, 'orderCount': orders.length},
      );
      await _repository.createOrderTransferRequest(transactionId, orders);
      await _refreshCurrentPageAfterOrderAction(
        reason: 'order_transfer_request',
      );
      _showRowMessage(transactionId, 'Đã gửi Kế toán xác nhận.', true);
      await AppLogger.instance.info(
        'PaymentMonitor',
        'Payment monitor order transfer request succeeded',
        context: {'transactionId': transactionId, 'orderCount': orders.length},
      );
      return true;
    } catch (error) {
      _showRowMessage(
        transactionId,
        _orderInputErrorMessage(
          error,
          fallback: 'Chưa gửi được yêu cầu cập nhật mã đơn.',
        ),
        false,
      );
      await AppLogger.instance.error(
        'PaymentMonitor',
        'Payment monitor order transfer request failed',
        error: error,
        context: {'transactionId': transactionId},
      );
      return false;
    }
  }

  Future<List<BankStatementOrderHistoryEntry>> fetchOrderHistory(
    String transactionId,
  ) async {
    try {
      await AppLogger.instance.info(
        'PaymentMonitor',
        'Payment monitor order history load started',
        context: {'transactionId': transactionId},
      );
      final rows = await _repository.fetchOrderHistory(transactionId);
      await AppLogger.instance.info(
        'PaymentMonitor',
        'Payment monitor order history load succeeded',
        context: {'transactionId': transactionId, 'count': rows.length},
      );
      return rows;
    } catch (error) {
      await AppLogger.instance.error(
        'PaymentMonitor',
        'Payment monitor order history load failed',
        error: error,
        context: {'transactionId': transactionId},
      );
      rethrow;
    }
  }

  Future<void> approveOrderTransferRequest(
    String transactionId,
    String requestId,
  ) {
    return _reviewOrderTransferRequest(
      transactionId,
      requestId,
      approved: true,
    );
  }

  Future<void> rejectOrderTransferRequest(
    String transactionId,
    String requestId, {
    String? note,
  }) {
    return _reviewOrderTransferRequest(
      transactionId,
      requestId,
      approved: false,
      note: note,
    );
  }

  Future<void> _reviewOrderTransferRequest(
    String transactionId,
    String requestId, {
    required bool approved,
    String? note,
  }) async {
    try {
      await AppLogger.instance.info(
        'PaymentMonitor',
        approved
            ? 'Payment monitor order transfer approval started'
            : 'Payment monitor order transfer rejection started',
        context: {
          'transactionId': transactionId,
          'requestId': requestId,
          'hasNote': note?.trim().isNotEmpty == true,
        },
      );
      final updated = approved
          ? await _repository.approveOrderTransferRequest(requestId)
          : await _repository.rejectOrderTransferRequest(requestId, note: note);
      if (updated != null) {
        _replaceTransaction(updated);
      } else {
        await _refreshCurrentPageAfterOrderAction(
          reason: approved
              ? 'order_transfer_approved'
              : 'order_transfer_rejected',
        );
      }
      _showRowMessage(
        transactionId,
        approved ? 'Đã cập nhật mã đơn hàng.' : 'Đã từ chối yêu cầu.',
        true,
      );
      await AppLogger.instance.info(
        'PaymentMonitor',
        approved
            ? 'Payment monitor order transfer approval succeeded'
            : 'Payment monitor order transfer rejection succeeded',
        context: {'transactionId': transactionId, 'requestId': requestId},
      );
    } catch (error) {
      _showRowMessage(
        transactionId,
        approved ? 'Chưa duyệt được yêu cầu.' : 'Chưa từ chối được yêu cầu.',
        false,
      );
      await AppLogger.instance.error(
        'PaymentMonitor',
        approved
            ? 'Payment monitor order transfer approval failed'
            : 'Payment monitor order transfer rejection failed',
        error: error,
        context: {'transactionId': transactionId, 'requestId': requestId},
      );
    }
  }

  Future<void> _refreshCurrentPageAfterOrderAction({
    required String reason,
  }) async {
    await _poll(
      force: true,
      bypassBackoff: true,
      includeTotal: true,
      reason: reason,
    );
  }

  void _replaceTransaction(MapPaymentTransaction updated) {
    final index = _latestTransactions.indexWhere(
      (transaction) => transaction.id == updated.id,
    );
    if (index < 0) return;
    _latestTransactions[index] = updated;
    notifyListeners();
  }

  String _orderInputErrorMessage(Object error, {required String fallback}) {
    if (error is api.ApiException && error.message.trim().isNotEmpty) {
      return error.message;
    }
    if (error is FormatException) {
      return 'Mã đơn hàng phải gồm 14 chữ số, ngăn cách bằng dòng hoặc dấu phẩy.';
    }
    return fallback;
  }

  void _showRowMessage(String id, String text, bool success) {
    _rowMessageTimers.remove(id)?.cancel();
    _rowMessages[id] = PaymentMonitorRowMessage(text: text, success: success);
    notifyListeners();
    _rowMessageTimers[id] = Timer(const Duration(seconds: 3), () {
      _rowMessages.remove(id);
      _rowMessageTimers.remove(id);
      notifyListeners();
    });
  }

  void _clearRowMessages({required bool notify}) {
    for (final timer in _rowMessageTimers.values) {
      timer.cancel();
    }
    _rowMessageTimers.clear();
    _rowMessages.clear();
    if (notify) notifyListeners();
  }

  static List<String> _assignedStoreIdsFor(User? user) {
    if (user == null) return const [];
    final ids = user.assignedStoreIds
        .map((value) => value.trim().toUpperCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty && user.storeId?.trim().isNotEmpty == true) {
      ids.add(user.storeId!.trim().toUpperCase());
    }
    ids.sort();
    return ids;
  }

  static String? _defaultActiveStoreIdFor(User? user) {
    final ids = _assignedStoreIdsFor(user);
    return ids.length == 1 ? ids.first : null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _realtimeRefreshTimer?.cancel();
    _clearRowMessages(notify: false);
    unawaited(_realtimeSubscription?.cancel());
    unawaited(_realtimeChannel?.sink.close());
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
    if (!_canUsePaymentSpeaker) {
      await AppLogger.instance.info(
        'PaymentMonitor',
        'Payment notifications ignored because speaker feature is unavailable',
        context: {
          'count': notifications.length,
          'clientId': clientId,
          'storeCode': _requestStoreId ?? _user?.storeId,
          'reason': _speakerEligibilityReason(),
          'hasPaymentSpeakerFeature': _userCanUsePaymentSpeakerFeature(_user),
          'supportsPaymentMonitor': _canMonitorOnThisDevice,
          'supportsPaymentSpeaker': _canUseSpeakerOnThisDevice,
        },
      );
      return;
    }
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
      _setTerminalNotification(notification.notificationId);
      await _acknowledgeNotificationEvent(
        notificationId: notification.notificationId,
        clientId: clientId,
        event: 'SILENCED',
        error: 'speaker_disabled',
      );
    }
  }

  Future<void> _silenceStreamNotification(
    PaymentNotification notification,
    String clientId, {
    required String reason,
  }) async {
    if (_terminalNotificationIds.contains(notification.notificationId)) return;
    _setTerminalNotification(notification.notificationId);
    await AppLogger.instance.info(
      'PaymentSpeaker',
      'Payment speaker stream skipped because speaker is disabled',
      context: {
        'notificationId': notification.notificationId,
        'transactionId': notification.transactionId,
        'storeCode': notification.storeCode,
        'clientId': clientId,
        'amount': notification.amount,
        'reason': reason,
      },
    );
    await AppLogger.instance.uploadLog(
      'info',
      'PaymentSpeaker',
      'Payment speaker stream skipped because speaker is disabled',
      context: {
        'notificationId': notification.notificationId,
        'transactionId': notification.transactionId,
        'clientId': clientId,
        'amount': notification.amount,
        'reason': reason,
      },
      storeCode: notification.storeCode,
    );
    await _acknowledgeNotificationEvent(
      notificationId: notification.notificationId,
      clientId: clientId,
      event: 'SILENCED',
      error: reason,
    );
  }

  Future<void> _playReadyNotifications(
    List<PaymentNotification> notifications,
    String clientId, {
    bool useStreamEndpoint = false,
  }) async {
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
        await _playNotificationWithRetry(
          notification,
          clientId,
          useStreamEndpoint: useStreamEndpoint,
        );
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
    String clientId, {
    bool useStreamEndpoint = false,
  }) async {
    if (!useStreamEndpoint && notification.audioStatus != 'READY') {
      throw StateError(
        'Server audio is not ready: ${notification.audioStatus}',
      );
    }

    final audio = await _downloadNotificationAudio(
      notification,
      useStreamEndpoint: useStreamEndpoint,
    );
    var streamStartedAckSent = false;
    for (var attempt = 1; attempt <= _maxAudioPlaybackAttempts; attempt += 1) {
      try {
        final startedAt = DateTime.now();
        final startContext = {
          'notificationId': notification.notificationId,
          'transactionId': notification.transactionId,
          'storeCode': notification.storeCode,
          'clientId': clientId,
          'amount': notification.amount,
          'attempt': attempt,
          'bytes': audio.bytes.length,
          'audioMode': audio.mode,
          'streaming': useStreamEndpoint,
        };
        unawaited(
          AppLogger.instance.info(
            'PaymentSpeaker',
            'Payment speaker playback started',
            context: startContext,
          ),
        );
        unawaited(
          AppLogger.instance.uploadLog(
            'info',
            'PaymentSpeaker',
            'Payment speaker playback started',
            context: {
              'notificationId': notification.notificationId,
              'transactionId': notification.transactionId,
              'clientId': clientId,
              'amount': notification.amount,
              'attempt': attempt,
              'bytes': audio.bytes.length,
              'audioMode': audio.mode,
              'streaming': useStreamEndpoint,
            },
            storeCode: notification.storeCode,
          ),
        );
        final result = await _playNotificationOnce(
          notification: notification,
          clientId: clientId,
          attempt: attempt,
          audio: audio,
          onPlaybackStarting: useStreamEndpoint
              ? () {
                  if (streamStartedAckSent) return Future<void>.value();
                  streamStartedAckSent = true;
                  return _acknowledgeNotificationEvent(
                    notificationId: notification.notificationId,
                    clientId: clientId,
                    event: 'STREAM_STARTED',
                  ).then((_) {});
                }
              : null,
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
            'audioMode': audio.mode,
            if (result.sampleRateHz != null)
              'sampleRateHz': result.sampleRateHz,
            if (result.channels != null) 'channels': result.channels,
            if (result.bitsPerSample != null)
              'bitsPerSample': result.bitsPerSample,
            if (result.audioPreflightStatus != null)
              'audioPreflightStatus': result.audioPreflightStatus,
            'startedAt': startedAt.toIso8601String(),
            'streaming': useStreamEndpoint,
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
            'audioMode': audio.mode,
            if (result.sampleRateHz != null)
              'sampleRateHz': result.sampleRateHz,
            if (result.channels != null) 'channels': result.channels,
            if (result.bitsPerSample != null)
              'bitsPerSample': result.bitsPerSample,
            if (result.audioPreflightStatus != null)
              'audioPreflightStatus': result.audioPreflightStatus,
            'startedAt': startedAt.toIso8601String(),
            'streaming': useStreamEndpoint,
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
          'streaming': useStreamEndpoint,
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

  Future<_DownloadedPaymentAudio> _downloadNotificationAudio(
    PaymentNotification notification, {
    bool useStreamEndpoint = false,
  }) async {
    await AppLogger.instance.info(
      'PaymentMonitor',
      'Downloading payment notification audio',
      context: {
        'notificationId': notification.notificationId,
        'transactionId': notification.transactionId,
        'storeCode': notification.storeCode,
        'amount': notification.amount,
        'preferredMode': 'client_cue_prefix_amount',
        'streaming': useStreamEndpoint,
      },
    );
    try {
      final audioBytes = useStreamEndpoint
          ? await _repository.downloadNotificationStreamAudio(
              notification.notificationId,
              rawAmount: true,
            )
          : await _repository.downloadNotificationAudio(
              notification.notificationId,
              rawAmount: true,
            );
      if (audioBytes.isEmpty) {
        throw StateError('Raw amount audio is empty');
      }
      await _logNotificationAudioDownloaded(
        notification: notification,
        bytes: audioBytes.length,
        mode: 'client_cue_prefix_amount',
        streaming: useStreamEndpoint,
      );
      return _DownloadedPaymentAudio(
        bytes: audioBytes,
        playLocalCue: false,
        playLocalCuePrefix: true,
        mode: 'client_cue_prefix_amount',
      );
    } catch (error, stackTrace) {
      if (error is api.ApiException &&
          (error.statusCode == 401 || error.statusCode == 403)) {
        rethrow;
      }
      final safeError = _safeSpeakerError(error);
      await AppLogger.instance.warn(
        'PaymentMonitor',
        'Raw amount payment audio unavailable; falling back to server combined cue',
        context: {
          'notificationId': notification.notificationId,
          'transactionId': notification.transactionId,
          'storeCode': notification.storeCode,
          'amount': notification.amount,
          'audioMode': 'server_combined_cue',
          'streaming': useStreamEndpoint,
          'error': safeError,
          'stackTrace': stackTrace.toString(),
        },
      );
      await AppLogger.instance.uploadLog(
        'warn',
        'PaymentMonitor',
        'Raw amount payment audio unavailable; falling back to server combined cue',
        context: {
          'notificationId': notification.notificationId,
          'transactionId': notification.transactionId,
          'amount': notification.amount,
          'audioMode': 'server_combined_cue',
          'streaming': useStreamEndpoint,
          'error': safeError,
        },
        storeCode: notification.storeCode,
      );
    }

    try {
      final audioBytes = useStreamEndpoint
          ? await _repository.downloadNotificationStreamAudio(
              notification.notificationId,
              includeCue: true,
            )
          : await _repository.downloadNotificationAudio(
              notification.notificationId,
              includeCue: true,
            );
      if (audioBytes.isEmpty) {
        throw StateError('Server combined audio is empty');
      }
      await _logNotificationAudioDownloaded(
        notification: notification,
        bytes: audioBytes.length,
        mode: 'server_combined_cue',
        streaming: useStreamEndpoint,
      );
      return _DownloadedPaymentAudio(
        bytes: audioBytes,
        playLocalCue: false,
        playLocalCuePrefix: false,
        mode: 'server_combined_cue',
      );
    } catch (error, stackTrace) {
      if (error is api.ApiException &&
          (error.statusCode == 401 || error.statusCode == 403)) {
        rethrow;
      }
      final safeError = _safeSpeakerError(error);
      await AppLogger.instance.warn(
        'PaymentMonitor',
        'Combined payment audio unavailable; falling back to local cue',
        context: {
          'notificationId': notification.notificationId,
          'transactionId': notification.transactionId,
          'storeCode': notification.storeCode,
          'amount': notification.amount,
          'audioMode': 'local_cue_fallback',
          'streaming': useStreamEndpoint,
          'error': safeError,
          'stackTrace': stackTrace.toString(),
        },
      );
      await AppLogger.instance.uploadLog(
        'warn',
        'PaymentMonitor',
        'Combined payment audio unavailable; falling back to local cue',
        context: {
          'notificationId': notification.notificationId,
          'transactionId': notification.transactionId,
          'amount': notification.amount,
          'audioMode': 'local_cue_fallback',
          'streaming': useStreamEndpoint,
          'error': safeError,
        },
        storeCode: notification.storeCode,
      );
    }

    final audioBytes = useStreamEndpoint
        ? await _repository.downloadNotificationStreamAudio(
            notification.notificationId,
          )
        : await _repository.downloadNotificationAudio(
            notification.notificationId,
          );
    if (audioBytes.isEmpty) {
      throw StateError('Server audio is empty');
    }
    await _logNotificationAudioDownloaded(
      notification: notification,
      bytes: audioBytes.length,
      mode: 'local_cue_fallback',
      streaming: useStreamEndpoint,
    );
    return _DownloadedPaymentAudio(
      bytes: audioBytes,
      playLocalCue: true,
      playLocalCuePrefix: false,
      mode: 'local_cue_fallback',
    );
  }

  Future<void> _logNotificationAudioDownloaded({
    required PaymentNotification notification,
    required int bytes,
    required String mode,
    required bool streaming,
  }) async {
    await AppLogger.instance.info(
      'PaymentMonitor',
      'Payment notification audio downloaded',
      context: {
        'notificationId': notification.notificationId,
        'bytes': bytes,
        'audioMode': mode,
        'streaming': streaming,
      },
    );
    await AppLogger.instance.uploadLog(
      'info',
      'PaymentMonitor',
      'Payment notification audio downloaded',
      context: {
        'notificationId': notification.notificationId,
        'bytes': bytes,
        'audioMode': mode,
        'streaming': streaming,
      },
      storeCode: notification.storeCode,
    );
  }

  Future<PaymentSpeakerResult> _playNotificationOnce({
    required PaymentNotification notification,
    required String clientId,
    required int attempt,
    required _DownloadedPaymentAudio audio,
    Future<void> Function()? onPlaybackStarting,
  }) async {
    return _speaker.playServerAudio(
      amount: notification.amount,
      audioBytes: audio.bytes,
      notificationId: notification.notificationId,
      transactionId: notification.transactionId,
      storeCode: notification.storeCode,
      clientId: clientId,
      attempt: attempt,
      playLocalCue: audio.playLocalCue,
      playLocalCuePrefix: audio.playLocalCuePrefix,
      onPlaybackStarting: onPlaybackStarting,
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
