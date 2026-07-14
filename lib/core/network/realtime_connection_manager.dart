import 'dart:async';
import 'dart:collection';
import 'dart:convert';

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

abstract interface class RealtimeConnection {
  Future<void> get ready;
  Stream<dynamic> get stream;
  Future<void> close();
}

typedef RealtimeConnector = RealtimeConnection Function(Uri uri);
typedef RealtimeUriIssuer = Future<Uri> Function();

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
    implements RealtimeClient {
  RealtimeConnectionManager({
    RealtimeUriIssuer? issueConnectionUri,
    RealtimeConnector? connector,
    Duration readyTimeout = const Duration(seconds: 10),
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
       _reconnectDelays = List.unmodifiable(reconnectDelays);

  static final RealtimeConnectionManager instance = RealtimeConnectionManager();

  static const int _seenEventLimit = 512;

  final RealtimeUriIssuer _issueConnectionUri;
  final RealtimeConnector _connector;
  final Duration _readyTimeout;
  final List<Duration> _reconnectDelays;
  final StreamController<RealtimeEnvelope> _eventController =
      StreamController<RealtimeEnvelope>.broadcast();
  final StreamController<RealtimeSyncReason> _syncController =
      StreamController<RealtimeSyncReason>.broadcast();
  final LinkedHashSet<String> _seenEventIds = LinkedHashSet<String>();

  String? _sessionKey;
  RealtimeConnection? _connection;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  bool _active = false;
  bool _connecting = false;
  bool _hasConnected = false;
  bool _observingLifecycle = false;
  bool _isShutdown = false;
  int _generation = 0;
  int _reconnectAttempt = 0;

  @override
  Stream<RealtimeEnvelope> get events => _eventController.stream;

  @override
  Stream<RealtimeSyncReason> get syncRequests => _syncController.stream;

  bool get isConnected => _connection != null && !_connecting;

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
    _active = nextSessionKey != null;
    _sessionKey = nextSessionKey;
    _hasConnected = false;
    _reconnectAttempt = 0;
    _seenEventIds.clear();
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
    unawaited(_connect(generation, isReconnect: false));
  }

  Future<void> _connect(int generation, {required bool isReconnect}) async {
    if (!_active ||
        _isShutdown ||
        generation != _generation ||
        _connecting ||
        _connection != null) {
      return;
    }
    _connecting = true;
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
      if (!_active || generation != _generation || _isShutdown) return;
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
          generation != _generation ||
          _isShutdown) {
        return;
      }
      _reconnectAttempt = 0;
      final shouldRequestSync = _hasConnected;
      _hasConnected = true;
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
      if (shouldRequestSync && !_syncController.isClosed) {
        _syncController.add(RealtimeSyncReason.reconnected);
      }
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
      if (generation == _generation) _connecting = false;
    }
  }

  void _handleMessage(dynamic rawMessage) {
    try {
      final envelope = RealtimeEnvelope.parse(rawMessage);
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
      if (!_eventController.isClosed) _eventController.add(envelope);
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

  Future<void> _handleDisconnect(
    RealtimeConnection expectedConnection,
    int generation, {
    required String reason,
    bool streamEnded = false,
  }) async {
    if (!identical(expectedConnection, _connection)) return;
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
        generation != _generation ||
        _reconnectTimer?.isActive == true ||
        _reconnectDelays.isEmpty) {
      return;
    }
    final delayIndex = _reconnectAttempt < _reconnectDelays.length
        ? _reconnectAttempt
        : _reconnectDelays.length - 1;
    final delay = _reconnectDelays[delayIndex];
    _reconnectAttempt += 1;
    unawaited(
      AppLogger.instance.info(
        'RealtimeV2',
        'Realtime reconnect scheduled',
        context: {
          'attempt': _reconnectAttempt,
          'delayMs': delay.inMilliseconds,
        },
      ),
    );
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      unawaited(_connect(generation, isReconnect: true));
    });
  }

  void handleAppResumed() {
    if (!_active || _isShutdown) return;
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
    if (_connection == null && !_connecting) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      unawaited(_connect(_generation, isReconnect: true));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) handleAppResumed();
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
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopObservingLifecycle();
    await _disconnectCurrent('manager_shutdown');
    await _eventController.close();
    await _syncController.close();
  }
}
