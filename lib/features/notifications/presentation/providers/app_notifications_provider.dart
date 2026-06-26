import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../bank_statement/data/bank_statement_repository.dart';
import '../../../bank_statement/domain/bank_statement_transaction.dart';

const String _statementOrderTransferRealtimeEventType =
    'STATEMENT_ORDER_TRANSFER_REQUEST';

typedef AppNotificationRealtimeConnector = WebSocketChannel Function(Uri uri);

class AppNotificationsProvider extends ChangeNotifier {
  final BankStatementRepository _bankStatementRepository;
  final AppNotificationRealtimeConnector _realtimeConnector;
  final List<BankStatementOrderTransferRequest> _statementOrderRequests = [];

  User? _user;
  int _count = 0;
  bool _isInitialized = false;
  bool _isLoading = false;
  bool _canReviewStatementOrderTransfers = false;
  bool _disposed = false;
  WebSocketChannel? _realtimeChannel;
  StreamSubscription<dynamic>? _realtimeSubscription;
  String? _realtimeUrl;

  AppNotificationsProvider(
    this._bankStatementRepository, {
    AppNotificationRealtimeConnector? realtimeConnector,
  }) : _realtimeConnector =
           realtimeConnector ?? ((uri) => WebSocketChannel.connect(uri));

  List<BankStatementOrderTransferRequest> get statementOrderRequests =>
      List.unmodifiable(_statementOrderRequests);
  bool get isLoading => _isLoading;
  bool get canReviewStatementOrderTransfers =>
      _canReviewStatementOrderTransfers;
  bool get isEnabled => _isInitialized && _user?.canUseBankStatements == true;
  int get count => _count;

  Future<void> syncAuth(User? user, {required bool isInitialized}) async {
    if (_disposed) return;
    _isInitialized = isInitialized;
    final userChanged = _user?.id != user?.id || _user?.email != user?.email;
    _user = user;
    if (!isEnabled) {
      _clear();
      _closeRealtime();
      return;
    }
    if (userChanged || _statementOrderRequests.isEmpty) {
      await load(silent: true);
    }
    _connectRealtime();
  }

  Future<void> load({bool silent = false}) async {
    if (_disposed || !isEnabled || _isLoading) return;
    _isLoading = true;
    if (!silent && !_disposed) notifyListeners();
    try {
      await AppLogger.instance.info(
        'AppNotifications',
        'App notification load started',
        context: {'source': 'statement_order_transfer'},
      );
      final result = await _bankStatementRepository.fetchOrderTransferRequests(
        status: 'NOTIFICATION',
        limit: 20,
      );
      if (_disposed) return;
      _statementOrderRequests
        ..clear()
        ..addAll(result.requests);
      _count = result.total;
      _canReviewStatementOrderTransfers = result.canReview;
      await AppLogger.instance.info(
        'AppNotifications',
        'App notification load succeeded',
        context: {
          'source': 'statement_order_transfer',
          'count': _statementOrderRequests.length,
          'total': result.total,
          'canReview': result.canReview,
        },
      );
    } catch (error) {
      _statementOrderRequests.clear();
      _count = 0;
      _canReviewStatementOrderTransfers = false;
      await AppLogger.instance.warn(
        'AppNotifications',
        'App notification load failed',
        context: {'error': error.toString()},
      );
    } finally {
      _isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> approveStatementOrderTransfer(String requestId) async {
    await _reviewStatementOrderTransfer(requestId, approved: true);
  }

  Future<void> rejectStatementOrderTransfer(
    String requestId, {
    String? note,
  }) async {
    await _reviewStatementOrderTransfer(requestId, approved: false, note: note);
  }

  Future<void> _reviewStatementOrderTransfer(
    String requestId, {
    required bool approved,
    String? note,
  }) async {
    try {
      await AppLogger.instance.info(
        'AppNotifications',
        'Statement order notification review started',
        context: {'requestId': requestId, 'approved': approved},
      );
      if (approved) {
        await _bankStatementRepository.approveOrderTransferRequest(requestId);
      } else {
        await _bankStatementRepository.rejectOrderTransferRequest(
          requestId,
          note: note,
        );
      }
      await load(silent: true);
      await AppLogger.instance.info(
        'AppNotifications',
        'Statement order notification review succeeded',
        context: {'requestId': requestId, 'approved': approved},
      );
    } catch (error) {
      await AppLogger.instance.error(
        'AppNotifications',
        'Statement order notification review failed',
        error: error,
        context: {'requestId': requestId, 'approved': approved},
      );
      rethrow;
    }
  }

  void _connectRealtime() {
    if (_disposed) return;
    final token = ApiClient().authToken?.trim();
    if (!isEnabled || token == null || token.isEmpty) {
      _closeRealtime();
      return;
    }
    final url = ApiConstants.realtimeWsUrl(accessToken: token);
    if (_realtimeUrl == url && _realtimeChannel != null) return;
    _closeRealtime();
    try {
      final channel = _realtimeConnector(Uri.parse(url));
      _realtimeChannel = channel;
      _realtimeUrl = url;
      _realtimeSubscription = channel.stream.listen(
        _handleRealtimeMessage,
        onError: (error, stackTrace) {
          unawaited(
            AppLogger.instance.warn(
              'AppNotifications',
              'App notification realtime failed',
              context: {
                'error': error.toString(),
                'stackTrace': stackTrace.toString(),
              },
            ),
          );
        },
        onDone: () {
          _realtimeChannel = null;
          _realtimeSubscription = null;
          _realtimeUrl = null;
        },
      );
      unawaited(
        AppLogger.instance.info(
          'AppNotifications',
          'App notification realtime connected',
        ),
      );
    } catch (error, stackTrace) {
      unawaited(
        AppLogger.instance.warn(
          'AppNotifications',
          'App notification realtime connect failed',
          context: {
            'error': error.toString(),
            'stackTrace': stackTrace.toString(),
          },
        ),
      );
    }
  }

  void _handleRealtimeMessage(dynamic message) {
    try {
      final text = switch (message) {
        String value => value,
        List<int> value => utf8.decode(value),
        _ => '',
      };
      if (text.isEmpty) return;
      final decoded = jsonDecode(text);
      if (decoded is! Map ||
          decoded['type']?.toString() !=
              _statementOrderTransferRealtimeEventType) {
        return;
      }
      unawaited(
        AppLogger.instance.info(
          'AppNotifications',
          'App notification realtime received',
          context: {'source': 'statement_order_transfer'},
        ),
      );
      unawaited(load(silent: true));
    } catch (error, stackTrace) {
      unawaited(
        AppLogger.instance.warn(
          'AppNotifications',
          'App notification realtime parse failed',
          context: {
            'error': error.toString(),
            'stackTrace': stackTrace.toString(),
          },
        ),
      );
    }
  }

  void _clear() {
    if (_disposed) return;
    if (_statementOrderRequests.isEmpty &&
        _count == 0 &&
        !_canReviewStatementOrderTransfers) {
      return;
    }
    _statementOrderRequests.clear();
    _count = 0;
    _canReviewStatementOrderTransfers = false;
    notifyListeners();
  }

  void _closeRealtime() {
    final subscription = _realtimeSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    _realtimeSubscription = null;
    final channel = _realtimeChannel;
    if (channel != null) unawaited(channel.sink.close());
    _realtimeChannel = null;
    _realtimeUrl = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _closeRealtime();
    super.dispose();
  }
}
