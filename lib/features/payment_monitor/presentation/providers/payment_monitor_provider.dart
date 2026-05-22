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
  DateTime _selectedDate = _todayInVietnam();
  int _pageIndex = 0;
  int _pageSize = 10;
  int _totalTransactions = 0;

  PaymentMonitorProvider(this._repository, this._speaker);

  bool get isActive => _isActive;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime? get lastCheckedAt => _lastCheckedAt;
  String? get storeOverride => _storeOverride;
  DateTime get selectedDate => _selectedDate;
  int get pageIndex => _pageIndex;
  int get pageSize => _pageSize;
  int get totalTransactions => _totalTransactions;
  bool get canGoPreviousPage => _pageIndex > 0;
  bool get canGoNextPage => (_pageIndex + 1) * _pageSize < _totalTransactions;
  List<MapPaymentTransaction> get latestTransactions =>
      List.unmodifiable(_latestTransactions);

  void syncAuth(User? user, {required bool isInitialized}) {
    _user = user;
    if (!isInitialized || user == null || !_canMonitorOnThisDevice) {
      _stop();
      return;
    }
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
    final normalized = DateTime(value.year, value.month, value.day);
    if (_isSameDate(_selectedDate, normalized)) return;
    _selectedDate = normalized;
    _pageIndex = 0;
    _poll();
  }

  void setPageSize(int value) {
    if (_pageSize == value) return;
    _pageSize = value;
    _pageIndex = 0;
    _poll();
  }

  void nextPage() {
    if (!canGoNextPage) return;
    _pageIndex += 1;
    _poll();
  }

  void previousPage() {
    if (!canGoPreviousPage) return;
    _pageIndex -= 1;
    _poll();
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
    if (!_hasMonitorScope) {
      _stop();
      return;
    }
    if (_isActive) return;
    _isActive = true;
    _notificationCheckpointAt = DateTime.now().toUtc();
    _seenNotificationIds.clear();
    _latestTransactions.clear();
    _poll();
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
    notifyListeners();
  }

  void _restart() {
    _stop();
    _reconcile();
  }

  void _stop() {
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
    _seenNotificationIds.clear();
    _latestTransactions.clear();
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _poll() async {
    if (_isLoading || !_hasMonitorScope) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final clientId = await _ensureClientId();
      final transactionPage = await _repository.fetchStoredTransactions(
        storeId: _requestStoreId,
        date: _formatDateForApi(_selectedDate),
        page: _pageIndex,
        limit: _pageSize,
      );
      final notifications = await _repository.fetchReadyNotifications(
        clientId: clientId,
        storeId: _requestStoreId,
        afterCreatedAt: _notificationCheckpointAt,
        limit: 3,
      );
      await _playReadyNotifications(notifications, clientId);

      _lastCheckedAt = DateTime.now();
      _pageIndex = transactionPage.page;
      _pageSize = transactionPage.limit;
      _totalTransactions = transactionPage.total;
      _latestTransactions
        ..clear()
        ..addAll(transactionPage.transactions);
    } catch (error) {
      _errorMessage = error.toString();
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

  Future<void> _playReadyNotifications(
    List<PaymentNotification> notifications,
    String clientId,
  ) async {
    for (final notification in notifications) {
      if (!_seenNotificationIds.add(notification.notificationId)) continue;
      try {
        if (notification.audioStatus != 'READY') {
          throw StateError(
            'Server audio is not ready: ${notification.audioStatus}',
          );
        }
        final audioBytes = await _repository.downloadNotificationAudio(
          notification.notificationId,
        );
        if (audioBytes.isEmpty) {
          throw StateError('Server audio is empty');
        }
        await _speaker.playServerAudio(
          amount: notification.amount,
          audioBytes: audioBytes,
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

  static bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _formatDateForApi(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }
}
