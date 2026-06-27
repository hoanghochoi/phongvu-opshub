import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../auth/domain/entities/user.dart';
import '../../data/repositories/payment_monitor_repository.dart';
import '../../domain/payment_delivery_metrics.dart';

class PaymentDeliveryMetricsProvider extends ChangeNotifier {
  static const _defaultWindowHours = 24;
  static const _defaultHistoryLimit = 20;
  static const _defaultRefreshInterval = Duration(minutes: 1);

  final PaymentMonitorRepository _repository;
  final Duration _refreshInterval;

  User? _user;
  Timer? _timer;
  PaymentDeliveryMetrics? _metrics;
  List<PaymentDeliveryHistoryItem> _historyItems =
      const <PaymentDeliveryHistoryItem>[];
  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isHistoryLoading = false;
  bool _disposed = false;
  String? _errorMessage;
  String? _historyErrorMessage;
  DateTime? _lastLoadedAt;
  DateTime? _historyLoadedAt;

  PaymentDeliveryMetricsProvider(
    this._repository, {
    Duration refreshInterval = _defaultRefreshInterval,
  }) : _refreshInterval = refreshInterval;

  PaymentDeliveryMetrics? get metrics => _metrics;
  List<PaymentDeliveryHistoryItem> get historyItems => _historyItems;
  bool get isLoading => _isLoading;
  bool get isHistoryLoading => _isHistoryLoading;
  String? get errorMessage => _errorMessage;
  String? get historyErrorMessage => _historyErrorMessage;
  DateTime? get lastLoadedAt => _lastLoadedAt;
  DateTime? get historyLoadedAt => _historyLoadedAt;
  bool get isEnabled => _isInitialized && _user?.isSuperAdmin == true;
  bool get shouldShow => isEnabled;

  Future<void> syncAuth(User? user, {required bool isInitialized}) async {
    if (_disposed) return;
    final wasEnabled = isEnabled;
    final userChanged = _user?.id != user?.id || _user?.email != user?.email;
    _user = user;
    _isInitialized = isInitialized;
    if (!isEnabled) {
      _stopTimer();
      _clear();
      return;
    }
    _startTimer();
    if (!wasEnabled || userChanged || _metrics == null) {
      await load(silent: true);
    }
  }

  Future<void> load({bool silent = false}) async {
    if (_disposed || !isEnabled || _isLoading) return;
    _isLoading = true;
    _errorMessage = null;
    if (!silent && !_disposed) notifyListeners();
    final startedAt = DateTime.now();
    try {
      await AppLogger.instance.info(
        'PaymentDeliveryMetrics',
        'Payment delivery metrics load started',
        context: {'windowHours': _defaultWindowHours},
      );
      final result = await _repository.fetchDeliveryMetrics(
        windowHours: _defaultWindowHours,
      );
      if (_disposed) return;
      _metrics = result;
      _lastLoadedAt = DateTime.now();
      await AppLogger.instance.info(
        'PaymentDeliveryMetrics',
        'Payment delivery metrics load succeeded',
        context: {
          'windowHours': result.windowHours,
          'currentCount': result.current.count,
          'currentAverageMs': result.current.averageMs,
          'previousCount': result.previous.count,
          'previousAverageMs': result.previous.averageMs,
          'deltaMs': result.deltaMs,
          'deltaPercent': result.deltaPercent,
          'trend': result.trend.name,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error) {
      if (_disposed) return;
      _errorMessage = error.toString();
      await AppLogger.instance.warn(
        'PaymentDeliveryMetrics',
        'Payment delivery metrics load failed',
        context: {
          'windowHours': _defaultWindowHours,
          'error': error.toString(),
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } finally {
      _isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> loadHistory({int limit = _defaultHistoryLimit}) async {
    if (_disposed || !isEnabled || _isHistoryLoading) return;
    _isHistoryLoading = true;
    _historyErrorMessage = null;
    if (!_disposed) notifyListeners();
    final startedAt = DateTime.now();
    try {
      await AppLogger.instance.info(
        'PaymentDeliveryMetrics',
        'Payment delivery history load started',
        context: {'limit': limit},
      );
      final result = await _repository.fetchDeliveryHistory(limit: limit);
      if (_disposed) return;
      _historyItems = result.items;
      _historyLoadedAt = DateTime.now();
      await AppLogger.instance.info(
        'PaymentDeliveryMetrics',
        'Payment delivery history load succeeded',
        context: {
          'limit': result.limit,
          'itemCount': result.items.length,
          'errorCount': result.items.where((item) => item.hasError).length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error) {
      if (_disposed) return;
      _historyErrorMessage = error.toString();
      await AppLogger.instance.warn(
        'PaymentDeliveryMetrics',
        'Payment delivery history load failed',
        context: {
          'limit': limit,
          'error': error.toString(),
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } finally {
      _isHistoryLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _startTimer() {
    if (_timer != null || _refreshInterval.inMilliseconds <= 0) return;
    _timer = Timer.periodic(
      _refreshInterval,
      (_) => unawaited(load(silent: true)),
    );
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _clear() {
    final changed =
        _metrics != null ||
        _historyItems.isNotEmpty ||
        _isLoading ||
        _isHistoryLoading ||
        _errorMessage != null ||
        _historyErrorMessage != null ||
        _lastLoadedAt != null ||
        _historyLoadedAt != null;
    _metrics = null;
    _historyItems = const <PaymentDeliveryHistoryItem>[];
    _isLoading = false;
    _isHistoryLoading = false;
    _errorMessage = null;
    _historyErrorMessage = null;
    _lastLoadedAt = null;
    _historyLoadedAt = null;
    if (changed && !_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTimer();
    super.dispose();
  }
}
