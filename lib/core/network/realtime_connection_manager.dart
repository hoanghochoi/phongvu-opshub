import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../logging/app_logger.dart';
import 'realtime_ticket_client.dart';

enum RealtimeSyncReason { reconnected, appResumed }

class RealtimeEnvelope {
  const RealtimeEnvelope({
    required this.version,
    required this.kind,
    required this.id,
    required this.topic,
    required this.sequence,
    required this.timestamp,
    required this.data,
  });

  final int version;
  final String kind;
  final String id;
  final String topic;
  final int sequence;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  factory RealtimeEnvelope.parse(Object? rawMessage) {
    final rawText = switch (rawMessage) {
      String value => value,
      List<int> value => utf8.decode(value),
      _ => throw const FormatException('Realtime message is not text'),
    };
    final decoded = jsonDecode(rawText);
    if (decoded is! Map) {
      throw const FormatException('Realtime envelope is not an object');
    }
    final payload = Map<String, dynamic>.from(decoded);
    final version = _intOf(payload['v']);
    final kind = payload['kind']?.toString().trim() ?? '';
    final id = payload['id']?.toString().trim() ?? '';
    final topic = payload['topic']?.toString().trim() ?? '';
    final sequence = _intOf(payload['seq']);
    final timestamp = DateTime.tryParse(payload['ts']?.toString() ?? '');
    final rawData = payload['data'];
    if (version != 2 ||
        kind.isEmpty ||
        id.isEmpty ||
        topic.isEmpty ||
        sequence < 0 ||
        timestamp == null ||
        rawData is! Map) {
      throw const FormatException('Realtime envelope is invalid');
    }
    return RealtimeEnvelope(
      version: version,
      kind: kind,
      id: id,
      topic: topic,
      sequence: sequence,
      timestamp: timestamp,
      data: Map<String, dynamic>.from(rawData),
    );
  }

  static int _intOf(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? -1;
  }
}

abstract interface class RealtimeClient {
  Stream<RealtimeEnvelope> get events;
  Stream<RealtimeSyncReason> get syncRequests;
  Future<void> syncSession(String? sessionKey);
}

abstract interface class RealtimeBackgroundConnectionLease {
  void release();
}

abstract interface class RealtimeBackgroundConnectionController {
  Stream<RealtimeEnvelope> get backgroundSpeakerEvents;
  Stream<RealtimeSyncReason> get backgroundSpeakerSyncRequests;
  RealtimeBackgroundConnectionLease acquireBackgroundConnection(String owner);
}

abstract interface class RealtimeConnection {
  Future<void> get ready;
  Stream<dynamic> get stream;
  Future<void> close();
}

typedef RealtimeConnector = RealtimeConnection Function(Uri uri);
typedef RealtimeUriIssuer = Future<Uri> Function();
typedef RealtimeRandomDouble = double Function();

class WebSocketRealtimeConnection implements RealtimeConnection {
  WebSocketRealtimeConnection._(this._channel);

  factory WebSocketRealtimeConnection.connect(Uri uri) {
    return WebSocketRealtimeConnection._(WebSocketChannel.connect(uri));
  }

  final WebSocketChannel _channel;

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  Future<void> close() async {
    await _channel.sink.close();
  }
}

/// Owns the authenticated application socket. Feature providers subscribe to
/// typed events instead of opening another connection for each screen.
class RealtimeConnectionManager
    with WidgetsBindingObserver
    implements RealtimeClient, RealtimeBackgroundConnectionController {
  RealtimeConnectionManager({
    RealtimeUriIssuer? issueConnectionUri,
    RealtimeConnector? connector,
    Duration readyTimeout = const Duration(seconds: 10),
    Duration stableConnectionWindow = const Duration(seconds: 30),
    RealtimeRandomDouble? randomDouble,
    List<Duration> reconnectDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 30),
    ],
  }) : _issueConnectionUri =
           issueConnectionUri ??
           RealtimeTicketClient.instance.issueV2ConnectionUri,
       _connector = connector ?? WebSocketRealtimeConnection.connect,
       _readyTimeout = readyTimeout,
       _stableConnectionWindow = stableConnectionWindow,
       _randomDouble = randomDouble ?? math.Random().nextDouble,
       _reconnectDelays = List.unmodifiable(reconnectDelays);

  static final RealtimeConnectionManager instance = RealtimeConnectionManager();

  static const int _seenEventLimit = 512;

  final RealtimeUriIssuer _issueConnectionUri;
  final RealtimeConnector _connector;
  final Duration _readyTimeout;
  final Duration _stableConnectionWindow;
  final RealtimeRandomDouble _randomDouble;
  final List<Duration> _reconnectDelays;
  final StreamController<RealtimeEnvelope> _eventController =
      StreamController<RealtimeEnvelope>.broadcast();
  final StreamController<RealtimeSyncReason> _syncController =
      StreamController<RealtimeSyncReason>.broadcast();
  final StreamController<RealtimeEnvelope> _backgroundSpeakerEventController =
      StreamController<RealtimeEnvelope>.broadcast();
  final StreamController<RealtimeSyncReason> _backgroundSpeakerSyncController =
      StreamController<RealtimeSyncReason>.broadcast();
  final LinkedHashSet<String> _seenEventIds = LinkedHashSet<String>();
  final Map<String, int> _lastSequenceByTopic = <String, int>{};
  final LinkedHashMap<String, RealtimeEnvelope> _deferredForegroundEvents =
      LinkedHashMap<String, RealtimeEnvelope>();
  final Map<int, String> _backgroundConnectionLeases = <int, String>{};

  String? _sessionKey;
  RealtimeConnection? _connection;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _stableConnectionTimer;
  bool _active = false;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  bool _foregroundConnectionAllowed = true;
  int? _connectingGeneration;
  bool _hasConnected = false;
  bool _observingLifecycle = false;
  bool _isShutdown = false;
  int _generation = 0;
  int _reconnectAttempt = 0;
  int _nextBackgroundConnectionLeaseId = 0;

  @override
  Stream<RealtimeEnvelope> get events => _eventController.stream;

  @override
  Stream<RealtimeSyncReason> get syncRequests => _syncController.stream;

  @override
  Stream<RealtimeEnvelope> get backgroundSpeakerEvents =>
      _backgroundSpeakerEventController.stream;

  @override
  Stream<RealtimeSyncReason> get backgroundSpeakerSyncRequests =>
      _backgroundSpeakerSyncController.stream;

  bool get isConnected => _connection != null && _connectingGeneration == null;

  bool get _canMaintainConnection =>
      _lifecycleState != AppLifecycleState.detached &&
      (_foregroundConnectionAllowed || _backgroundConnectionLeases.isNotEmpty);

  @visibleForTesting
  int get backgroundConnectionRequirementCount =>
      _backgroundConnectionLeases.length;

  @override
  RealtimeBackgroundConnectionLease acquireBackgroundConnection(String owner) {
    final normalizedOwner = owner.trim();
    if (normalizedOwner.isEmpty) {
      throw ArgumentError.value(owner, 'owner', 'must not be empty');
    }
    if (_isShutdown) return _NoopRealtimeBackgroundConnectionLease();

    final leaseId = ++_nextBackgroundConnectionLeaseId;
    _backgroundConnectionLeases[leaseId] = normalizedOwner;
    _handleBackgroundConnectionRequirementsChanged(
      owner: normalizedOwner,
      action: 'acquired',
    );
    return _ManagedRealtimeBackgroundConnectionLease(
      () => _releaseBackgroundConnection(leaseId),
    );
  }

  void _releaseBackgroundConnection(int leaseId) {
    if (_isShutdown) return;
    final owner = _backgroundConnectionLeases.remove(leaseId);
    if (owner == null) return;
    _handleBackgroundConnectionRequirementsChanged(
      owner: owner,
      action: 'released',
    );
  }

  void _handleBackgroundConnectionRequirementsChanged({
    required String owner,
    required String action,
  }) {
    final canMaintainConnection = _canMaintainConnection;
    unawaited(
      AppLogger.instance.info(
        'RealtimeV2',
        'Realtime background connection requirement changed',
        context: {
          'owner': owner,
          'action': action,
          'requirementCount': _backgroundConnectionLeases.length,
          'lifecycleState': _lifecycleState.name,
          'connected': _connection != null,
          'connectionAllowed': canMaintainConnection,
        },
      ),
    );
    if (!_active) return;
    if (!canMaintainConnection) {
      _cancelConnectionTimers();
      unawaited(_disconnectCurrent('background_requirement_released'));
      return;
    }
    if (_connection == null && _connectingGeneration == null) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      unawaited(_connect(_generation, isReconnect: _hasConnected));
    }
  }

  @override
  Future<void> syncSession(String? sessionKey) async {
    if (_isShutdown) return;
    final normalizedSessionKey = sessionKey?.trim();
    final nextSessionKey = normalizedSessionKey?.isNotEmpty == true
        ? normalizedSessionKey
        : null;
    if (_sessionKey == nextSessionKey &&
        ((_active && nextSessionKey != null) ||
            (!_active && nextSessionKey == null))) {
      return;
    }

    _generation += 1;
    final generation = _generation;
    // A ticket/socket attempt from the previous session may still be awaiting
    // I/O. Release only that generation's ownership so the new session can
    // connect immediately; the old attempt will fail its generation checks.
    _connectingGeneration = null;
    _active = nextSessionKey != null;
    _sessionKey = nextSessionKey;
    _hasConnected = false;
    _reconnectAttempt = 0;
    _stableConnectionTimer?.cancel();
    _stableConnectionTimer = null;
    _seenEventIds.clear();
    _lastSequenceByTopic.clear();
    _deferredForegroundEvents.clear();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _disconnectCurrent('session_changed');

    if (!_active || generation != _generation) {
      _stopObservingLifecycle();
      await AppLogger.instance.info(
        'RealtimeV2',
        'Realtime session stopped',
        context: {'reason': 'signed_out'},
      );
      return;
    }

    _startObservingLifecycle();
    if (_canMaintainConnection) {
      unawaited(_connect(generation, isReconnect: false));
    }
  }

  Future<void> _connect(int generation, {required bool isReconnect}) async {
    if (!_active ||
        _isShutdown ||
        !_canMaintainConnection ||
        generation != _generation ||
        _connectingGeneration != null ||
        _connection != null) {
      return;
    }
    _connectingGeneration = generation;
    final startedAt = DateTime.now();
    await AppLogger.instance.info(
      'RealtimeV2',
      'Realtime connection started',
      context: {
        'reconnect': isReconnect,
        'attempt': isReconnect ? _reconnectAttempt : 0,
      },
    );
    RealtimeConnection? connection;
    try {
      final uri = await _issueConnectionUri();
      if (!_active ||
          !_canMaintainConnection ||
          generation != _generation ||
          _isShutdown) {
        return;
      }
      connection = _connector(uri);
      _connection = connection;
      _subscription = connection.stream.listen(
        _handleMessage,
        onError: (Object error, StackTrace stackTrace) {
          unawaited(
            AppLogger.instance.error(
              'RealtimeV2',
              'Realtime stream failed',
              error: error,
              stackTrace: stackTrace,
            ),
          );
          scheduleMicrotask(() {
            unawaited(
              _handleDisconnect(
                connection!,
                generation,
                reason: 'stream_error',
              ),
            );
          });
        },
        onDone: () {
          scheduleMicrotask(() {
            unawaited(
              _handleDisconnect(
                connection!,
                generation,
                reason: 'server_closed',
                streamEnded: true,
              ),
            );
          });
        },
      );
      await connection.ready.timeout(_readyTimeout);
      if (!identical(connection, _connection) ||
          !_active ||
          !_canMaintainConnection ||
          generation != _generation ||
          _isShutdown) {
        return;
      }
      final shouldRequestSync = _hasConnected;
      _hasConnected = true;
      _scheduleStableConnectionReset(generation, connection);
      await AppLogger.instance.info(
        'RealtimeV2',
        'Realtime connection succeeded',
        context: {
          'reconnect': isReconnect,
          'host': uri.host,
          'path': uri.path,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (shouldRequestSync) _requestReconnectSync();
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'RealtimeV2',
        'Realtime connection failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'reconnect': isReconnect,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (connection != null && identical(connection, _connection)) {
        await _handleDisconnect(
          connection,
          generation,
          reason: 'connect_failed',
        );
      } else if (_active && generation == _generation) {
        _scheduleReconnect(generation);
      }
    } finally {
      if (_connectingGeneration == generation) {
        _connectingGeneration = null;
      }
    }
  }

  void _handleMessage(dynamic rawMessage) {
    try {
      final envelope = RealtimeEnvelope.parse(rawMessage);
      final hasDurableSequence = envelope.topic == 'home.summary';
      final lastSequence = hasDurableSequence
          ? _lastSequenceByTopic[envelope.topic]
          : null;
      if (lastSequence != null && envelope.sequence < lastSequence) {
        unawaited(
          AppLogger.instance.info(
            'RealtimeV2',
            'Realtime event ignored out of order',
            context: {
              'eventId': envelope.id,
              'kind': envelope.kind,
              'topic': envelope.topic,
              'sequence': envelope.sequence,
              'lastSequence': lastSequence,
            },
          ),
        );
        return;
      }
      if (hasDurableSequence &&
          (lastSequence == null || envelope.sequence > lastSequence)) {
        _lastSequenceByTopic[envelope.topic] = envelope.sequence;
      }
      if (!_seenEventIds.add(envelope.id)) {
        unawaited(
          AppLogger.instance.info(
            'RealtimeV2',
            'Realtime event deduplicated',
            context: {
              'eventId': envelope.id,
              'kind': envelope.kind,
              'topic': envelope.topic,
              'sequence': envelope.sequence,
            },
          ),
        );
        return;
      }
      if (_seenEventIds.length > _seenEventLimit) {
        _seenEventIds.remove(_seenEventIds.first);
      }
      _routeEnvelope(envelope);
    } catch (error) {
      unawaited(
        AppLogger.instance.warn(
          'RealtimeV2',
          'Realtime event ignored',
          context: {'errorType': error.runtimeType.toString()},
        ),
      );
    }
  }

  void _routeEnvelope(RealtimeEnvelope envelope) {
    if (_lifecycleState == AppLifecycleState.resumed) {
      if (!_eventController.isClosed) _eventController.add(envelope);
      return;
    }
    final isBackgroundSpeakerEvent =
        envelope.kind == 'PAYMENT_SPEAKER_STREAM' &&
        envelope.topic == 'payment.speaker';
    if (isBackgroundSpeakerEvent) {
      if (_backgroundConnectionLeases.isNotEmpty &&
          _lifecycleState != AppLifecycleState.detached &&
          !_backgroundSpeakerEventController.isClosed) {
        _backgroundSpeakerEventController.add(envelope);
      }
      return;
    }
    if (_lifecycleState == AppLifecycleState.detached) return;
    _deferredForegroundEvents[envelope.id] = envelope;
    if (_deferredForegroundEvents.length > _seenEventLimit) {
      _deferredForegroundEvents.remove(_deferredForegroundEvents.keys.first);
    }
    unawaited(
      AppLogger.instance.info(
        'RealtimeV2',
        'Realtime UI event deferred outside resumed lifecycle',
        context: {
          'eventId': envelope.id,
          'kind': envelope.kind,
          'topic': envelope.topic,
          'lifecycleState': _lifecycleState.name,
          'pendingCount': _deferredForegroundEvents.length,
        },
      ),
    );
  }

  void _requestReconnectSync() {
    if (_lifecycleState == AppLifecycleState.resumed) {
      if (!_syncController.isClosed) {
        _syncController.add(RealtimeSyncReason.reconnected);
      }
      return;
    }
    if (_backgroundConnectionLeases.isNotEmpty &&
        _lifecycleState != AppLifecycleState.detached &&
        !_backgroundSpeakerSyncController.isClosed) {
      _backgroundSpeakerSyncController.add(RealtimeSyncReason.reconnected);
    }
  }

  void _drainDeferredForegroundEvents() {
    if (_deferredForegroundEvents.isEmpty || _eventController.isClosed) return;
    final pending = _deferredForegroundEvents.values.toList(growable: false);
    _deferredForegroundEvents.clear();
    for (final envelope in pending) {
      _eventController.add(envelope);
    }
    unawaited(
      AppLogger.instance.info(
        'RealtimeV2',
        'Deferred realtime UI events released on resume',
        context: {'eventCount': pending.length},
      ),
    );
  }

  Future<void> _handleDisconnect(
    RealtimeConnection expectedConnection,
    int generation, {
    required String reason,
    bool streamEnded = false,
  }) async {
    if (!identical(expectedConnection, _connection)) return;
    _stableConnectionTimer?.cancel();
    _stableConnectionTimer = null;
    await _disconnectCurrent(reason, cancelSubscription: !streamEnded);
    if (_active && generation == _generation && !_isShutdown) {
      _scheduleReconnect(generation);
    }
  }

  Future<void> _disconnectCurrent(
    String reason, {
    bool cancelSubscription = true,
  }) async {
    final connection = _connection;
    final subscription = _subscription;
    _connection = null;
    _subscription = null;
    if (subscription != null && cancelSubscription) {
      await subscription.cancel();
    }
    if (connection != null) {
      try {
        await connection.close();
      } catch (_) {
        // The socket may already be closed by the server.
      }
      await AppLogger.instance.info(
        'RealtimeV2',
        'Realtime connection closed',
        context: {'reason': reason},
      );
    }
  }

  void _scheduleReconnect(int generation) {
    if (!_active ||
        _isShutdown ||
        !_canMaintainConnection ||
        generation != _generation ||
        _reconnectTimer?.isActive == true ||
        _reconnectDelays.isEmpty) {
      return;
    }
    final delayIndex = _reconnectAttempt < _reconnectDelays.length
        ? _reconnectAttempt
        : _reconnectDelays.length - 1;
    final delayCap = _reconnectDelays[delayIndex];
    final jitter = _randomDouble().clamp(0.0, 1.0);
    final delay = Duration(
      milliseconds: (delayCap.inMilliseconds * jitter).floor(),
    );
    _reconnectAttempt += 1;
    unawaited(
      AppLogger.instance.info(
        'RealtimeV2',
        'Realtime reconnect scheduled',
        context: {
          'attempt': _reconnectAttempt,
          'delayMs': delay.inMilliseconds,
          'delayCapMs': delayCap.inMilliseconds,
        },
      ),
    );
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      unawaited(_connect(generation, isReconnect: true));
    });
  }

  void _scheduleStableConnectionReset(
    int generation,
    RealtimeConnection connection,
  ) {
    _stableConnectionTimer?.cancel();
    if (_stableConnectionWindow <= Duration.zero) {
      _reconnectAttempt = 0;
      return;
    }
    _stableConnectionTimer = Timer(_stableConnectionWindow, () {
      _stableConnectionTimer = null;
      if (!_active ||
          _isShutdown ||
          generation != _generation ||
          !identical(connection, _connection)) {
        return;
      }
      final previousAttempt = _reconnectAttempt;
      _reconnectAttempt = 0;
      unawaited(
        AppLogger.instance.info(
          'RealtimeV2',
          'Realtime reconnect backoff reset after stable connection',
          context: {
            'stableWindowSeconds': _stableConnectionWindow.inSeconds,
            'previousAttempt': previousAttempt,
          },
        ),
      );
    });
  }

  void handleAppResumed() {
    _lifecycleState = AppLifecycleState.resumed;
    _foregroundConnectionAllowed = true;
    if (!_active || _isShutdown) return;
    _drainDeferredForegroundEvents();
    unawaited(
      AppLogger.instance.info(
        'RealtimeV2',
        'App resumed; one-shot realtime sync requested',
        context: {'connected': _connection != null},
      ),
    );
    if (!_syncController.isClosed) {
      _syncController.add(RealtimeSyncReason.appResumed);
    }
    if (_connection == null && _connectingGeneration == null) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      unawaited(_connect(_generation, isReconnect: true));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      handleAppResumed();
      return;
    }
    _handleAppBackgrounded(state);
  }

  void _handleAppBackgrounded(AppLifecycleState state) {
    if (_isShutdown) return;
    final previousState = _lifecycleState;
    _lifecycleState = state;
    if (state != AppLifecycleState.inactive) {
      _foregroundConnectionAllowed = false;
    }
    if (_canMaintainConnection) {
      final retentionReason = _backgroundConnectionLeases.isNotEmpty
          ? 'background_requirement'
          : 'inactive_compatibility';
      unawaited(
        AppLogger.instance.info(
          'RealtimeV2',
          'Authenticated realtime retained outside resumed lifecycle',
          context: {
            'fromState': previousState.name,
            'state': state.name,
            'reason': retentionReason,
            'connected': _connection != null,
            'requirementCount': _backgroundConnectionLeases.length,
          },
        ),
      );
      if (_active &&
          _connection == null &&
          _connectingGeneration == null &&
          _reconnectTimer?.isActive != true) {
        unawaited(_connect(_generation, isReconnect: _hasConnected));
      }
      return;
    }
    _cancelConnectionTimers();
    unawaited(
      AppLogger.instance.info(
        'RealtimeV2',
        'App backgrounded; authenticated realtime paused',
        context: {
          'fromState': previousState.name,
          'state': state.name,
          'connected': _connection != null,
          'requirementCount': _backgroundConnectionLeases.length,
        },
      ),
    );
    unawaited(_disconnectCurrent('app_backgrounded'));
  }

  void _cancelConnectionTimers() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stableConnectionTimer?.cancel();
    _stableConnectionTimer = null;
  }

  void _startObservingLifecycle() {
    if (_observingLifecycle) return;
    WidgetsBinding.instance.addObserver(this);
    _observingLifecycle = true;
  }

  void _stopObservingLifecycle() {
    if (!_observingLifecycle) return;
    WidgetsBinding.instance.removeObserver(this);
    _observingLifecycle = false;
  }

  Future<void> shutdown() async {
    if (_isShutdown) return;
    _isShutdown = true;
    _active = false;
    _generation += 1;
    _connectingGeneration = null;
    _backgroundConnectionLeases.clear();
    _cancelConnectionTimers();
    _stopObservingLifecycle();
    await _disconnectCurrent('manager_shutdown');
    await _eventController.close();
    await _syncController.close();
    await _backgroundSpeakerEventController.close();
    await _backgroundSpeakerSyncController.close();
  }
}

class _ManagedRealtimeBackgroundConnectionLease
    implements RealtimeBackgroundConnectionLease {
  _ManagedRealtimeBackgroundConnectionLease(this._onRelease);

  void Function()? _onRelease;

  @override
  void release() {
    final onRelease = _onRelease;
    if (onRelease == null) return;
    _onRelease = null;
    onRelease();
  }
}

class _NoopRealtimeBackgroundConnectionLease
    implements RealtimeBackgroundConnectionLease {
  @override
  void release() {}
}
