import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/domain/entities/user.dart';
import '../../data/payment_speaker.dart';
import '../../data/repositories/payment_monitor_repository.dart';
import '../../domain/map_payment_transaction.dart';
import '../../domain/payment_notification.dart';

class PaymentMonitorProvider extends ChangeNotifier {
  static const _pollInterval = Duration(seconds: 5);

  final PaymentMonitorRepository _repository;
  final PaymentSpeaker _speaker;
  final Set<String> _seenTransactionIds = {};
  final Set<String> _seenNotificationIds = {};
  final List<MapPaymentTransaction> _latestTransactions = [];

  Timer? _timer;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;
  User? _user;
  String? _storeOverride;
  String? _clientId;
  bool _isActive = false;
  bool _isLoading = false;
  bool _hasSeeded = false;
  String? _errorMessage;
  DateTime? _lastCheckedAt;

  PaymentMonitorProvider(this._repository, this._speaker);

  bool get isActive => _isActive;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime? get lastCheckedAt => _lastCheckedAt;
  String? get storeOverride => _storeOverride;
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
    _restart();
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
    _hasSeeded = false;
    _seenTransactionIds.clear();
    _seenNotificationIds.clear();
    _latestTransactions.clear();
    _poll();
    unawaited(_connectRealtime());
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
    unawaited(_closeRealtime());
    if (!_isActive &&
        !_isLoading &&
        _latestTransactions.isEmpty &&
        _errorMessage == null) {
      return;
    }
    _isActive = false;
    _isLoading = false;
    _hasSeeded = false;
    _seenTransactionIds.clear();
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
      final transactions = await _repository.fetchStoredTransactions(
        storeId: _requestStoreId,
        limit: 50,
      );
      final sorted = [...transactions]
        ..sort((a, b) {
          final aTime =
              a.firstSeenAt ??
              a.paidAt ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bTime =
              b.firstSeenAt ??
              b.paidAt ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return aTime.compareTo(bTime);
        });

      final newTransactions = <MapPaymentTransaction>[];
      for (final transaction in sorted) {
        if (_seenTransactionIds.add(transaction.id) && _hasSeeded) {
          newTransactions.add(transaction);
        }
      }
      _hasSeeded = true;
      if (newTransactions.isNotEmpty) {
        await AppLogger.instance.info(
          'PaymentMonitor',
          'Stored transaction poll observed new rows; realtime handles audio',
          context: {'count': newTransactions.length},
        );
      }

      _lastCheckedAt = DateTime.now();
      _latestTransactions
        ..clear()
        ..addAll(transactions.take(10));
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      if (_isActive && _channel == null) {
        unawaited(_connectRealtime());
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_closeRealtime());
    super.dispose();
  }

  Future<void> _connectRealtime() async {
    if (_channel != null || !_hasMonitorScope) return;
    final token = ApiClient().authToken;
    if (token == null || token.isEmpty) return;
    final clientId = await _ensureClientId();
    final baseUri = Uri.parse(
      ApiConstants.realtimeWsUrl(storeId: _requestStoreId),
    );
    final url = baseUri.replace(
      queryParameters: {...baseUri.queryParameters, 'access_token': token},
    );

    try {
      final channel = WebSocketChannel.connect(url);
      _channel = channel;
      _channelSubscription = channel.stream.listen(
        (message) => unawaited(_handleRealtimeMessage(message, clientId)),
        onError: (Object error, StackTrace stackTrace) {
          unawaited(
            AppLogger.instance.error(
              'PaymentMonitor',
              'Realtime socket error',
              error: error,
              stackTrace: stackTrace,
              upload: true,
            ),
          );
          unawaited(_closeRealtime());
        },
        onDone: () {
          unawaited(
            AppLogger.instance.warn('PaymentMonitor', 'Realtime socket closed'),
          );
          unawaited(_closeRealtime());
        },
      );
      await AppLogger.instance.info(
        'PaymentMonitor',
        'Realtime socket connected',
        context: {'storeId': _requestStoreId ?? _user?.storeId},
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'PaymentMonitor',
        'Realtime socket connect failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
      );
    }
  }

  Future<void> _closeRealtime() async {
    final subscription = _channelSubscription;
    _channelSubscription = null;
    await subscription?.cancel();
    final channel = _channel;
    _channel = null;
    await channel?.sink.close();
  }

  Future<void> _handleRealtimeMessage(dynamic message, String clientId) async {
    try {
      final decoded = jsonDecode(message.toString());
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['type'] != 'PAYMENT_NOTIFICATION') return;
      final payload = decoded['payload'];
      if (payload is! Map) return;
      final notification = PaymentNotification.fromJson(
        payload.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (!notification.isValid) return;
      if (!_seenNotificationIds.add(notification.notificationId)) return;

      await _repository.acknowledgeNotification(
        notificationId: notification.notificationId,
        clientId: clientId,
        event: 'DELIVERED',
      );

      try {
        if (notification.audioStatus != 'READY') {
          throw StateError(
            'Server audio is not ready: ${notification.audioStatus}',
          );
        }
        final audioBytes = notification.audioStatus == 'READY'
            ? await _repository.downloadNotificationAudio(
                notification.notificationId,
              )
            : null;
        if (notification.audioStatus == 'READY' &&
            (audioBytes == null || audioBytes.isEmpty)) {
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
        await _speaker.speakAmount(notification.amount);
      }
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'PaymentMonitor',
        'Realtime message handling failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
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
}
