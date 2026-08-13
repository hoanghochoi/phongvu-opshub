part of 'payment_monitor_provider.dart';

typedef PaymentMonitorSpeakerQueueSilence =
    Future<void> Function(
      PaymentNotification notification,
      String clientId, {
      required String reason,
    });

typedef PaymentMonitorSpeakerQueuePlay =
    Future<void> Function(PaymentNotification notification, String clientId);

/// Owns stream delivery ordering and local dedupe/lease state. Audio
/// preparation and playback remain provider callbacks until the next slice.
class PaymentMonitorSpeakerQueue {
  final bool Function(int generation) _isCurrentOperation;
  final bool Function() _canUseSpeaker;
  final bool Function() _isSpeakerEnabled;
  final int Function() _currentGeneration;
  final String Function() _eligibilityReason;
  final PaymentMonitorSpeakerQueueSilence _onSilence;
  final PaymentMonitorSpeakerQueuePlay _onPlay;

  final Set<String> _deliveryInFlightNotificationIds = {};
  final Set<String> _terminalNotificationIds = {};
  final Set<String> _queuedNotificationIds = {};
  final Set<String> _activeNotificationIds = {};
  final Queue<PaymentNotification> _queue = Queue<PaymentNotification>();
  bool _isDraining = false;

  PaymentMonitorSpeakerQueue({
    required bool Function(int generation) isCurrentOperation,
    required bool Function() canUseSpeaker,
    required bool Function() isSpeakerEnabled,
    required int Function() currentGeneration,
    required String Function() eligibilityReason,
    required PaymentMonitorSpeakerQueueSilence onSilence,
    required PaymentMonitorSpeakerQueuePlay onPlay,
  }) : _isCurrentOperation = isCurrentOperation,
       _canUseSpeaker = canUseSpeaker,
       _isSpeakerEnabled = isSpeakerEnabled,
       _currentGeneration = currentGeneration,
       _eligibilityReason = eligibilityReason,
       _onSilence = onSilence,
       _onPlay = onPlay;

  bool isTerminal(String notificationId) =>
      _terminalNotificationIds.contains(notificationId);

  bool isQueued(String notificationId) =>
      _queuedNotificationIds.contains(notificationId);

  bool isActive(String notificationId) =>
      _activeNotificationIds.contains(notificationId);

  bool isInFlight(String notificationId) =>
      _deliveryInFlightNotificationIds.contains(notificationId);

  Set<String> get deliveryInFlightNotificationIds =>
      _deliveryInFlightNotificationIds;
  Set<String> get terminalNotificationIds => _terminalNotificationIds;
  Set<String> get queuedNotificationIds => _queuedNotificationIds;
  Set<String> get activeNotificationIds => _activeNotificationIds;

  bool acquireDeliveryLock(String notificationId) =>
      _deliveryInFlightNotificationIds.add(notificationId);

  void releaseDeliveryLock(String notificationId) {
    _deliveryInFlightNotificationIds.remove(notificationId);
  }

  void activate(String notificationId) {
    _activeNotificationIds.add(notificationId);
  }

  void deactivate(String notificationId) {
    _activeNotificationIds.remove(notificationId);
  }

  void markTerminal(String notificationId) {
    _terminalNotificationIds.add(notificationId);
  }

  void clear() {
    _deliveryInFlightNotificationIds.clear();
    _terminalNotificationIds.clear();
    _queuedNotificationIds.clear();
    _activeNotificationIds.clear();
    _queue.clear();
    _isDraining = false;
  }

  void enqueue(PaymentNotification notification, String clientId) {
    final notificationId = notification.notificationId;
    final isTerminalValue = isTerminal(notificationId);
    final isQueuedValue = isQueued(notificationId);
    final isActiveValue = isActive(notificationId);
    final isInFlightValue = isInFlight(notificationId);
    if (isTerminalValue || isQueuedValue || isActiveValue || isInFlightValue) {
      unawaited(
        AppLogger.instance.info(
          'PaymentSpeaker',
          'Payment speaker stream notification ignored because delivery is already in flight locally',
          context: {
            'notificationId': notificationId,
            'transactionId': notification.transactionId,
            'storeCode': notification.storeCode,
            'clientId': clientId,
            'deliveryPath': 'stream',
            'triggerSource': 'realtime_stream',
            'dedupeHit': true,
            'terminal': isTerminalValue,
            'queued': isQueuedValue,
            'active': isActiveValue,
            'inFlight': isInFlightValue,
          },
        ),
      );
      return;
    }
    _queuedNotificationIds.add(notificationId);
    _queue.add(notification);
    unawaited(
      AppLogger.instance.info(
        'PaymentMonitor',
        'Payment speaker stream notification queued',
        context: {
          'notificationId': notificationId,
          'transactionId': notification.transactionId,
          'storeCode': notification.storeCode,
          'queueLength': _queue.length,
        },
      ),
    );
    unawaited(_drain(clientId));
  }

  Future<void> _drain(String clientId) async {
    if (_isDraining) return;
    final speakerGeneration = _currentGeneration();
    _isDraining = true;
    try {
      while (_queue.isNotEmpty && _isCurrentOperation(speakerGeneration)) {
        final notification = _queue.removeFirst();
        final notificationId = notification.notificationId;
        _queuedNotificationIds.remove(notificationId);
        final ownsDeliveryLock = acquireDeliveryLock(notificationId);
        if (isTerminal(notificationId) ||
            isActive(notificationId) ||
            !ownsDeliveryLock) {
          if (ownsDeliveryLock) releaseDeliveryLock(notificationId);
          continue;
        }
        if (!_canUseSpeaker()) {
          await AppLogger.instance.info(
            'PaymentMonitor',
            'Queued payment stream skipped because speaker became unavailable',
            context: {
              'notificationId': notificationId,
              'transactionId': notification.transactionId,
              'storeCode': notification.storeCode,
              'reason': _eligibilityReason(),
            },
          );
          releaseDeliveryLock(notificationId);
          continue;
        }
        if (!_isSpeakerEnabled()) {
          await _onSilence(
            notification,
            clientId,
            reason: 'speaker_disabled_after_queue',
          );
          releaseDeliveryLock(notificationId);
          continue;
        }
        activate(notificationId);
        try {
          await _onPlay(notification, clientId);
          if (!_isCurrentOperation(speakerGeneration)) return;
        } finally {
          deactivate(notificationId);
          releaseDeliveryLock(notificationId);
        }
      }
    } finally {
      _isDraining = false;
    }
  }
}
