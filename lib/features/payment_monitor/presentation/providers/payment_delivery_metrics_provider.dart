import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../auth/domain/entities/user.dart';
import '../../data/repositories/payment_monitor_repository.dart';
import '../../domain/payment_delivery_metrics.dart';

class PaymentDeliveryMetricsProvider extends ChangeNotifier {
  static const _defaultWindowHours = 24;
  static const _defaultRefreshInterval = Duration(minutes: 1);

  final PaymentMonitorRepository _repository;
  final Duration _refreshInterval;

  User? _user;
  Timer? _timer;
  PaymentDeliveryMetrics? _metrics;
  bool _isInitialized = false;
  bool _isLoading = false;
  bool _disposed = false;
  String? _errorMessage;
  DateTime? _lastLoadedAt;

  PaymentDeliveryMetricsProvider(
    this._repository, {
    Duration refreshInterval = _defaultRefreshInterval,
  }) : _refreshInterval = refreshInterval;

  PaymentDeliveryMetrics? get metrics => _metrics;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime? get lastLoadedAt => _lastLoadedAt;
  bool get isEnabled => _isInitialized && _user?.isSuperAdmin == true;
  bool get shouldShow => isEnabled && (_metrics != null || _isLoading);

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
        _isLoading ||
        _errorMessage != null ||
        _lastLoadedAt != null;
    _metrics = null;
    _isLoading = false;
    _errorMessage = null;
    _lastLoadedAt = null;
    if (changed && !_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTimer();
    super.dispose();
  }
}
