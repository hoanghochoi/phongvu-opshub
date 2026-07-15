import 'dart:async';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/realtime_connection_manager.dart';
import '../../../../core/runtime/app_runtime_coordinator.dart';
import 'auth_provider.dart';

/// Keeps the last-known-good access snapshot fresh without polling while the
/// app is backgrounded or before an authenticated route is visible.
class AuthAccessRefreshCoordinator {
  AuthAccessRefreshCoordinator({
    this.refreshTtl = const Duration(minutes: 15),
    DateTime Function()? now,
    RealtimeClient? realtimeClient,
  }) : _now = now ?? DateTime.now {
    _realtimeSubscription = realtimeClient?.events.listen(_handleRealtimeEvent);
  }

  final Duration refreshTtl;
  final DateTime Function() _now;

  AuthProvider? _auth;
  AppRuntimeCoordinator? _runtime;
  Timer? _timer;
  Future<void>? _refreshInFlight;
  StreamSubscription<RealtimeEnvelope>? _realtimeSubscription;
  DateTime? _nextRetryAt;
  int _failureCount = 0;
  String? _userKey;
  bool _disposed = false;
  bool _realtimeInvalidationPending = false;

  void sync(AuthProvider auth, AppRuntimeCoordinator runtime) {
    if (_disposed) return;
    _auth = auth;
    _runtime = runtime;
    final nextUserKey = auth.user?.id ?? auth.user?.email;
    if (_userKey != nextUserKey) {
      _userKey = nextUserKey;
      _nextRetryAt = null;
      _failureCount = 0;
      _realtimeInvalidationPending = false;
    }
    _timer?.cancel();
    _timer = null;
    if (!_isEligible(auth, runtime) || auth.isAccessSyncing) return;

    if (_realtimeInvalidationPending) {
      _startRefresh('realtime_access_changed');
      return;
    }

    final retryAt = _nextRetryAt;
    if (retryAt != null && _now().isBefore(retryAt)) {
      _schedule(
        retryAt.difference(_now()),
        _failureCount > 0 ? 'failure_backoff' : 'refresh_ttl',
      );
      return;
    }

    final lastSyncedAt = auth.accessLastSyncedAt;
    final remaining = lastSyncedAt == null
        ? Duration.zero
        : refreshTtl - _now().difference(lastSyncedAt);
    if (remaining <= Duration.zero) {
      _startRefresh('ttl_expired');
      return;
    }
    _schedule(remaining, 'ttl_timer');
  }

  void _schedule(Duration delay, String reason) {
    _timer = Timer(delay, () => _startRefresh(reason));
    unawaited(
      AppLogger.instance.info(
        'AuthAccessRefresh',
        'Access refresh scheduled',
        context: {'delaySeconds': delay.inSeconds, 'reason': reason},
      ),
    );
  }

  void _startRefresh(String reason) {
    if (_disposed || _refreshInFlight != null) return;
    final auth = _auth;
    final runtime = _runtime;
    if (auth == null || runtime == null || !_isEligible(auth, runtime)) return;
    if (reason == 'realtime_access_changed') {
      _realtimeInvalidationPending = false;
      _nextRetryAt = null;
    }
    final request = _runRefresh(auth, reason);
    _refreshInFlight = request;
    unawaited(
      request.whenComplete(() {
        if (identical(_refreshInFlight, request)) _refreshInFlight = null;
        final currentAuth = _auth;
        final currentRuntime = _runtime;
        if (!_disposed && currentAuth != null && currentRuntime != null) {
          sync(currentAuth, currentRuntime);
        }
      }),
    );
  }

  void _handleRealtimeEvent(RealtimeEnvelope event) {
    final kind = event.kind.trim().toUpperCase();
    final topic = event.topic.trim().toLowerCase();
    if (kind != 'ACCESS_CHANGED' || topic != 'access.changed') {
      return;
    }
    _realtimeInvalidationPending = true;
    _nextRetryAt = null;
    unawaited(
      AppLogger.instance.info(
        'AuthAccessRefresh',
        'Access refresh requested by realtime invalidation',
        context: {
          'eventId': event.id,
          'kind': event.kind,
          'topic': event.topic,
        },
      ),
    );
    _startRefresh('realtime_access_changed');
  }

  Future<void> _runRefresh(AuthProvider auth, String reason) async {
    await AppLogger.instance.info(
      'AuthAccessRefresh',
      'Access refresh requested by lifecycle',
      context: {'reason': reason},
    );
    final succeeded = await auth.retryAccessSync();
    if (succeeded) {
      _failureCount = 0;
      _nextRetryAt = _now().add(refreshTtl);
    } else {
      _failureCount += 1;
      final delays = <Duration>[
        const Duration(minutes: 1),
        const Duration(minutes: 2),
        const Duration(minutes: 5),
        const Duration(minutes: 15),
      ];
      final index = _failureCount > delays.length
          ? delays.length - 1
          : _failureCount - 1;
      _nextRetryAt = _now().add(delays[index]);
    }
    await AppLogger.instance.info(
      'AuthAccessRefresh',
      'Access refresh lifecycle request completed',
      context: {'reason': reason, 'succeeded': succeeded},
    );
  }

  bool _isEligible(AuthProvider auth, AppRuntimeCoordinator runtime) =>
      auth.isInitialized &&
      auth.isAuthenticated &&
      runtime.isForeground &&
      runtime.hasAuthenticatedRoute;

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _auth = null;
    _runtime = null;
    _userKey = null;
    unawaited(_realtimeSubscription?.cancel());
    _realtimeSubscription = null;
  }
}
