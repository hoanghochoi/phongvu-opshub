import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/realtime_connection_manager.dart';
import '../../../auth/domain/entities/user.dart';
import '../../data/repositories/payment_monitor_repository.dart';
import '../../domain/payment_delivery_metrics.dart';

class PaymentDeliveryMetricsProvider extends ChangeNotifier {
  static const _defaultWindowHours = 24;
  static const _defaultHistoryLimit = 20;
  static const _defaultRefreshInterval = Duration(minutes: 15);
  static const _defaultRealtimeDebounce = Duration(seconds: 30);

  final PaymentMonitorRepository _repository;
  final Duration _refreshInterval;
  final Duration _realtimeDebounce;
  final RealtimeClient _realtimeClient;

  User? _user;
  Timer? _timer;
  Timer? _realtimeDebounceTimer;
  StreamSubscription<RealtimeEnvelope>? _realtimeEventSubscription;
  StreamSubscription<RealtimeSyncReason>? _realtimeSyncSubscription;
  PaymentDeliveryMetrics? _metrics;
  List<PaymentDeliveryHistoryItem> _historyItems =
      const <PaymentDeliveryHistoryItem>[];
  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isHistoryLoading = false;
  bool _disposed = false;
  bool _isForeground = true;
  bool _isSurfaceActive = true;
  String? _errorMessage;
  String? _historyErrorMessage;
  DateTime? _lastLoadedAt;
  DateTime? _historyLoadedAt;
  int _authGeneration = 0;
  int _metricsRequestToken = 0;
  int _historyRequestToken = 0;
  String? _authorizationSignature;

  PaymentDeliveryMetricsProvider(
    this._repository, {
    Duration refreshInterval = _defaultRefreshInterval,
    Duration realtimeDebounce = _defaultRealtimeDebounce,
    RealtimeClient? realtimeClient,
  }) : _refreshInterval = refreshInterval,
       _realtimeDebounce = realtimeDebounce,
       _realtimeClient = realtimeClient ?? RealtimeConnectionManager.instance {
    _realtimeEventSubscription = _realtimeClient.events.listen(
      _handleRealtimeEnvelope,
    );
    _realtimeSyncSubscription = _realtimeClient.syncRequests.listen(
      _handleRealtimeSyncRequest,
    );
  }

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

  Future<void> syncRuntime({
    required bool isForeground,
    required bool isSurfaceActive,
  }) async {
    if (_disposed) return;
    final becameEligible =
        (!_isForeground || !_isSurfaceActive) &&
        isForeground &&
        isSurfaceActive;
    _isForeground = isForeground;
    _isSurfaceActive = isSurfaceActive;
    if (!isEnabled || !_isForeground || !_isSurfaceActive) {
      _stopTimer();
      _cancelRealtimeDebounce();
      return;
    }
    _startTimer();
    if (becameEligible && _metrics == null) await load(silent: true);
  }

  Future<void> syncAuth(User? user, {required bool isInitialized}) async {
    if (_disposed) return;
    final wasEnabled = isEnabled;
    final userChanged = _user?.id != user?.id || _user?.email != user?.email;
    _user = user;
    _isInitialized = isInitialized;
    final nextSignature = _authSignature(user, isInitialized);
    final authorizationChanged = _authorizationSignature != nextSignature;
    _authorizationSignature = nextSignature;
    if (authorizationChanged) {
      _authGeneration += 1;
      _metricsRequestToken += 1;
      _historyRequestToken += 1;
      _isLoading = false;
      _isHistoryLoading = false;
    }
    if (!isEnabled) {
      _stopTimer();
      _cancelRealtimeDebounce();
      _clear();
      return;
    }
    if (_isForeground && _isSurfaceActive) _startTimer();
    if (_isForeground &&
        _isSurfaceActive &&
        (!wasEnabled || userChanged || _metrics == null)) {
      await load(silent: true);
    }
  }

  Future<void> load({bool silent = false}) async {
    if (_disposed ||
        !isEnabled ||
        !_isForeground ||
        !_isSurfaceActive ||
        _isLoading) {
      return;
    }
    _isLoading = true;
    final authGeneration = _authGeneration;
    final requestToken = ++_metricsRequestToken;
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
      if (!_isCurrentMetricsRequest(authGeneration, requestToken)) return;
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
      if (!_isCurrentMetricsRequest(authGeneration, requestToken)) return;
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
      if (_isCurrentMetricsRequest(authGeneration, requestToken)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadHistory({int limit = _defaultHistoryLimit}) async {
    if (_disposed || !isEnabled || _isHistoryLoading) return;
    _isHistoryLoading = true;
    final authGeneration = _authGeneration;
    final requestToken = ++_historyRequestToken;
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
      if (!_isCurrentHistoryRequest(authGeneration, requestToken)) return;
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
      if (!_isCurrentHistoryRequest(authGeneration, requestToken)) return;
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
      if (_isCurrentHistoryRequest(authGeneration, requestToken)) {
        _isHistoryLoading = false;
        notifyListeners();
      }
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

  void _handleRealtimeEnvelope(RealtimeEnvelope envelope) {
    if (envelope.kind != 'PAYMENT_DELIVERY_METRICS_UPDATED' ||
        envelope.topic != 'payment.delivery-metrics' ||
        !isEnabled ||
        !_isForeground ||
        !_isSurfaceActive) {
      return;
    }
    _realtimeDebounceTimer?.cancel();
    if (_realtimeDebounce <= Duration.zero) {
      unawaited(load(silent: true));
      return;
    }
    _realtimeDebounceTimer = Timer(_realtimeDebounce, () {
      _realtimeDebounceTimer = null;
      unawaited(load(silent: true));
    });
    unawaited(
      AppLogger.instance.info(
        'PaymentDeliveryMetrics',
        'Payment delivery metrics realtime invalidation queued',
        context: {
          'eventId': envelope.id,
          'debounceMs': _realtimeDebounce.inMilliseconds,
        },
      ),
    );
  }

  void _handleRealtimeSyncRequest(RealtimeSyncReason reason) {
    if (!isEnabled || !_isForeground || !_isSurfaceActive) return;
    _cancelRealtimeDebounce();
    unawaited(
      AppLogger.instance.info(
        'PaymentDeliveryMetrics',
        'Payment delivery metrics realtime sync requested',
        context: {'reason': reason.name},
      ),
    );
    unawaited(load(silent: true));
  }

  void _cancelRealtimeDebounce() {
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = null;
  }

  static String _authSignature(User? user, bool isInitialized) {
    if (!isInitialized || user == null) return 'signed_out';
    return '${user.id ?? ''}|${user.email}|${user.isSuperAdmin}';
  }

  bool _isCurrentMetricsRequest(int authGeneration, int requestToken) =>
      !_disposed &&
      isEnabled &&
      authGeneration == _authGeneration &&
      requestToken == _metricsRequestToken;

  bool _isCurrentHistoryRequest(int authGeneration, int requestToken) =>
      !_disposed &&
      isEnabled &&
      authGeneration == _authGeneration &&
      requestToken == _historyRequestToken;

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
    _cancelRealtimeDebounce();
    unawaited(_realtimeEventSubscription?.cancel());
    unawaited(_realtimeSyncSubscription?.cancel());
    super.dispose();
  }
}
