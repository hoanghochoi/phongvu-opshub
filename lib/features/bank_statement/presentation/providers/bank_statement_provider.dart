import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../auth/domain/entities/store_branch.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../notifications/data/app_notification_read_store.dart';
import '../../data/bank_statement_repository.dart';
import '../../domain/bank_statement_transaction.dart';
import '../../domain/order_code_parser.dart';

const int _vietnamUtcOffsetHours = 7;
const int _maxExportDateSpanDays = 31;
const String _orderTransferRealtimeEventType =
    'STATEMENT_ORDER_TRANSFER_REQUEST';
const String _orderTransferNotificationSource = 'statement_order_transfer';

typedef BankStatementRealtimeConnector = WebSocketChannel Function(Uri uri);

class BankStatementRowMessage {
  final String text;
  final bool success;

  const BankStatementRowMessage({required this.text, required this.success});
}

class BankStatementProvider extends ChangeNotifier {
  final BankStatementRepository _repository;
  final DateTime Function() _now;
  final BankStatementRealtimeConnector _realtimeConnector;
  final AppNotificationReadStore _notificationReadStore;
  final List<BankStatementTransaction> _transactions = [];
  final List<BankStatementOrderTransferRequest> _pendingOrderTransferRequests =
      [];
  final List<StoreBranch> _stores = [];
  final Set<String> _selectedIds = {};
  final Set<String> _seenOrderTransferNotificationIds = {};
  final Map<String, BankStatementRowMessage> _rowMessages = {};
  final Map<String, Timer> _messageTimers = {};
  StreamSubscription<dynamic>? _orderTransferRealtimeSubscription;
  WebSocketChannel? _orderTransferRealtimeChannel;
  String? _orderTransferRealtimeUrl;
  String? _notificationReadUserKey;

  User? _user;
  bool _storesLoaded = false;
  bool _allStores = false;
  bool _isLoading = false;
  bool _isExporting = false;
  bool _isLoadingOrderTransferRequests = false;
  bool _canReviewOrderTransfers = false;
  bool _hasSearched = false;
  bool _disposed = false;
  String? _errorMessage;
  String? _exportMessage;
  String _orderStatus = 'ALL';
  String? _order;
  String? _amount;
  String? _content;
  DateTime? _startDate;
  DateTime? _endDate;
  int _page = 0;
  int _limit = 20;
  int _total = 0;
  int _pendingOrderTransferTotal = 0;
  Set<String> _selectedStoreIds = {};

  BankStatementProvider(
    this._repository, {
    DateTime Function()? now,
    BankStatementRealtimeConnector? realtimeConnector,
    AppNotificationReadStore? notificationReadStore,
  }) : _now = now ?? DateTime.now,
       _realtimeConnector =
           realtimeConnector ?? ((uri) => WebSocketChannel.connect(uri)),
       _notificationReadStore =
           notificationReadStore ?? const AppNotificationReadStore();

  List<BankStatementTransaction> get transactions =>
      List.unmodifiable(_transactions);
  List<BankStatementOrderTransferRequest> get pendingOrderTransferRequests =>
      List.unmodifiable(_pendingOrderTransferRequests);
  List<StoreBranch> get stores => List.unmodifiable(_stores);
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  bool get allStores => _allStores;
  bool get isLoading => _isLoading;
  bool get isExporting => _isExporting;
  bool get isLoadingOrderTransferRequests => _isLoadingOrderTransferRequests;
  bool get canReviewOrderTransfers => _canReviewOrderTransfers;
  bool get hasOrderTransferNotifications => _user?.canUseBankStatements == true;
  bool get hasSearched => _hasSearched;
  String? get errorMessage => _errorMessage;
  String? get exportMessage => _exportMessage;
  String get orderStatus => _orderStatus;
  String? get order => _order;
  String? get amount => _amount;
  String? get content => _content;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  int get page => _page;
  int get limit => _limit;
  int get total => _total;
  int get pendingOrderTransferTotal => _pendingOrderTransferTotal;
  int get pendingOrderTransferUnreadCount =>
      _pendingOrderTransferRequests.where(_isUnreadOrderTransferRequest).length;
  Set<String> get selectedStoreIds => Set.unmodifiable(_selectedStoreIds);
  bool get canGoPrevious => _page > 0;
  bool get canGoNext => (_page + 1) * _limit < _total;
  bool get hasExportDateRangeLimitViolation =>
      _exportDateSpanDays > _maxExportDateSpanDays;
  String get exportDateRangeLimitMessage {
    final start = _effectiveStartDate();
    final end = _effectiveEndDate();
    return 'Chỉ xuất file tối đa 1 tháng (31 ngày). '
        'Khoảng đang chọn ${_formatDateForMessage(start)} - '
        '${_formatDateForMessage(end)} có $_exportDateSpanDays ngày.';
  }

  bool get allVisibleSelected =>
      _transactions.isNotEmpty &&
      _transactions.every((item) => _selectedIds.contains(item.id));

  bool get canSearch {
    return _hasEffectiveFilter && _primaryFilterCount <= 1;
  }

  bool get canUseAllStores => _user?.canUseAllBankStatementStores == true;

  BankStatementRowMessage? rowMessage(String id) => _rowMessages[id];

  Future<void> initialize(User? user) async {
    _user = user;
    await _loadOrderTransferNotificationReadState();
    await AppLogger.instance.info(
      'BankStatement',
      'Bank statement screen opened',
      context: {'role': user?.role, 'scope': user?.workScopeType},
    );
    if (!_storesLoaded) {
      await loadStores();
    }
    await loadPendingOrderTransferRequests(silent: true);
    _connectOrderTransferRealtime();
  }

  Future<void> loadStores() async {
    try {
      final user = _user;
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement store load started',
        context: {
          'scopeMode': canUseAllStores ? 'ALL_STORES' : 'ASSIGNED_STORE',
          'hasAssignedStore': user?.storeId?.isNotEmpty == true,
        },
      );
      final stores = await _repository.fetchStores();
      final assignedStoreIds = _assignedStoreIdsFor(user);
      _stores
        ..clear()
        ..addAll(
          user?.canUseAllBankStatementStores == true
              ? stores
              : stores.where(
                  (store) => assignedStoreIds.contains(store.storeId),
                ),
        );
      _storesLoaded = true;
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement stores loaded',
        context: {
          'scopeMode': canUseAllStores ? 'ALL_STORES' : 'ASSIGNED_STORE',
          'availableCount': stores.length,
          'visibleCount': _stores.length,
        },
      );
      notifyListeners();
    } catch (error) {
      _errorMessage = 'Chưa tải được danh sách showroom.';
      await AppLogger.instance.error(
        'BankStatement',
        'Bank statement store load failed',
        error: error,
        context: {
          'scopeMode': canUseAllStores ? 'ALL_STORES' : 'ASSIGNED_STORE',
          'hasAssignedStore': _user?.storeId?.isNotEmpty == true,
        },
      );
      notifyListeners();
    }
  }

  static Set<String> _assignedStoreIdsFor(User? user) {
    final ids =
        user?.assignedStoreIds
            .map((value) => value.trim().toUpperCase())
            .where((value) => value.isNotEmpty)
            .toSet() ??
        <String>{};
    final legacyStoreId = user?.storeId?.trim().toUpperCase();
    if (ids.isEmpty && legacyStoreId?.isNotEmpty == true) {
      ids.add(legacyStoreId!);
    }
    return ids;
  }

  void setStoreSelection({required bool allStores, required Set<String> ids}) {
    _allStores = canUseAllStores && allStores;
    _selectedStoreIds = ids.map((id) => id.toUpperCase()).toSet();
    if (_allStores || _selectedStoreIds.isNotEmpty) {
      _order = null;
      _amount = null;
      _content = null;
    }
    _resetPagingAndSelection();
    notifyListeners();
    unawaited(loadPendingOrderTransferRequests(silent: true));
    _connectOrderTransferRealtime();
  }

  void setOrder(String value) {
    _order = _clean(value);
    if ((_order ?? '').isNotEmpty) {
      _allStores = false;
      _selectedStoreIds.clear();
      _amount = null;
      _content = null;
    }
    _resetPagingAndSelection();
    notifyListeners();
  }

  void setAmount(String value) {
    final cleanValue = value.replaceAll(RegExp(r'[^0-9]'), '');
    _amount = _clean(cleanValue);
    if ((_amount ?? '').isNotEmpty) {
      _allStores = false;
      _selectedStoreIds.clear();
      _order = null;
      _content = null;
    }
    _resetPagingAndSelection();
    notifyListeners();
  }

  void setContent(String value) {
    _content = _clean(value);
    if ((_content ?? '').isNotEmpty) {
      _allStores = false;
      _selectedStoreIds.clear();
      _order = null;
      _amount = null;
    }
    _resetPagingAndSelection();
    notifyListeners();
  }

  void setOrderStatus(String value) {
    _orderStatus = value;
    _resetPagingAndSelection();
    notifyListeners();
  }

  void setDateRange(DateTime? start, DateTime? end) {
    if (start == null || end == null) {
      _startDate = null;
      _endDate = null;
    } else if (end.isBefore(start)) {
      _startDate = end;
      _endDate = start;
    } else {
      _startDate = start;
      _endDate = end;
    }
    _resetPagingAndSelection();
    notifyListeners();
  }

  void setLimit(int value) {
    if (_limit == value) return;
    _limit = value;
    _page = 0;
    if (_hasSearched && canSearch) {
      unawaited(_fetchPage(0));
    }
    notifyListeners();
  }

  Future<void> nextPage() async {
    if (!canGoNext || _isLoading) return;
    await _fetchPage(_page + 1);
  }

  Future<void> previousPage() async {
    if (!canGoPrevious || _isLoading) return;
    await _fetchPage(_page - 1);
  }

  void toggleSelected(String id, bool selected) {
    if (selected) {
      _selectedIds.add(id);
    } else {
      _selectedIds.remove(id);
    }
    notifyListeners();
  }

  void toggleAllVisible(bool selected) {
    if (selected) {
      _selectedIds.addAll(_transactions.map((item) => item.id));
    } else {
      for (final item in _transactions) {
        _selectedIds.remove(item.id);
      }
    }
    notifyListeners();
  }

  Future<void> search() async {
    if (!canSearch || _isLoading) return;
    _isLoading = true;
    _errorMessage = null;
    _exportMessage = null;
    notifyListeners();
    final query = _query(page: 0, limit: _limit);
    try {
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement search started',
        context: _logContext(),
      );
      final result = await _repository.fetchStatements(query);
      _transactions
        ..clear()
        ..addAll(result.transactions);
      _page = result.page;
      _total = result.total;
      _hasSearched = true;
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement search succeeded',
        context: {
          ..._logContext(),
          'count': _transactions.length,
          'total': _total,
          'selectedCount': _selectedIds.length,
          'serverSidePaging': true,
        },
      );
    } catch (error) {
      _errorMessage = 'Chưa tải được sao kê. Vui lòng kiểm tra filter.';
      await AppLogger.instance.error(
        'BankStatement',
        'Bank statement search failed',
        error: error,
        context: _logContext(),
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> exportCsv() async {
    if (!canSearch || _isExporting) return;
    if (hasExportDateRangeLimitViolation) {
      _exportMessage = 'Không xuất file quá 1 tháng.';
      await AppLogger.instance.warn(
        'BankStatement',
        'Bank statement export blocked by date range limit',
        context: {
          ..._logContext(),
          'dateSpanDays': _exportDateSpanDays,
          'maxDateSpanDays': _maxExportDateSpanDays,
        },
      );
      notifyListeners();
      return;
    }
    _isExporting = true;
    _exportMessage = null;
    notifyListeners();
    final selected = _selectedIds.toList(growable: false);
    try {
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement export started',
        context: {
          ..._logContext(),
          'selectedCount': selected.length,
          'dateSpanDays': _exportDateSpanDays,
        },
      );
      final csvBytes = await _repository.exportCsv(
        _query(),
        transactionIds: selected,
      );
      final path = await FilePicker.saveFile(
        dialogTitle: 'Lưu file sao kê',
        fileName: 'opshub_sao_ke_${_timestampForFile()}.csv',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: ensureUtf8BomForCsv(csvBytes),
        lockParentWindow: true,
      );
      _exportMessage = path == null ? 'Đã hủy lưu file.' : 'Đã xuất file.';
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement export succeeded',
        context: {
          'selectedCount': selected.length,
          'dateSpanDays': _exportDateSpanDays,
          'saved': path != null,
        },
      );
    } catch (error) {
      _exportMessage = 'Xuất file thất bại.';
      await AppLogger.instance.error(
        'BankStatement',
        'Bank statement export failed',
        error: error,
        context: _logContext(),
      );
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  Future<void> _fetchPage(int page) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement page load started',
        context: {..._logContext(), 'targetPage': page},
      );
      final result = await _repository.fetchStatements(
        _query(page: page, limit: _limit),
      );
      _transactions
        ..clear()
        ..addAll(result.transactions);
      _page = result.page;
      _total = result.total;
      _hasSearched = true;
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement page load succeeded',
        context: {
          ..._logContext(),
          'count': _transactions.length,
          'total': _total,
          'selectedCount': _selectedIds.length,
        },
      );
    } catch (error) {
      _errorMessage = 'Chưa tải được sao kê. Vui lòng kiểm tra filter.';
      await AppLogger.instance.error(
        'BankStatement',
        'Bank statement page load failed',
        error: error,
        context: {..._logContext(), 'targetPage': page},
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateOrders(String transactionId, String rawInput) async {
    try {
      final orders = parseOrderInput(rawInput);
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement inline order save started',
        context: {'transactionId': transactionId, 'orderCount': orders.length},
      );
      final updated = await _repository.updateOrders(transactionId, orders);
      _replaceTransaction(updated);
      _showRowMessage(transactionId, 'Đã lưu mã đơn hàng.', true);
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement inline order save succeeded',
        context: {'transactionId': transactionId, 'orderCount': orders.length},
      );
    } catch (error) {
      final message = _orderInputErrorMessage(
        error,
        fallback: 'Chưa lưu được mã đơn.',
      );
      _showRowMessage(transactionId, message, false);
      await AppLogger.instance.error(
        'BankStatement',
        'Bank statement inline order save failed',
        error: error,
        context: {'transactionId': transactionId},
      );
    }
  }

  Future<bool> requestOrderTransfer(
    String transactionId,
    String rawInput,
  ) async {
    try {
      final orders = parseOrderInput(rawInput);
      if (orders.isEmpty) {
        throw const FormatException('Missing order codes');
      }
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement order transfer request started',
        context: {'transactionId': transactionId, 'orderCount': orders.length},
      );
      await _repository.createOrderTransferRequest(transactionId, orders);
      _showRowMessage(transactionId, 'Đã gửi Kế toán xác nhận.', true);
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement order transfer request succeeded',
        context: {'transactionId': transactionId, 'orderCount': orders.length},
      );
      await loadPendingOrderTransferRequests(silent: true);
      if (_hasSearched) {
        await _fetchPage(_page);
      } else {
        notifyListeners();
      }
      return true;
    } catch (error) {
      final message = _orderInputErrorMessage(
        error,
        fallback: 'Chưa gửi được yêu cầu cập nhật mã đơn.',
      );
      _showRowMessage(transactionId, message, false);
      await AppLogger.instance.error(
        'BankStatement',
        'Bank statement order transfer request failed',
        error: error,
        context: {'transactionId': transactionId},
      );
      return false;
    }
  }

  Future<void> loadPendingOrderTransferRequests({bool silent = false}) async {
    if (_disposed || _isLoadingOrderTransferRequests) return;
    _isLoadingOrderTransferRequests = true;
    if (!silent && !_disposed) notifyListeners();
    try {
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement pending order transfer load started',
        context: _orderTransferLogContext(),
      );
      final result = await _repository.fetchOrderTransferRequests(
        status: 'NOTIFICATION',
        allStores: _allStores || (canUseAllStores && _selectedStoreIds.isEmpty),
        storeIds: _selectedStoreIds.toList()..sort(),
      );
      if (_disposed) return;
      _pendingOrderTransferRequests
        ..clear()
        ..addAll(result.requests);
      _pendingOrderTransferTotal = result.total;
      _canReviewOrderTransfers = result.canReview;
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement pending order transfer load succeeded',
        context: {
          ..._orderTransferLogContext(),
          'count': _pendingOrderTransferRequests.length,
          'total': _pendingOrderTransferTotal,
          'unreadCount': pendingOrderTransferUnreadCount,
        },
      );
    } catch (error) {
      final reviewUnavailable =
          error is ApiException &&
          (error.statusCode == 401 || error.statusCode == 403);
      if (reviewUnavailable) {
        if (_disposed) return;
        _canReviewOrderTransfers = false;
        _pendingOrderTransferRequests.clear();
        _pendingOrderTransferTotal = 0;
        _closeOrderTransferRealtime();
      }
      if (reviewUnavailable) {
        await AppLogger.instance.info(
          'BankStatement',
          'Bank statement pending order transfer unavailable for user',
          context: _orderTransferLogContext(),
        );
      } else {
        await AppLogger.instance.warn(
          'BankStatement',
          'Bank statement pending order transfer load failed',
          context: {..._orderTransferLogContext(), 'error': error.toString()},
        );
      }
    } finally {
      _isLoadingOrderTransferRequests = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> approveOrderTransferRequest(String requestId) {
    return _reviewOrderTransferRequest(requestId, approved: true);
  }

  Future<void> rejectOrderTransferRequest(String requestId, {String? note}) {
    return _reviewOrderTransferRequest(requestId, approved: false, note: note);
  }

  Future<void> markPendingOrderTransferNotificationsRead() async {
    if (_disposed || !hasOrderTransferNotifications) return;
    final userKey = _notificationReadUserKey;
    if (userKey == null) {
      await AppLogger.instance.warn(
        'BankStatement',
        'Bank statement notification mark-read skipped without signed-in user',
      );
      return;
    }
    final visibleIds = _pendingOrderTransferRequests
        .map((request) => request.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final unreadIds = _pendingOrderTransferRequests
        .where(_isUnreadOrderTransferRequest)
        .map((request) => request.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final hasLocalChanges = !visibleIds.every(
      _seenOrderTransferNotificationIds.contains,
    );
    if (unreadIds.isEmpty && !hasLocalChanges) {
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement notification mark-read skipped with no unread visible rows',
        context: {
          ..._orderTransferLogContext(),
          'visibleCount': visibleIds.length,
        },
      );
      return;
    }
    final previousIds = Set<String>.of(_seenOrderTransferNotificationIds);
    try {
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement notification mark-read started',
        context: {..._orderTransferLogContext(), 'newCount': unreadIds.length},
      );
      if (unreadIds.isNotEmpty) {
        await _notificationReadStore.markRead(
          source: _orderTransferNotificationSource,
          ids: unreadIds,
        );
      }
      _seenOrderTransferNotificationIds.addAll(visibleIds);
      await _notificationReadStore.saveSeenIds(
        userKey: userKey,
        source: _orderTransferNotificationSource,
        ids: _seenOrderTransferNotificationIds,
      );
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement notification mark-read succeeded',
        context: {
          ..._orderTransferLogContext(),
          'seenCount': _seenOrderTransferNotificationIds.length,
          'unreadCount': pendingOrderTransferUnreadCount,
        },
      );
      if (!_disposed) notifyListeners();
    } catch (error) {
      _seenOrderTransferNotificationIds
        ..clear()
        ..addAll(previousIds);
      await AppLogger.instance.warn(
        'BankStatement',
        'Bank statement notification mark-read failed',
        context: {..._orderTransferLogContext(), 'error': error.toString()},
      );
      if (!_disposed) notifyListeners();
    }
  }

  bool _isUnreadOrderTransferRequest(
    BankStatementOrderTransferRequest request,
  ) {
    final id = request.id.trim();
    return id.isNotEmpty &&
        request.notificationReadAt == null &&
        !_seenOrderTransferNotificationIds.contains(id);
  }

  Future<List<BankStatementOrderHistoryEntry>> fetchHistory(
    String transactionId,
  ) async {
    try {
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement history load started',
        context: {'transactionId': transactionId},
      );
      final rows = await _repository.fetchOrderHistory(transactionId);
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement history load succeeded',
        context: {'transactionId': transactionId, 'count': rows.length},
      );
      return rows;
    } catch (error) {
      await AppLogger.instance.error(
        'BankStatement',
        'Bank statement history load failed',
        error: error,
        context: {'transactionId': transactionId},
      );
      rethrow;
    }
  }

  List<String> parseOrderInput(String input) => parseStatementOrderInput(input);

  @override
  void dispose() {
    _disposed = true;
    _closeOrderTransferRealtime();
    for (final timer in _messageTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  BankStatementQuery _query({int? page, int? limit}) {
    final defaultToday = _usesDefaultTodayDateRange ? _todayInVietnam() : null;
    return BankStatementQuery(
      allStores: _allStores,
      storeIds: _selectedStoreIds.toList()..sort(),
      order: _order,
      amount: _amount,
      content: _content,
      orderStatus: _orderStatus,
      startDate: _startDate ?? defaultToday,
      endDate: _endDate ?? defaultToday,
      page: page ?? _page,
      limit: limit ?? _limit,
    );
  }

  bool get _usesDefaultTodayDateRange => _startDate == null && _endDate == null;

  DateTime _todayInVietnam() {
    final vietnamNow = _now().toUtc().add(
      const Duration(hours: _vietnamUtcOffsetHours),
    );
    return DateTime(vietnamNow.year, vietnamNow.month, vietnamNow.day);
  }

  int get _primaryFilterCount => [
    _allStores || _selectedStoreIds.isNotEmpty,
    (_order ?? '').isNotEmpty,
    (_amount ?? '').isNotEmpty,
    (_content ?? '').isNotEmpty,
  ].where((value) => value).length;

  bool get _hasEffectiveFilter =>
      _primaryFilterCount > 0 ||
      _startDate != null ||
      _endDate != null ||
      _orderStatus != 'ALL';

  void _resetPagingAndSelection() {
    _page = 0;
    _total = 0;
    _hasSearched = false;
    _selectedIds.clear();
    _transactions.clear();
  }

  void _replaceTransaction(BankStatementTransaction updated) {
    final visibleIndex = _transactions.indexWhere(
      (item) => item.id == updated.id,
    );
    if (visibleIndex >= 0) _transactions[visibleIndex] = updated;
  }

  Future<void> _reviewOrderTransferRequest(
    String requestId, {
    required bool approved,
    String? note,
  }) async {
    try {
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement order transfer review started',
        context: {'requestId': requestId, 'approved': approved},
      );
      final result = approved
          ? await _repository.approveOrderTransferRequest(requestId)
          : await _repository.rejectOrderTransferRequest(requestId, note: note);
      final transaction = result.transaction;
      if (transaction != null) {
        _replaceTransaction(transaction);
        _showRowMessage(
          transaction.id,
          approved ? 'Đã xác nhận cấn trừ.' : 'Đã từ chối cấn trừ.',
          true,
        );
      }
      await loadPendingOrderTransferRequests(silent: true);
      if (_hasSearched) {
        await _fetchPage(_page);
      } else {
        notifyListeners();
      }
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement order transfer review succeeded',
        context: {'requestId': requestId, 'approved': approved},
      );
    } catch (error) {
      await AppLogger.instance.error(
        'BankStatement',
        'Bank statement order transfer review failed',
        error: error,
        context: {'requestId': requestId, 'approved': approved},
      );
      rethrow;
    }
  }

  Future<void> _loadOrderTransferNotificationReadState() async {
    _seenOrderTransferNotificationIds.clear();
    _notificationReadUserKey = AppNotificationReadStore.userKey(
      id: _user?.id,
      email: _user?.email,
    );
    final userKey = _notificationReadUserKey;
    if (userKey == null) return;
    try {
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement notification read-state load started',
      );
      final ids = await _notificationReadStore.loadSeenIds(
        userKey: userKey,
        source: _orderTransferNotificationSource,
      );
      _seenOrderTransferNotificationIds.addAll(ids);
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement notification read-state load succeeded',
        context: {'seenCount': ids.length},
      );
    } catch (error) {
      _seenOrderTransferNotificationIds.clear();
      await AppLogger.instance.warn(
        'BankStatement',
        'Bank statement notification read-state load failed',
        context: {'error': error.toString()},
      );
    }
  }

  void _connectOrderTransferRealtime() {
    if (!hasOrderTransferNotifications) {
      _closeOrderTransferRealtime();
      return;
    }
    final token = ApiClient().authToken?.trim();
    if (token == null || token.isEmpty) return;
    final url = ApiConstants.realtimeWsUrl(
      storeId: _orderTransferRealtimeStoreId(),
      accessToken: token,
    );
    if (_orderTransferRealtimeUrl == url &&
        _orderTransferRealtimeChannel != null) {
      return;
    }
    _closeOrderTransferRealtime();
    try {
      final channel = _realtimeConnector(Uri.parse(url));
      _orderTransferRealtimeChannel = channel;
      _orderTransferRealtimeUrl = url;
      _orderTransferRealtimeSubscription = channel.stream.listen(
        _handleOrderTransferRealtimeMessage,
        onError: (error, stackTrace) {
          unawaited(
            AppLogger.instance.warn(
              'BankStatement',
              'Bank statement order transfer realtime failed',
              context: {
                ..._orderTransferLogContext(),
                'error': error.toString(),
                'stackTrace': stackTrace.toString(),
              },
            ),
          );
        },
        onDone: () {
          _orderTransferRealtimeChannel = null;
          _orderTransferRealtimeSubscription = null;
          _orderTransferRealtimeUrl = null;
        },
      );
      unawaited(
        AppLogger.instance.info(
          'BankStatement',
          'Bank statement order transfer realtime connected',
          context: _orderTransferLogContext(),
        ),
      );
    } catch (error, stackTrace) {
      unawaited(
        AppLogger.instance.warn(
          'BankStatement',
          'Bank statement order transfer realtime connect failed',
          context: {
            ..._orderTransferLogContext(),
            'error': error.toString(),
            'stackTrace': stackTrace.toString(),
          },
        ),
      );
    }
  }

  void _closeOrderTransferRealtime() {
    final subscription = _orderTransferRealtimeSubscription;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    _orderTransferRealtimeSubscription = null;
    final channel = _orderTransferRealtimeChannel;
    if (channel != null) {
      unawaited(channel.sink.close());
    }
    _orderTransferRealtimeChannel = null;
    _orderTransferRealtimeUrl = null;
  }

  void _handleOrderTransferRealtimeMessage(dynamic message) {
    try {
      final text = switch (message) {
        String value => value,
        List<int> value => utf8.decode(value),
        _ => '',
      };
      if (text.isEmpty) return;
      final decoded = jsonDecode(text);
      if (decoded is! Map ||
          decoded['type']?.toString() != _orderTransferRealtimeEventType) {
        return;
      }
      final payload = decoded['payload'];
      final transactionId = payload is Map
          ? payload['transactionId']?.toString()
          : null;
      unawaited(
        AppLogger.instance.info(
          'BankStatement',
          'Bank statement order transfer realtime received',
          context: {
            ..._orderTransferLogContext(),
            'hasTransactionId': transactionId?.isNotEmpty == true,
          },
        ),
      );
      unawaited(loadPendingOrderTransferRequests(silent: true));
      if (_hasSearched) {
        unawaited(_fetchPage(_page));
      }
    } catch (error, stackTrace) {
      unawaited(
        AppLogger.instance.warn(
          'BankStatement',
          'Bank statement order transfer realtime parse failed',
          context: {
            ..._orderTransferLogContext(),
            'error': error.toString(),
            'stackTrace': stackTrace.toString(),
          },
        ),
      );
    }
  }

  String? _orderTransferRealtimeStoreId() {
    if (_selectedStoreIds.length == 1) return _selectedStoreIds.single;
    if (!canUseAllStores) return _user?.storeId;
    return null;
  }

  DateTime _effectiveStartDate() => _startDate ?? _todayInVietnam();

  DateTime _effectiveEndDate() => _endDate ?? _todayInVietnam();

  int get _exportDateSpanDays {
    final start = _dateOnly(_effectiveStartDate());
    final end = _dateOnly(_effectiveEndDate());
    return end.difference(start).inDays.abs() + 1;
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  String _formatDateForMessage(DateTime value) {
    final date = _dateOnly(value);
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  String? _clean(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  String _orderInputErrorMessage(Object error, {required String fallback}) {
    if (error is ApiException) return error.message;
    if (error is FormatException) {
      return 'Mã đơn hàng phải gồm 14 chữ số, ngăn cách bằng dòng hoặc dấu phẩy.';
    }
    return fallback;
  }

  void _showRowMessage(String id, String text, bool success) {
    _messageTimers.remove(id)?.cancel();
    _rowMessages[id] = BankStatementRowMessage(text: text, success: success);
    notifyListeners();
    _messageTimers[id] = Timer(const Duration(seconds: 3), () {
      _rowMessages.remove(id);
      _messageTimers.remove(id);
      notifyListeners();
    });
  }

  Map<String, Object?> _logContext() {
    return {
      'allStores': _allStores,
      'storeCount': _selectedStoreIds.length,
      'hasOrder': (_order ?? '').isNotEmpty,
      'hasAmount': (_amount ?? '').isNotEmpty,
      'contentLength': _content?.length ?? 0,
      'orderStatus': _orderStatus,
      'hasStartDate': _startDate != null,
      'hasEndDate': _endDate != null,
      'defaultTodayDate': _usesDefaultTodayDateRange,
      'page': _page,
      'limit': _limit,
    };
  }

  Map<String, Object?> _orderTransferLogContext() {
    return {
      'allStores': _allStores || (canUseAllStores && _selectedStoreIds.isEmpty),
      'storeCount': _selectedStoreIds.length,
      'canReview': _canReviewOrderTransfers,
      'pendingTotal': _pendingOrderTransferTotal,
      'unreadTotal': pendingOrderTransferUnreadCount,
    };
  }

  String _timestampForFile() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}

@visibleForTesting
Uint8List ensureUtf8BomForCsv(Uint8List bytes) {
  const bom = [0xef, 0xbb, 0xbf];
  if (bytes.length >= bom.length &&
      bytes[0] == bom[0] &&
      bytes[1] == bom[1] &&
      bytes[2] == bom[2]) {
    return bytes;
  }
  return Uint8List.fromList([...bom, ...bytes]);
}
