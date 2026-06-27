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
import '../../data/app_notification_read_store.dart';
import '../../../offset_adjustment/data/offset_adjustment_repository.dart';
import '../../../offset_adjustment/domain/offset_adjustment.dart';

const String _statementOrderTransferRealtimeEventType =
    'STATEMENT_ORDER_TRANSFER_REQUEST';
const String _offsetAdjustmentRealtimeEventType =
    'OFFSET_ADJUSTMENT_NOTIFICATION';
const String _statementOrderTransferNotificationSource =
    'statement_order_transfer';
const String _offsetAdjustmentNotificationSource = 'offset_adjustment';

typedef AppNotificationRealtimeConnector = WebSocketChannel Function(Uri uri);

class AppNotificationsProvider extends ChangeNotifier {
  final BankStatementRepository _bankStatementRepository;
  final OffsetAdjustmentRepository _offsetAdjustmentRepository;
  final AppNotificationRealtimeConnector _realtimeConnector;
  final AppNotificationReadStore _readStore;
  final List<BankStatementOrderTransferRequest> _statementOrderRequests = [];
  final List<OffsetAdjustment> _offsetAdjustmentRequests = [];
  final Set<String> _seenStatementOrderNotificationIds = {};
  final Set<String> _seenOffsetAdjustmentNotificationIds = {};

  User? _user;
  int _statementOrderCount = 0;
  int _offsetAdjustmentCount = 0;
  bool _isInitialized = false;
  bool _isLoading = false;
  bool _canReviewStatementOrderTransfers = false;
  bool _canReviewOffsetAdjustments = false;
  bool _disposed = false;
  WebSocketChannel? _realtimeChannel;
  StreamSubscription<dynamic>? _realtimeSubscription;
  String? _realtimeUrl;
  String? _notificationReadUserKey;

  AppNotificationsProvider(
    this._bankStatementRepository, {
    required OffsetAdjustmentRepository offsetAdjustmentRepository,
    AppNotificationRealtimeConnector? realtimeConnector,
    AppNotificationReadStore? notificationReadStore,
  }) : _offsetAdjustmentRepository = offsetAdjustmentRepository,
       _realtimeConnector =
           realtimeConnector ?? ((uri) => WebSocketChannel.connect(uri)),
       _readStore = notificationReadStore ?? const AppNotificationReadStore();

  List<BankStatementOrderTransferRequest> get statementOrderRequests =>
      List.unmodifiable(_statementOrderRequests);
  List<OffsetAdjustment> get offsetAdjustmentRequests =>
      List.unmodifiable(_offsetAdjustmentRequests);
  bool get isLoading => _isLoading;
  bool get canReviewStatementOrderTransfers =>
      _canReviewStatementOrderTransfers;
  bool get canReviewOffsetAdjustments => _canReviewOffsetAdjustments;
  bool get hasStatementOrderNotifications =>
      _isInitialized && _user?.canUseBankStatements == true;
  bool get hasOffsetAdjustmentNotifications =>
      _isInitialized && _user?.canUseOffsetAdjustments == true;
  bool get isEnabled =>
      hasStatementOrderNotifications || hasOffsetAdjustmentNotifications;
  int get count => _unreadStatementOrderCount + _unreadOffsetAdjustmentCount;
  int get totalCount => _statementOrderCount + _offsetAdjustmentCount;

  Future<void> syncAuth(User? user, {required bool isInitialized}) async {
    if (_disposed) return;
    _isInitialized = isInitialized;
    final userChanged = _user?.id != user?.id || _user?.email != user?.email;
    _user = user;
    if (userChanged) {
      await _loadSeenNotificationIds();
    }
    if (!isEnabled) {
      _clear();
      _closeRealtime();
      return;
    }
    if (userChanged ||
        (_statementOrderRequests.isEmpty &&
            _offsetAdjustmentRequests.isEmpty)) {
      await load(silent: true);
    }
    _connectRealtime();
  }

  Future<void> load({bool silent = false}) async {
    if (_disposed || !isEnabled || _isLoading) return;
    _isLoading = true;
    if (!silent && !_disposed) notifyListeners();
    final loadStatements = hasStatementOrderNotifications;
    final loadOffsets = hasOffsetAdjustmentNotifications;
    try {
      if (loadStatements) {
        await _loadStatementOrderNotifications();
      } else {
        _clearStatementOrderNotifications();
      }
      if (_disposed) return;
      if (loadOffsets) {
        await _loadOffsetAdjustmentNotifications();
      } else {
        _clearOffsetAdjustmentNotifications();
      }
    } finally {
      _isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _loadStatementOrderNotifications() async {
    try {
      await AppLogger.instance.info(
        'AppNotifications',
        'App notification load started',
        context: {'source': _statementOrderTransferNotificationSource},
      );
      final result = await _bankStatementRepository.fetchOrderTransferRequests(
        status: 'NOTIFICATION',
        limit: 20,
      );
      if (_disposed) return;
      _statementOrderRequests
        ..clear()
        ..addAll(result.requests);
      _statementOrderCount = result.total;
      _canReviewStatementOrderTransfers = result.canReview;
      await AppLogger.instance.info(
        'AppNotifications',
        'App notification load succeeded',
        context: {
          'source': _statementOrderTransferNotificationSource,
          'count': _statementOrderRequests.length,
          'total': result.total,
          'unreadCount': _unreadStatementOrderCount,
          'canReview': result.canReview,
        },
      );
    } catch (error) {
      _clearStatementOrderNotifications();
      await AppLogger.instance.warn(
        'AppNotifications',
        'App notification load failed',
        context: {
          'source': _statementOrderTransferNotificationSource,
          'error': error.toString(),
        },
      );
    }
  }

  Future<void> _loadOffsetAdjustmentNotifications() async {
    try {
      await AppLogger.instance.info(
        'AppNotifications',
        'App notification load started',
        context: {'source': _offsetAdjustmentNotificationSource},
      );
      final result = await _offsetAdjustmentRepository.fetchList(
        _offsetNotificationQuery(),
      );
      if (_disposed) return;
      _offsetAdjustmentRequests
        ..clear()
        ..addAll(result.items);
      _offsetAdjustmentCount = result.total;
      _canReviewOffsetAdjustments = result.canReview;
      await AppLogger.instance.info(
        'AppNotifications',
        'App notification load succeeded',
        context: {
          'source': _offsetAdjustmentNotificationSource,
          'count': _offsetAdjustmentRequests.length,
          'total': result.total,
          'unreadCount': _unreadOffsetAdjustmentCount,
          'canReview': result.canReview,
          'requesterMode': _user?.canReviewOffsetAdjustments != true,
        },
      );
    } catch (error) {
      _clearOffsetAdjustmentNotifications();
      await AppLogger.instance.warn(
        'AppNotifications',
        'App notification load failed',
        context: {
          'source': _offsetAdjustmentNotificationSource,
          'error': error.toString(),
        },
      );
    }
  }

  Future<void> markVisibleNotificationsRead() async {
    if (_disposed || !isEnabled) return;
    final userKey = _notificationReadUserKey;
    if (userKey == null) {
      await AppLogger.instance.warn(
        'AppNotifications',
        'App notification mark-read skipped without signed-in user',
      );
      return;
    }
    final statementIds = _statementOrderRequests
        .map((request) => request.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final offsetIds = _offsetAdjustmentRequests
        .map((request) => request.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final unreadStatementIds = _statementOrderRequests
        .where(_isUnreadStatementOrderRequest)
        .map((request) => request.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final unreadOffsetIds = _offsetAdjustmentRequests
        .where(_isUnreadOffsetAdjustmentRequest)
        .map((request) => request.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final hasLocalChanges =
        !statementIds.every(_seenStatementOrderNotificationIds.contains) ||
        !offsetIds.every(_seenOffsetAdjustmentNotificationIds.contains);
    if (unreadStatementIds.isEmpty &&
        unreadOffsetIds.isEmpty &&
        !hasLocalChanges) {
      await AppLogger.instance.info(
        'AppNotifications',
        'App notification mark-read skipped with no unread visible rows',
        context: {
          'statementCount': statementIds.length,
          'offsetCount': offsetIds.length,
        },
      );
      return;
    }
    final previousStatementIds = Set<String>.of(
      _seenStatementOrderNotificationIds,
    );
    final previousOffsetIds = Set<String>.of(
      _seenOffsetAdjustmentNotificationIds,
    );
    try {
      await AppLogger.instance.info(
        'AppNotifications',
        'App notification mark-read started',
        context: {
          'statementNewCount': unreadStatementIds.length,
          'offsetNewCount': unreadOffsetIds.length,
        },
      );
      if (unreadStatementIds.isNotEmpty) {
        await _readStore.markRead(
          source: _statementOrderTransferNotificationSource,
          ids: unreadStatementIds,
        );
      }
      if (unreadOffsetIds.isNotEmpty) {
        await _readStore.markRead(
          source: _offsetAdjustmentNotificationSource,
          ids: unreadOffsetIds,
        );
      }
      _seenStatementOrderNotificationIds.addAll(statementIds);
      _seenOffsetAdjustmentNotificationIds.addAll(offsetIds);
      await _saveSeenNotificationIds(userKey);
      await AppLogger.instance.info(
        'AppNotifications',
        'App notification mark-read succeeded',
        context: {
          'statementSeenCount': _seenStatementOrderNotificationIds.length,
          'offsetSeenCount': _seenOffsetAdjustmentNotificationIds.length,
          'unreadCount': count,
        },
      );
      if (!_disposed) notifyListeners();
    } catch (error) {
      _seenStatementOrderNotificationIds
        ..clear()
        ..addAll(previousStatementIds);
      _seenOffsetAdjustmentNotificationIds
        ..clear()
        ..addAll(previousOffsetIds);
      await AppLogger.instance.warn(
        'AppNotifications',
        'App notification mark-read failed',
        context: {'error': error.toString()},
      );
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> reloadReadState() async {
    if (_disposed) return;
    await _loadSeenNotificationIds();
    if (!_disposed) notifyListeners();
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
      if (decoded is! Map) {
        return;
      }
      final type = decoded['type']?.toString();
      if (type != _statementOrderTransferRealtimeEventType &&
          type != _offsetAdjustmentRealtimeEventType) {
        return;
      }
      if (type == _statementOrderTransferRealtimeEventType &&
          !hasStatementOrderNotifications) {
        return;
      }
      if (type == _offsetAdjustmentRealtimeEventType &&
          !hasOffsetAdjustmentNotifications) {
        return;
      }
      final source = type == _offsetAdjustmentRealtimeEventType
          ? _offsetAdjustmentNotificationSource
          : _statementOrderTransferNotificationSource;
      unawaited(
        AppLogger.instance.info(
          'AppNotifications',
          'App notification realtime received',
          context: {'source': source},
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
        _offsetAdjustmentRequests.isEmpty &&
        _statementOrderCount == 0 &&
        _offsetAdjustmentCount == 0 &&
        !_canReviewStatementOrderTransfers &&
        !_canReviewOffsetAdjustments) {
      return;
    }
    _clearStatementOrderNotifications();
    _clearOffsetAdjustmentNotifications();
    notifyListeners();
  }

  void _clearStatementOrderNotifications() {
    _statementOrderRequests.clear();
    _statementOrderCount = 0;
    _canReviewStatementOrderTransfers = false;
  }

  void _clearOffsetAdjustmentNotifications() {
    _offsetAdjustmentRequests.clear();
    _offsetAdjustmentCount = 0;
    _canReviewOffsetAdjustments = false;
  }

  int get _unreadStatementOrderCount {
    return _statementOrderRequests.where(_isUnreadStatementOrderRequest).length;
  }

  int get _unreadOffsetAdjustmentCount {
    return _offsetAdjustmentRequests
        .where(_isUnreadOffsetAdjustmentRequest)
        .length;
  }

  bool _isUnreadStatementOrderRequest(
    BankStatementOrderTransferRequest request,
  ) {
    final id = request.id.trim();
    return id.isNotEmpty &&
        request.notificationReadAt == null &&
        !_seenStatementOrderNotificationIds.contains(id);
  }

  bool _isUnreadOffsetAdjustmentRequest(OffsetAdjustment request) {
    final id = request.id.trim();
    return id.isNotEmpty &&
        request.notificationReadAt == null &&
        !_seenOffsetAdjustmentNotificationIds.contains(id);
  }

  Future<void> _loadSeenNotificationIds() async {
    _seenStatementOrderNotificationIds.clear();
    _seenOffsetAdjustmentNotificationIds.clear();
    _notificationReadUserKey = AppNotificationReadStore.userKey(
      id: _user?.id,
      email: _user?.email,
    );
    final userKey = _notificationReadUserKey;
    if (userKey == null) return;
    try {
      await AppLogger.instance.info(
        'AppNotifications',
        'App notification read-state load started',
      );
      final statementIds = await _readStore.loadSeenIds(
        userKey: userKey,
        source: _statementOrderTransferNotificationSource,
      );
      final offsetIds = await _readStore.loadSeenIds(
        userKey: userKey,
        source: _offsetAdjustmentNotificationSource,
      );
      _seenStatementOrderNotificationIds.addAll(statementIds);
      _seenOffsetAdjustmentNotificationIds.addAll(offsetIds);
      await AppLogger.instance.info(
        'AppNotifications',
        'App notification read-state load succeeded',
        context: {
          'statementSeenCount': statementIds.length,
          'offsetSeenCount': offsetIds.length,
        },
      );
    } catch (error) {
      _seenStatementOrderNotificationIds.clear();
      _seenOffsetAdjustmentNotificationIds.clear();
      await AppLogger.instance.warn(
        'AppNotifications',
        'App notification read-state load failed',
        context: {'error': error.toString()},
      );
    }
  }

  Future<void> _saveSeenNotificationIds(String userKey) async {
    await _readStore.saveSeenIds(
      userKey: userKey,
      source: _statementOrderTransferNotificationSource,
      ids: _seenStatementOrderNotificationIds,
    );
    await _readStore.saveSeenIds(
      userKey: userKey,
      source: _offsetAdjustmentNotificationSource,
      ids: _seenOffsetAdjustmentNotificationIds,
    );
  }

  OffsetAdjustmentQuery _offsetNotificationQuery() {
    return OffsetAdjustmentQuery(
      allStores: _user?.canReviewOffsetAdjustments == true,
      storeIds: const [],
      type: 'ALL',
      status: OffsetAdjustmentStatus.notification,
      order: null,
      amount: null,
      startDate: null,
      endDate: null,
      page: 0,
      limit: 20,
    );
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
