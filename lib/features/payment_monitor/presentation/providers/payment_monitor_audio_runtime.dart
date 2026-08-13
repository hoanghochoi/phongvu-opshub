part of 'payment_monitor_provider.dart';

typedef PaymentMonitorAudioAcknowledgeEvent =
    Future<bool> Function({
      required String notificationId,
      required String clientId,
      required String event,
      String? error,
    });

/// Owns the low-level payment notification audio lifecycle.
///
/// The provider remains the public facade and owns queue/authorization state.
/// This coordinator receives all provider state it needs through callbacks so
/// preparation, playback retries and delivery acknowledgements can evolve
/// independently without reaching into provider fields.
class PaymentMonitorAudioRuntime {
  static const _maxAudioPlaybackAttempts = 3;

  static String safeSpeakerError(Object error) {
    final normalized = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 180) return normalized;
    return '${normalized.substring(0, 177)}...';
  }

  final PaymentMonitorRepository _repository;
  final PaymentSpeaker _speaker;
  final PaymentAmountAudioComposer _amountAudioComposer;
  final Duration _playbackRetryDelay;
  final String Function() _voicePresetId;
  final int Function() _currentSpeakerGeneration;
  final bool Function(int generation) _isCurrentSpeakerOperation;
  final PaymentMonitorAudioAcknowledgeEvent _acknowledgeEvent;
  final void Function(String notificationId) _onTerminal;

  PaymentMonitorAudioRuntime({
    required PaymentMonitorRepository repository,
    required PaymentSpeaker speaker,
    required PaymentAmountAudioComposer amountAudioComposer,
    required Duration playbackRetryDelay,
    required String Function() voicePresetId,
    required int Function() currentSpeakerGeneration,
    required bool Function(int generation) isCurrentSpeakerOperation,
    required PaymentMonitorAudioAcknowledgeEvent acknowledgeEvent,
    required void Function(String notificationId) onTerminal,
  }) : _repository = repository,
       _speaker = speaker,
       _amountAudioComposer = amountAudioComposer,
       _playbackRetryDelay = playbackRetryDelay,
       _voicePresetId = voicePresetId,
       _currentSpeakerGeneration = currentSpeakerGeneration,
       _isCurrentSpeakerOperation = isCurrentSpeakerOperation,
       _acknowledgeEvent = acknowledgeEvent,
       _onTerminal = onTerminal;

  Future<bool> playNotificationWithRetry(
    PaymentNotification notification,
    String clientId, {
    bool useStreamEndpoint = false,
    String triggerSource = 'ready_backlog',
  }) async {
    final speakerGeneration = _currentSpeakerGeneration();
    if (!_isCurrentSpeakerOperation(speakerGeneration)) return false;
    if (!useStreamEndpoint && notification.audioStatus != 'READY') {
      throw StateError(
        'Server audio is not ready: ${notification.audioStatus}',
      );
    }

    final deliveryPath = useStreamEndpoint ? 'stream' : 'audio';
    late final _DownloadedPaymentAudio audio;
    try {
      audio = await _downloadNotificationAudio(
        notification,
        clientId: clientId,
        useStreamEndpoint: useStreamEndpoint,
        triggerSource: triggerSource,
      );
      if (!_isCurrentSpeakerOperation(speakerGeneration)) return false;
    } catch (error, stackTrace) {
      if (!_isCurrentSpeakerOperation(speakerGeneration)) return false;
      if (error is _PaymentNotificationDeliverySuppressedException) {
        rethrow;
      }
      final safeError = safeSpeakerError(error);
      await _acknowledgeEvent(
        notificationId: notification.notificationId,
        clientId: clientId,
        event: 'FAILED',
        error: safeError,
      );
      _onTerminal(notification.notificationId);
      await AppLogger.instance.error(
        'PaymentSpeaker',
        'Payment speaker audio download failed before playback could start',
        error: error,
        stackTrace: stackTrace,
        context: {
          'notificationId': notification.notificationId,
          'transactionId': notification.transactionId,
          'storeCode': notification.storeCode,
          'clientId': clientId,
          'deliveryPath': deliveryPath,
          'triggerSource': triggerSource,
        },
      );
      Error.throwWithStackTrace(error, stackTrace);
    }

    var streamStartedAckSent = false;
    Future<void> acknowledgePlaybackStarted() async {
      if (streamStartedAckSent) return;
      if (!_isCurrentSpeakerOperation(speakerGeneration)) return;
      streamStartedAckSent = true;
      await _acknowledgeEvent(
        notificationId: notification.notificationId,
        clientId: clientId,
        event: 'STREAM_STARTED',
      );
    }

    for (var attempt = 1; attempt <= _maxAudioPlaybackAttempts; attempt += 1) {
      if (!_isCurrentSpeakerOperation(speakerGeneration)) return false;
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
          if (audio.voicePresetId != null) 'voicePresetId': audio.voicePresetId,
          'deliveryPath': deliveryPath,
          'triggerSource': triggerSource,
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
              'deliveryPath': deliveryPath,
              'triggerSource': triggerSource,
            },
            storeCode: notification.storeCode,
          ),
        );
        final result = await _playNotificationOnce(
          notification: notification,
          clientId: clientId,
          attempt: attempt,
          audio: audio,
          onPlaybackStarting: acknowledgePlaybackStarted,
        );
        if (!_isCurrentSpeakerOperation(speakerGeneration)) return false;
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
            if (audio.voicePresetId != null)
              'voicePresetId': audio.voicePresetId,
            if (result.sampleRateHz != null)
              'sampleRateHz': result.sampleRateHz,
            if (result.channels != null) 'channels': result.channels,
            if (result.bitsPerSample != null)
              'bitsPerSample': result.bitsPerSample,
            if (result.audioPreflightStatus != null)
              'audioPreflightStatus': result.audioPreflightStatus,
            'startedAt': startedAt.toIso8601String(),
            'deliveryPath': deliveryPath,
            'triggerSource': triggerSource,
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
            if (audio.voicePresetId != null)
              'voicePresetId': audio.voicePresetId,
            if (result.sampleRateHz != null)
              'sampleRateHz': result.sampleRateHz,
            if (result.channels != null) 'channels': result.channels,
            if (result.bitsPerSample != null)
              'bitsPerSample': result.bitsPerSample,
            if (result.audioPreflightStatus != null)
              'audioPreflightStatus': result.audioPreflightStatus,
            'startedAt': startedAt.toIso8601String(),
            'deliveryPath': deliveryPath,
            'triggerSource': triggerSource,
          },
          storeCode: notification.storeCode,
        );
        return true;
      } catch (error, stackTrace) {
        if (!_isCurrentSpeakerOperation(speakerGeneration)) return false;
        final safeError = safeSpeakerError(error);
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
          'deliveryPath': deliveryPath,
          'triggerSource': triggerSource,
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
          await _acknowledgeEvent(
            notificationId: notification.notificationId,
            clientId: clientId,
            event: 'FAILED',
            error: safeError,
          );
          _onTerminal(notification.notificationId);
          Error.throwWithStackTrace(error, stackTrace);
        }

        await _acknowledgeEvent(
          notificationId: notification.notificationId,
          clientId: clientId,
          event: 'PLAYBACK_FAILED',
          error: safeError,
        );
        await Future<void>.delayed(_playbackRetryDelay);
      }
    }
    return false;
  }

  Future<_DownloadedPaymentAudio> _downloadNotificationAudio(
    PaymentNotification notification, {
    required String clientId,
    bool useStreamEndpoint = false,
    String triggerSource = 'ready_backlog',
  }) async {
    final deliveryPath = useStreamEndpoint ? 'stream' : 'audio';
    await AppLogger.instance.info(
      'PaymentMonitor',
      'Preparing payment notification audio',
      context: {
        'notificationId': notification.notificationId,
        'transactionId': notification.transactionId,
        'storeCode': notification.storeCode,
        'amount': notification.amount,
        'clientId': clientId,
        'deliveryPath': deliveryPath,
        'triggerSource': triggerSource,
        'preferredMode':
            useStreamEndpoint && notification.requestsLocalAssetPlayback
            ? 'local_preset_speaker_v1'
            : 'local_preset_required',
      },
    );

    if (!AppPlatformCapabilities.isPaymentSpeakerLocalPresetSupported()) {
      final bytes = useStreamEndpoint
          ? await _repository.downloadNotificationStreamAudio(
              notification.notificationId,
              includeCue: true,
              clientId: clientId,
            )
          : await _repository.downloadNotificationAudio(
              notification.notificationId,
              includeCue: true,
            );
      await _logNotificationAudioPrepared(
        notification: notification,
        clientId: clientId,
        bytes: bytes.length,
        mode: 'server_audio_native',
        deliveryPath: deliveryPath,
        triggerSource: triggerSource,
      );
      return _DownloadedPaymentAudio(
        bytes: bytes,
        playLocalCue: false,
        playLocalCuePrefix: false,
        mode: 'server_audio_native',
      );
    }

    if (!useStreamEndpoint || !notification.requestsLocalAssetPlayback) {
      throw StateError(
        'Payment speaker requires a LOCAL_ASSET realtime notification',
      );
    }
    try {
      final assetPackVersion = notification.assetPackVersion!.trim();
      final composed = await _amountAudioComposer.compose(
        amount: notification.amount,
        assetPackVersion: assetPackVersion,
        voicePresetId: _voicePresetId(),
      );
      await _repository.claimNotificationForLocalPlayback(
        notification.notificationId,
        clientId: clientId,
      );
      await _logNotificationAudioPrepared(
        notification: notification,
        clientId: clientId,
        bytes: composed.bytes.length,
        mode: 'local_preset_speaker_v1',
        deliveryPath: deliveryPath,
        triggerSource: triggerSource,
      );
      return _DownloadedPaymentAudio(
        bytes: composed.bytes,
        localPrefixBytes: composed.prefixBytes,
        voicePresetId: composed.voicePresetId,
        playLocalCue: false,
        playLocalCuePrefix: true,
        mode: 'local_preset_speaker_v1',
      );
    } catch (error, stackTrace) {
      if (error is api.ApiException &&
          (error.statusCode == 401 || error.statusCode == 403)) {
        rethrow;
      }
      if (error is api.ApiException && error.statusCode == 409) {
        throw _PaymentNotificationDeliverySuppressedException(
          _streamSuppressedReason(error),
          safeSpeakerError(error),
        );
      }
      final safeError = safeSpeakerError(error);
      await AppLogger.instance.error(
        'PaymentMonitor',
        'Offline payment preset is unavailable; server audio is disabled',
        error: error,
        stackTrace: stackTrace,
        context: {
          'notificationId': notification.notificationId,
          'transactionId': notification.transactionId,
          'storeCode': notification.storeCode,
          'amount': notification.amount,
          'clientId': clientId,
          'assetPackVersion': notification.assetPackVersion,
          'deliveryPath': deliveryPath,
          'triggerSource': triggerSource,
          'audioMode': 'local_preset_failed',
          'error': safeError,
          'stackTrace': stackTrace.toString(),
        },
      );
      await AppLogger.instance.uploadLog(
        'error',
        'PaymentMonitor',
        'Offline payment preset is unavailable; server audio is disabled',
        context: {
          'notificationId': notification.notificationId,
          'transactionId': notification.transactionId,
          'amount': notification.amount,
          'assetPackVersion': notification.assetPackVersion,
          'deliveryPath': deliveryPath,
          'triggerSource': triggerSource,
          'audioMode': 'local_preset_failed',
          'error': safeError,
        },
        storeCode: notification.storeCode,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _logNotificationAudioPrepared({
    required PaymentNotification notification,
    required String clientId,
    required int bytes,
    required String mode,
    required String deliveryPath,
    required String triggerSource,
  }) async {
    await AppLogger.instance.info(
      'PaymentMonitor',
      'Payment notification audio prepared',
      context: {
        'notificationId': notification.notificationId,
        'clientId': clientId,
        'bytes': bytes,
        'audioMode': mode,
        'deliveryPath': deliveryPath,
        'triggerSource': triggerSource,
      },
    );
    await AppLogger.instance.uploadLog(
      'info',
      'PaymentMonitor',
      'Payment notification audio prepared',
      context: {
        'notificationId': notification.notificationId,
        'clientId': clientId,
        'bytes': bytes,
        'audioMode': mode,
        'deliveryPath': deliveryPath,
        'triggerSource': triggerSource,
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
  }) {
    return _speaker.playServerAudio(
      amount: notification.amount,
      audioBytes: audio.bytes,
      notificationId: notification.notificationId,
      transactionId: notification.transactionId,
      storeCode: notification.storeCode,
      clientId: clientId,
      attempt: attempt,
      localPrefixBytes: audio.localPrefixBytes,
      playLocalCue: audio.playLocalCue,
      playLocalCuePrefix: audio.playLocalCuePrefix,
      onPlaybackStarting: onPlaybackStarting,
    );
  }

  String buildSpeakerErrorMessage(String safeError) {
    final lower = safeError.toLowerCase();
    if (lower.contains('audio output device') ||
        lower.contains('waveoutdevices=0') ||
        lower.contains('no wave device')) {
      return 'Windows không nhận thiết bị âm thanh. Kiểm tra loa/audio driver rồi bấm Khởi động lại app. Lỗi: $safeError';
    }
    return 'Không phát được loa sau $_maxAudioPlaybackAttempts lần thử. '
        'Bấm Khởi động lại app rồi thử lại. Lỗi: $safeError';
  }
}

class _DownloadedPaymentAudio {
  final List<int> bytes;
  final List<int>? localPrefixBytes;
  final String? voicePresetId;
  final bool playLocalCue;
  final bool playLocalCuePrefix;
  final String mode;

  const _DownloadedPaymentAudio({
    required this.bytes,
    this.localPrefixBytes,
    this.voicePresetId,
    required this.playLocalCue,
    required this.playLocalCuePrefix,
    required this.mode,
  });
}

class _PaymentNotificationDeliverySuppressedException implements Exception {
  final String reason;
  final String message;

  const _PaymentNotificationDeliverySuppressedException(
    this.reason,
    this.message,
  );

  @override
  String toString() => message;
}

String _streamSuppressedReason(api.ApiException error) {
  final message = error.message.toLowerCase();
  if (message.contains('quá hạn') || message.contains('qua han')) {
    return 'stream_recovery_window_expired';
  }
  return 'duplicate_suppressed';
}
