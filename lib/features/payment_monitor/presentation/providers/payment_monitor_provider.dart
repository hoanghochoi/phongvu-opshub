import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../auth/domain/entities/user.dart';
import '../../data/payment_speaker.dart';
import '../../data/repositories/payment_monitor_repository.dart';
import '../../domain/map_payment_transaction.dart';
import '../../domain/payment_notification.dart';

class PaymentMonitorProvider extends ChangeNotifier {
  static const _pollInterval = Duration(seconds: 5);
  static const _startupNotificationLookback = Duration(minutes: 15);
  static const _speakerEnabledPreferenceKey = 'payment_monitor_enabled';

  final PaymentMonitorRepository _repository;
  final PaymentSpeaker _speaker;
  final Set<String> _seenNotificationIds = {};
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

  PaymentMonitorProvider(this._repository, this._speaker) {
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
    await prefs.setBool(_speakerEnabledPreferenceKey, value);
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
    _poll();
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
    _poll();
  }

  void nextPage() {
    if (!canGoNextPage) return;
    _pageIndex += 1;
    unawaited(_logPageChanged('next'));
    _poll();
  }

  void previousPage() {
    if (!canGoPreviousPage) return;
    _pageIndex -= 1;
    unawaited(_logPageChanged('previous'));
    _poll();
  }

  Future<void> _loadEnabledPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_speakerEnabledPreferenceKey);
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
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

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
    _seenNotificationIds.clear();
    _latestTransactions.clear();
    _poll();
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
    notifyListeners();
  }

  void _restart() {
    _stop(reason: 'restart');
    _reconcile();
  }

  void _stop({required String reason}) {
    _timer?.cancel();
    _timer = null;
    if (!_isActive &&
        !_isLoading &&
        _latestTransactions.isEmpty &&
        _errorMessage == null) {
      return;
    }
    _isActive = false;
    _isLoading = false;
    _notificationCheckpointAt = null;
    _loggedMonitorStarted = false;
    _seenNotificationIds.clear();
    _latestTransactions.clear();
    _errorMessage = null;
    AppLogger.instance.info(
      'PaymentMonitor',
      'Payment monitor stopped',
      context: {'reason': reason, 'storeId': _requestStoreId ?? _user?.storeId},
    );
    notifyListeners();
  }

  Future<void> _poll() async {
    if (_isLoading || !_canMonitorOnThisDevice || !_hasMonitorScope) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

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
      final transactionPage = await _repository.fetchStoredTransactions(
        storeId: _requestStoreId,
        startDate: _formatDateForApi(_rangeStartDate),
        endDate: _formatDateForApi(_rangeEndDate),
        page: _pageIndex,
        limit: _pageSize,
      );
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
      await _handleReadyNotifications(notifications, clientId);

      _lastCheckedAt = DateTime.now();
      _pageIndex = transactionPage.page;
      _pageSize = transactionPage.limit;
      _totalTransactions = transactionPage.total;
      _latestTransactions
        ..clear()
        ..addAll(transactionPage.transactions);
    } catch (error) {
      _errorMessage = _friendlyPollError(error);
      await AppLogger.instance.error(
        'PaymentMonitor',
        'Payment monitor poll failed',
        error: error,
        upload: true,
        context: {
          'storeId': _requestStoreId ?? _user?.storeId,
          'startDate': _formatDateForApi(_rangeStartDate),
          'endDate': _formatDateForApi(_rangeEndDate),
          'page': _pageIndex,
          'limit': _pageSize,
        },
      );
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
    var value = prefs.getString('payment_monitor_client_id');
    if (value == null || value.isEmpty) {
      value = 'pc-${DateTime.now().microsecondsSinceEpoch}';
      await prefs.setString('payment_monitor_client_id', value);
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
      if (!_seenNotificationIds.add(notification.notificationId)) continue;
      await _repository.acknowledgeNotification(
        notificationId: notification.notificationId,
        clientId: clientId,
        event: 'SILENCED',
      );
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
      if (!_seenNotificationIds.add(notification.notificationId)) {
        await AppLogger.instance.warn(
          'PaymentMonitor',
          'Payment notification skipped as duplicate',
          context: {
            'notificationId': notification.notificationId,
            'transactionId': notification.transactionId,
            'storeCode': notification.storeCode,
          },
        );
        continue;
      }
      try {
        if (notification.audioStatus != 'READY') {
          throw StateError(
            'Server audio is not ready: ${notification.audioStatus}',
          );
        }
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
        await AppLogger.instance.info(
          'PaymentMonitor',
          'Calling payment speaker',
          context: {
            'notificationId': notification.notificationId,
            'amount': notification.amount,
          },
        );
        await _speaker.playServerAudio(
          amount: notification.amount,
          audioBytes: audioBytes,
        );
        await AppLogger.instance.info(
          'PaymentMonitor',
          'Acknowledging payment notification played',
          context: {'notificationId': notification.notificationId},
        );
        await _repository.acknowledgeNotification(
          notificationId: notification.notificationId,
          clientId: clientId,
          event: 'PLAYED',
        );
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
      } catch (error, stackTrace) {
        await AppLogger.instance.error(
          'PaymentMonitor',
          'Payment notification audio failed',
          error: error,
          stackTrace: stackTrace,
          upload: true,
          context: {'notificationId': notification.notificationId},
        );
        await _repository.acknowledgeNotification(
          notificationId: notification.notificationId,
          clientId: clientId,
          event: 'FAILED',
          error: error.toString(),
        );
      }
    }
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

  static String _friendlyPollError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('network') || text.contains('socket')) {
      return 'Không kết nối được. Vui lòng kiểm tra mạng rồi thử lại.';
    }
    if (text.contains('timeout')) {
      return 'Kết nối hơi lâu. Vui lòng thử lại sau ít phút.';
    }
    if (text.contains('401') || text.contains('403')) {
      return 'Tài khoản chưa có quyền xem giao dịch của showroom này.';
    }
    return 'Chưa cập nhật được giao dịch. Vui lòng thử lại sau ít phút.';
  }
}
