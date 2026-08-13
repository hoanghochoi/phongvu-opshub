part of 'payment_monitor_provider.dart';

typedef PaymentMonitorRealtimeRefresh =
    void Function({
      required bool drainReadyNotifications,
      required String reason,
    });

typedef PaymentMonitorRealtimeLeaseChanged =
    void Function(String reason, bool acquired);

class PaymentMonitorRealtimeRuntimeChange {
  final bool foregroundChanged;
  final bool speakerBackgroundRuntimeChanged;
  final bool listViewChanged;
  final bool becameListActive;

  const PaymentMonitorRealtimeRuntimeChange({
    required this.foregroundChanged,
    required this.speakerBackgroundRuntimeChanged,
    required this.listViewChanged,
    required this.becameListActive,
  });

  bool get changed =>
      foregroundChanged || speakerBackgroundRuntimeChanged || listViewChanged;
}

/// Owns realtime subscriptions, refresh debounce state and the background
/// speaker lease. The provider remains the behavior facade and supplies the
/// authorization/poll/audio callbacks through the constructor.
class PaymentMonitorRealtimeRuntime {
  static const _backgroundRealtimeOwner = 'payment_speaker';
  static const _realtimeRefreshDebounce = Duration(milliseconds: 500);

  final RealtimeClient _realtimeClient;
  final Future<void> Function(RealtimeEnvelope) _onEnvelope;
  final void Function(RealtimeSyncReason) _onSyncRequest;
  final PaymentMonitorRealtimeRefresh _onRefresh;
  final bool Function() _shouldHoldBackgroundLease;
  final PaymentMonitorRealtimeLeaseChanged _onLeaseChanged;

  StreamSubscription<RealtimeEnvelope>? _realtimeEventSubscription;
  StreamSubscription<RealtimeSyncReason>? _realtimeSyncSubscription;
  StreamSubscription<RealtimeEnvelope>?
  _backgroundSpeakerRealtimeEventSubscription;
  StreamSubscription<RealtimeSyncReason>?
  _backgroundSpeakerRealtimeSyncSubscription;
  Timer? _refreshTimer;
  RealtimeBackgroundConnectionLease? _backgroundRealtimeLease;

  bool _isDisposed = false;
  bool _isForeground = true;
  bool _isSpeakerBackgroundRuntimeAllowed = false;
  bool _isListViewActive = true;
  bool _refreshPending = false;
  bool _refreshShouldDrainReadyNotifications = false;

  PaymentMonitorRealtimeRuntime({
    required RealtimeClient realtimeClient,
    required Future<void> Function(RealtimeEnvelope) onEnvelope,
    required void Function(RealtimeSyncReason) onSyncRequest,
    required PaymentMonitorRealtimeRefresh onRefresh,
    required bool Function() shouldHoldBackgroundLease,
    required PaymentMonitorRealtimeLeaseChanged onLeaseChanged,
  }) : _realtimeClient = realtimeClient,
       _onEnvelope = onEnvelope,
       _onSyncRequest = onSyncRequest,
       _onRefresh = onRefresh,
       _shouldHoldBackgroundLease = shouldHoldBackgroundLease,
       _onLeaseChanged = onLeaseChanged {
    _realtimeEventSubscription = _realtimeClient.events.listen(_onEnvelope);
    _realtimeSyncSubscription = _realtimeClient.syncRequests.listen(
      _onSyncRequest,
    );
    final realtimeClient = _realtimeClient;
    if (realtimeClient is RealtimeBackgroundConnectionController) {
      final backgroundClient =
          realtimeClient as RealtimeBackgroundConnectionController;
      _backgroundSpeakerRealtimeEventSubscription = backgroundClient
          .backgroundSpeakerEvents
          .listen(_onEnvelope);
      _backgroundSpeakerRealtimeSyncSubscription = backgroundClient
          .backgroundSpeakerSyncRequests
          .listen(_onSyncRequest);
    }
  }

  bool get isForeground => _isForeground;
  bool get isSpeakerBackgroundRuntimeAllowed =>
      _isSpeakerBackgroundRuntimeAllowed;
  bool get isListViewActive => _isListViewActive;
  bool get refreshPending => _refreshPending;

  PaymentMonitorRealtimeRuntimeChange syncRuntime({
    required bool isForeground,
    required bool isListViewActive,
    required bool allowBackgroundSpeakerRuntime,
  }) {
    if (_isDisposed) {
      return const PaymentMonitorRealtimeRuntimeChange(
        foregroundChanged: false,
        speakerBackgroundRuntimeChanged: false,
        listViewChanged: false,
        becameListActive: false,
      );
    }
    final change = PaymentMonitorRealtimeRuntimeChange(
      foregroundChanged: _isForeground != isForeground,
      speakerBackgroundRuntimeChanged:
          _isSpeakerBackgroundRuntimeAllowed != allowBackgroundSpeakerRuntime,
      listViewChanged: _isListViewActive != isListViewActive,
      becameListActive: !_isListViewActive && isListViewActive,
    );
    _isForeground = isForeground;
    _isSpeakerBackgroundRuntimeAllowed = allowBackgroundSpeakerRuntime;
    _isListViewActive = isListViewActive;
    if (!isForeground) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
    syncBackgroundLease(reason: 'runtime_changed');
    return change;
  }

  void syncBackgroundLease({required String reason}) {
    if (_isDisposed) return;
    final shouldHold = _shouldHoldBackgroundLease();
    if (shouldHold && _backgroundRealtimeLease == null) {
      final realtimeClient = _realtimeClient;
      if (realtimeClient is RealtimeBackgroundConnectionController) {
        final backgroundClient =
            realtimeClient as RealtimeBackgroundConnectionController;
        _backgroundRealtimeLease = backgroundClient.acquireBackgroundConnection(
          _backgroundRealtimeOwner,
        );
        _onLeaseChanged(reason, true);
      }
      return;
    }
    if (!shouldHold) releaseBackgroundLease(reason);
  }

  void releaseBackgroundLease(String reason) {
    final lease = _backgroundRealtimeLease;
    if (lease == null) return;
    _backgroundRealtimeLease = null;
    lease.release();
    _onLeaseChanged(reason, false);
  }

  void markRefreshPending({bool drainReadyNotifications = false}) {
    if (_isDisposed) return;
    _refreshPending = true;
    _refreshShouldDrainReadyNotifications |= drainReadyNotifications;
  }

  void scheduleRefresh({required bool drainReadyNotifications}) {
    if (_isDisposed) return;
    markRefreshPending(drainReadyNotifications: drainReadyNotifications);
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_realtimeRefreshDebounce, () {
      _refreshTimer = null;
      if (!_isForeground) return;
      final shouldDrainReadyNotifications =
          _refreshShouldDrainReadyNotifications;
      _refreshPending = false;
      _refreshShouldDrainReadyNotifications = false;
      _onRefresh(
        drainReadyNotifications: shouldDrainReadyNotifications,
        reason: _isListViewActive
            ? 'realtime_event'
            : 'realtime_event_inactive_route',
      );
    });
  }

  void clearPendingRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _refreshPending = false;
    _refreshShouldDrainReadyNotifications = false;
  }

  void dispose({String reason = 'runtime_disposed'}) {
    if (_isDisposed) return;
    _isDisposed = true;
    releaseBackgroundLease(reason);
    _refreshTimer?.cancel();
    _refreshTimer = null;
    unawaited(_realtimeEventSubscription?.cancel());
    unawaited(_realtimeSyncSubscription?.cancel());
    unawaited(_backgroundSpeakerRealtimeEventSubscription?.cancel());
    unawaited(_backgroundSpeakerRealtimeSyncSubscription?.cancel());
  }
}
