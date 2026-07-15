import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/realtime_connection_manager.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../bank_statement/data/bank_statement_repository.dart';
import '../../../bank_statement/domain/bank_statement_transaction.dart';
import '../../data/app_notification_read_store.dart';
import '../../data/app_notifications_feed_repository.dart';
import '../../../offset_adjustment/data/offset_adjustment_repository.dart';
import '../../../offset_adjustment/domain/offset_adjustment.dart';

const String _statementOrderTransferRealtimeEventType =
    'STATEMENT_ORDER_TRANSFER_REQUEST';
const String _offsetAdjustmentRealtimeEventType =
    'OFFSET_ADJUSTMENT_NOTIFICATION';
const String _statementOrderTransferNotificationSource =
    'statement_order_transfer';
const String _offsetAdjustmentNotificationSource = 'offset_adjustment';

class AppNotificationsProvider extends ChangeNotifier {
  final BankStatementRepository _bankStatementRepository;
  final OffsetAdjustmentRepository _offsetAdjustmentRepository;
  final AppNotificationsFeedRepository _feedRepository;
  final RealtimeClient _realtimeClient;
  final AppNotificationReadStore _readStore;
  final Duration _realtimeRefreshDebounce;
  final Duration _realtimeRefreshMaxWait;
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
  bool _isForeground = false;
  bool _isSurfaceActive = false;
  bool _runtimeRefreshDirty = false;
  bool _initialLoadAttempted = false;
  StreamSubscription<RealtimeEnvelope>? _realtimeEventSubscription;
  StreamSubscription<RealtimeSyncReason>? _realtimeSyncSubscription;
  String? _notificationReadUserKey;
  Timer? _realtimeRefreshTimer;
  DateTime? _realtimeRefreshFirstQueuedAt;
  String? _pendingRealtimeRefreshReason;
  int _pendingRealtimeRefreshEvents = 0;
  int _authGeneration = 0;
  int _loadRequestToken = 0;
  String? _authorizationSignature;

  AppNotificationsProvider(
    this._bankStatementRepository, {
    required OffsetAdjustmentRepository offsetAdjustmentRepository,
    AppNotificationsFeedRepository? feedRepository,
    RealtimeClient? realtimeClient,
    AppNotificationReadStore? notificationReadStore,
    Duration realtimeRefreshDebounce = const Duration(seconds: 2),
    Duration realtimeRefreshMaxWait = const Duration(seconds: 5),
  }) : _offsetAdjustmentRepository = offsetAdjustmentRepository,
       _feedRepository =
           feedRepository ?? AppNotificationsFeedRepository(ApiClient()),
       _realtimeClient = realtimeClient ?? RealtimeConnectionManager.instance,
       _readStore = notificationReadStore ?? const AppNotificationReadStore(),
       _realtimeRefreshDebounce = realtimeRefreshDebounce,
       _realtimeRefreshMaxWait = realtimeRefreshMaxWait {
    _realtimeEventSubscription = _realtimeClient.events.listen(
      _handleRealtimeEnvelope,
    );
    _realtimeSyncSubscription = _realtimeClient.syncRequests.listen(
      _handleRealtimeSyncRequest,
    );
  }

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
  int get count =>
      (hasStatementOrderNotifications ? _unreadStatementOrderCount : 0) +
      (hasOffsetAdjustmentNotifications ? _unreadOffsetAdjustmentCount : 0);
  int get totalCount =>
      (hasStatementOrderNotifications ? _statementOrderCount : 0) +
      (hasOffsetAdjustmentNotifications ? _offsetAdjustmentCount : 0);

  Future<void> syncRuntime({
    required bool isForeground,
    required bool isSurfaceActive,
  }) async {
    if (_disposed) return;
    final wasRuntimeEligible = _isRuntimeEligible;
    _isForeground = isForeground;
    _isSurfaceActive = isSurfaceActive;
    if (!_isRuntimeEligible || !isEnabled) return;

    final becameRuntimeEligible = !wasRuntimeEligible;
    final needsInitialLoad = !_initialLoadAttempted;
    if (!becameRuntimeEligible ||
        (!_runtimeRefreshDirty && !needsInitialLoad)) {
      return;
    }

    _runtimeRefreshDirty = false;
    await AppLogger.instance.info(
      'AppNotifications',
      'App notification runtime activated',
      context: {'refreshRequired': true, 'hasInitialData': !needsInitialLoad},
    );
    await load(silent: true);
  }

  Future<void> syncAuth(User? user, {required bool isInitialized}) async {
    if (_disposed) return;
    final previousSignature = _authorizationSignature;
    final nextSignature = _authSignature(user, isInitialized);
    _isInitialized = isInitialized;
    final userChanged = _user?.id != user?.id || _user?.email != user?.email;
    _user = user;
    _authorizationSignature = nextSignature;
    final authorizationChanged = previousSignature != nextSignature;
    if (authorizationChanged) {
      _authGeneration += 1;
      _loadRequestToken += 1;
      _isLoading = false;
      _initialLoadAttempted = false;
      _cancelScheduledRealtimeRefresh();
      // Scope changes can keep the same feature booleans while changing the
      // stores visible to the user. Never retain rows from the previous scope.
      _clearStatementOrderNotifications();
      _clearOffsetAdjustmentNotifications();
      notifyListeners();
    }
    if (userChanged) {
      await _loadSeenNotificationIds(_authGeneration);
    }
    if (!isEnabled) {
      _runtimeRefreshDirty = false;
      _initialLoadAttempted = false;
      _clear();
      return;
    }
    if (userChanged || !_initialLoadAttempted) {
      if (!_isRuntimeEligible) {
        _runtimeRefreshDirty = true;
        return;
      }
      await load(silent: true);
    }
  }

  Future<void> load({bool silent = false}) async {
    if (_disposed || !isEnabled) return;
    if (!_isRuntimeEligible || _isLoading) {
      _runtimeRefreshDirty = true;
      return;
    }
    _cancelScheduledRealtimeRefresh();
    _initialLoadAttempted = true;
    _isLoading = true;
    final authGeneration = _authGeneration;
    final requestToken = ++_loadRequestToken;
    if (!silent && !_disposed) notifyListeners();
    final loadStatements = hasStatementOrderNotifications;
    final loadOffsets = hasOffsetAdjustmentNotifications;
    final startedAt = DateTime.now();
    try {
      await AppLogger.instance.info(
        'AppNotifications',
        'App notification feed load started',
        context: {
          'statementEnabled': loadStatements,
          'offsetEnabled': loadOffsets,
        },
      );
      final feed = await _feedRepository.fetchFeed();
      if (!_isCurrentLoad(authGeneration, requestToken)) return;
      _applyFeed(
        feed,
        loadStatements: loadStatements,
        loadOffsets: loadOffsets,
      );
      await AppLogger.instance.info(
        'AppNotifications',
        'App notification feed load succeeded',
        context: {
          'schemaVersion': feed.schemaVersion,
          'generatedAt': feed.generatedAt.toIso8601String(),
          'statementCount': _statementOrderRequests.length,
          'offsetCount': _offsetAdjustmentRequests.length,
          'unreadCount': count,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } on ApiException catch (error) {
      if (_isUnsupportedFeed(error)) {
        await AppLogger.instance.warn(
          'AppNotifications',
          'App notification feed unsupported; using legacy endpoints',
          context: {'statusCode': error.statusCode},
        );
        await _loadLegacyNotifications(
          loadStatements: loadStatements,
          loadOffsets: loadOffsets,
          authGeneration: authGeneration,
          requestToken: requestToken,
        );
      } else if (_isCurrentLoad(authGeneration, requestToken)) {
        await _logFeedFailure(error, startedAt);
      }
    } catch (error) {
      if (_isCurrentLoad(authGeneration, requestToken)) {
        await _logFeedFailure(error, startedAt);
      }
    } finally {
      if (_isCurrentLoad(authGeneration, requestToken)) {
        _isLoading = false;
        notifyListeners();
        if (_runtimeRefreshDirty && _isRuntimeEligible && isEnabled) {
          _runtimeRefreshDirty = false;
          unawaited(load(silent: true));
        }
      }
    }
  }

  void _applyFeed(
    AppNotificationsFeed feed, {
    required bool loadStatements,
    required bool loadOffsets,
  }) {
    if (loadStatements && feed.statementOrderTransfersEnabled) {
      final page = feed.statementOrderTransfers;
      _statementOrderRequests
        ..clear()
        ..addAll(page.requests);
      _statementOrderCount = page.total;
      _canReviewStatementOrderTransfers = page.canReview;
    } else {
      _clearStatementOrderNotifications();
    }
    if (loadOffsets && feed.offsetAdjustmentsEnabled) {
      final page = feed.offsetAdjustments;
      _offsetAdjustmentRequests
        ..clear()
        ..addAll(page.items);
      _offsetAdjustmentCount = page.total;
      _canReviewOffsetAdjustments = page.canReview;
    } else {
      _clearOffsetAdjustmentNotifications();
    }
  }

  Future<void> _loadLegacyNotifications({
    required bool loadStatements,
    required bool loadOffsets,
    required int authGeneration,
    required int requestToken,
  }) async {
    if (loadStatements) {
      await _loadStatementOrderNotifications(authGeneration, requestToken);
    } else {
      _clearStatementOrderNotifications();
    }
    if (!_isCurrentLoad(authGeneration, requestToken)) return;
    if (loadOffsets) {
      await _loadOffsetAdjustmentNotifications(authGeneration, requestToken);
    } else {
      _clearOffsetAdjustmentNotifications();
    }
  }

  bool _isUnsupportedFeed(ApiException error) {
    return error.statusCode == 404 || error.statusCode == 501;
  }

  Future<void> _logFeedFailure(Object error, DateTime startedAt) {
    return AppLogger.instance.warn(
      'AppNotifications',
      'App notification feed load failed; stale rows retained',
      context: {
        'error': error.toString(),
        if (error is ApiException) 'statusCode': error.statusCode,
        'statementCount': _statementOrderRequests.length,
        'offsetCount': _offsetAdjustmentRequests.length,
        'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
      },
    );
  }

  Future<void> _loadStatementOrderNotifications(
    int authGeneration,
    int requestToken,
  ) async {
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
      if (!_isCurrentLoad(authGeneration, requestToken) ||
          !hasStatementOrderNotifications) {
        return;
      }
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
      if (!_isCurrentLoad(authGeneration, requestToken)) return;
      await AppLogger.instance.warn(
        'AppNotifications',
        'Legacy app notification load failed; stale rows retained',
        context: {
          'source': _statementOrderTransferNotificationSource,
          'error': error.toString(),
        },
      );
    }
  }

  Future<void> _loadOffsetAdjustmentNotifications(
    int authGeneration,
    int requestToken,
  ) async {
    try {
      await AppLogger.instance.info(
        'AppNotifications',
        'App notification load started',
        context: {'source': _offsetAdjustmentNotificationSource},
      );
      final result = await _offsetAdjustmentRepository.fetchList(
        _offsetNotificationQuery(),
      );
      if (!_isCurrentLoad(authGeneration, requestToken) ||
          !hasOffsetAdjustmentNotifications) {
        return;
      }
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
      if (!_isCurrentLoad(authGeneration, requestToken)) return;
      await AppLogger.instance.warn(
        'AppNotifications',
        'Legacy app notification load failed; stale rows retained',
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

  void _handleRealtimeEnvelope(RealtimeEnvelope envelope) {
    final isStatementEvent =
        envelope.kind == _statementOrderTransferRealtimeEventType &&
        envelope.topic == 'notifications.statement-transfer';
    final isOffsetEvent =
        envelope.kind == _offsetAdjustmentRealtimeEventType &&
        envelope.topic == 'notifications.offset-adjustment';
    if (!isStatementEvent && !isOffsetEvent) return;
    if (isStatementEvent && !hasStatementOrderNotifications) {
      return;
    }
    if (isOffsetEvent && !hasOffsetAdjustmentNotifications) return;
    final source = isOffsetEvent
        ? _offsetAdjustmentNotificationSource
        : _statementOrderTransferNotificationSource;
    unawaited(
      AppLogger.instance.info(
        'AppNotifications',
        'App notification realtime received',
        context: {'eventId': envelope.id, 'source': source},
      ),
    );
    if (!_isRuntimeEligible) {
      _runtimeRefreshDirty = true;
      return;
    }
    _scheduleRealtimeRefresh(source);
  }

  void _handleRealtimeSyncRequest(RealtimeSyncReason reason) {
    if (_disposed || !isEnabled) return;
    if (!_isRuntimeEligible) {
      _runtimeRefreshDirty = true;
      return;
    }
    unawaited(
      AppLogger.instance.info(
        'AppNotifications',
        'App notification realtime sync requested',
        context: {'reason': reason.name},
      ),
    );
    _scheduleRealtimeRefresh('sync_${reason.name}');
  }

  void _scheduleRealtimeRefresh(String reason) {
    if (_disposed || !_isRuntimeEligible || !isEnabled) return;
    final now = DateTime.now();
    _realtimeRefreshFirstQueuedAt ??= now;
    _pendingRealtimeRefreshReason = reason;
    _pendingRealtimeRefreshEvents += 1;

    final elapsed = now.difference(_realtimeRefreshFirstQueuedAt!);
    final remaining = _realtimeRefreshMaxWait - elapsed;
    if (remaining <= Duration.zero) {
      _realtimeRefreshTimer?.cancel();
      _realtimeRefreshTimer = null;
      unawaited(_flushScheduledRealtimeRefresh());
      return;
    }

    _realtimeRefreshTimer?.cancel();
    final delay = remaining < _realtimeRefreshDebounce
        ? remaining
        : _realtimeRefreshDebounce;
    _realtimeRefreshTimer = Timer(delay, () {
      _realtimeRefreshTimer = null;
      unawaited(_flushScheduledRealtimeRefresh());
    });
  }

  Future<void> _flushScheduledRealtimeRefresh() async {
    final reason = _pendingRealtimeRefreshReason ?? 'realtime';
    final coalescedEvents = _pendingRealtimeRefreshEvents;
    _realtimeRefreshFirstQueuedAt = null;
    _pendingRealtimeRefreshReason = null;
    _pendingRealtimeRefreshEvents = 0;
    if (_disposed || !_isRuntimeEligible || !isEnabled) {
      _runtimeRefreshDirty = true;
      return;
    }
    await AppLogger.instance.info(
      'AppNotifications',
      'App notification realtime refresh coalesced',
      context: {'reason': reason, 'coalescedEvents': coalescedEvents},
    );
    await load(silent: true);
  }

  void _cancelScheduledRealtimeRefresh() {
    _realtimeRefreshTimer?.cancel();
    _realtimeRefreshTimer = null;
    _realtimeRefreshFirstQueuedAt = null;
    _pendingRealtimeRefreshReason = null;
    _pendingRealtimeRefreshEvents = 0;
  }

  bool get _isRuntimeEligible => _isForeground && _isSurfaceActive;

  static String _authSignature(User? user, bool isInitialized) {
    if (!isInitialized || user == null) return 'signed_out';
    final assignedStoreIds =
        user.assignedStoreIds
            .map((value) => value.trim().toUpperCase())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    final organizationNodeIds = user.organizationNodeIds.toSet().toList()
      ..sort();
    final assignmentNodeIds =
        user.organizationAssignments
            .map((assignment) => assignment.organizationNodeId)
            .toSet()
            .toList(growable: false)
          ..sort();
    return [
      user.id ?? '',
      user.email,
      user.role ?? '',
      user.canUseBankStatements,
      user.canUseAllBankStatementStores,
      user.canUseOffsetAdjustments,
      user.canReviewOffsetAdjustments,
      user.storeId ?? '',
      assignedStoreIds.join(','),
      user.organizationNodeId ?? '',
      organizationNodeIds.join(','),
      assignmentNodeIds.join(','),
    ].join('|');
  }

  bool _isCurrentLoad(int authGeneration, int requestToken) =>
      !_disposed &&
      authGeneration == _authGeneration &&
      requestToken == _loadRequestToken &&
      isEnabled;

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

  Future<void> _loadSeenNotificationIds([int? expectedGeneration]) async {
    final authGeneration = expectedGeneration ?? _authGeneration;
    final userKey = AppNotificationReadStore.userKey(
      id: _user?.id,
      email: _user?.email,
    );
    if (userKey == null) {
      if (authGeneration == _authGeneration) {
        _notificationReadUserKey = null;
        _seenStatementOrderNotificationIds.clear();
        _seenOffsetAdjustmentNotificationIds.clear();
      }
      return;
    }
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
      if (_disposed ||
          authGeneration != _authGeneration ||
          userKey !=
              AppNotificationReadStore.userKey(
                id: _user?.id,
                email: _user?.email,
              )) {
        return;
      }
      _notificationReadUserKey = userKey;
      _seenStatementOrderNotificationIds
        ..clear()
        ..addAll(statementIds);
      _seenOffsetAdjustmentNotificationIds
        ..clear()
        ..addAll(offsetIds);
      await AppLogger.instance.info(
        'AppNotifications',
        'App notification read-state load succeeded',
        context: {
          'statementSeenCount': statementIds.length,
          'offsetSeenCount': offsetIds.length,
        },
      );
    } catch (error) {
      if (_disposed || authGeneration != _authGeneration) return;
      _notificationReadUserKey = userKey;
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

  @override
  void dispose() {
    _disposed = true;
    _cancelScheduledRealtimeRefresh();
    unawaited(_realtimeEventSubscription?.cancel());
    unawaited(_realtimeSyncSubscription?.cancel());
    super.dispose();
  }
}
