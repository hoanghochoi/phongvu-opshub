import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/realtime_connection_manager.dart';
import '../../../../core/utils/date_range_defaults.dart';
import '../../../auth/domain/entities/store_branch.dart';
import '../../../auth/domain/entities/user.dart';
import '../../data/offset_adjustment_repository.dart';
import '../../domain/offset_adjustment.dart';

const _offsetRealtimeEventType = 'OFFSET_ADJUSTMENT_NOTIFICATION';
const _offsetRealtimeTopic = 'notifications.offset-adjustment';

class OffsetAdjustmentProvider extends ChangeNotifier {
  final OffsetAdjustmentRepository _repository;
  final DateTime Function() _now;
  final RealtimeClient _realtimeClient;
  final Duration _realtimeDebounce;
  final Duration _realtimeMaxWait;
  final List<OffsetAdjustment> _items = [];
  final List<OffsetAdjustment> _pendingItems = [];
  final List<StoreBranch> _stores = [];
  StreamSubscription<RealtimeEnvelope>? _realtimeSubscription;
  StreamSubscription<RealtimeSyncReason>? _realtimeSyncSubscription;
  Timer? _realtimeDebounceTimer;
  Timer? _realtimeMaxWaitTimer;
  User? _user;

  bool _storesLoaded = false;
  bool _allStores = false;
  bool _isLoading = false;
  bool _isLoadingPendingItems = false;
  bool _isSaving = false;
  bool _isExporting = false;
  bool _hasSearched = false;
  bool _canReview = false;
  bool _isInitialized = false;
  bool _disposed = false;
  bool _realtimeDirty = false;
  bool _realtimeRefreshInFlight = false;
  bool _realtimeImmediatePending = false;
  String _type = 'ALL';
  String _status = 'ALL';
  String? _order;
  String? _amount;
  DateTime? _startDate;
  DateTime? _endDate;
  int _page = 0;
  int _limit = 20;
  int _total = 0;
  int _pendingTotal = 0;
  Set<String> _selectedStoreIds = {};
  String? _errorMessage;
  String? _successMessage;

  OffsetAdjustmentProvider(
    this._repository, {
    DateTime Function()? now,
    RealtimeClient? realtimeClient,
    Duration realtimeDebounce = const Duration(seconds: 2),
    Duration realtimeMaxWait = const Duration(seconds: 5),
  }) : _now = now ?? DateTime.now,
       _realtimeClient = realtimeClient ?? RealtimeConnectionManager.instance,
       _realtimeDebounce = realtimeDebounce,
       _realtimeMaxWait = realtimeMaxWait {
    _realtimeSubscription = _realtimeClient.events.listen(
      _handleRealtimeEnvelope,
    );
    _realtimeSyncSubscription = _realtimeClient.syncRequests.listen(
      _handleRealtimeSyncRequest,
    );
  }

  List<OffsetAdjustment> get items => List.unmodifiable(_items);
  List<OffsetAdjustment> get pendingItems => List.unmodifiable(_pendingItems);
  List<StoreBranch> get stores => List.unmodifiable(_stores);
  bool get allStores => _allStores;
  bool get isLoading => _isLoading;
  bool get isLoadingPendingItems => _isLoadingPendingItems;
  bool get isSaving => _isSaving;
  bool get isExporting => _isExporting;
  bool get hasSearched => _hasSearched;
  bool get canReview => _canReview;
  String get type => _type;
  String get status => _status;
  String? get order => _order;
  String? get amount => _amount;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  int get page => _page;
  int get limit => _limit;
  int get total => _total;
  int get pendingTotal => _pendingTotal;
  Set<String> get selectedStoreIds => Set.unmodifiable(_selectedStoreIds);
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;
  bool get canGoPrevious => _page > 0;
  bool get canGoNext => (_page + 1) * _limit < _total;

  Future<void> initialize(User? user) async {
    _user = user;
    _canReview = user?.canReviewOffsetAdjustments == true;
    await AppLogger.instance.info(
      'OffsetAdjustment',
      'Offset adjustment screen opened',
      context: {
        'canReview': _canReview,
        'hasStore': user?.storeId?.isNotEmpty == true,
      },
    );
    if (!_storesLoaded) await loadStores();
    await search();
    await loadPendingTotal();
    _isInitialized = true;
    if (_realtimeDirty) {
      _queueRealtimeRefresh(reason: 'provider_activated', immediate: true);
    }
  }

  Future<void> loadStores() async {
    try {
      await AppLogger.instance.info(
        'OffsetAdjustment',
        'Offset adjustment store load started',
        context: {'canReview': _canReview},
      );
      final stores = await _repository.fetchStores();
      final assignedStoreIds = _assignedStoreIdsFor(_user);
      _stores
        ..clear()
        ..addAll(
          _canReview
              ? stores
              : stores.where(
                  (store) => assignedStoreIds.contains(store.storeId),
                ),
        );
      _storesLoaded = true;
      await AppLogger.instance.info(
        'OffsetAdjustment',
        'Offset adjustment stores loaded',
        context: {
          'availableCount': stores.length,
          'visibleCount': _stores.length,
        },
      );
      notifyListeners();
    } catch (error) {
      _errorMessage = 'Chưa tải được danh sách showroom.';
      await AppLogger.instance.error(
        'OffsetAdjustment',
        'Offset adjustment store load failed',
        error: error,
        context: {'canReview': _canReview},
      );
      notifyListeners();
    }
  }

  void setStoreSelection({required bool allStores, required Set<String> ids}) {
    _allStores = _canReview && allStores;
    _selectedStoreIds = ids.map((id) => id.toUpperCase()).toSet();
    _resetPaging();
    notifyListeners();
  }

  void setType(String value) {
    _type = value;
    _resetPaging();
    notifyListeners();
  }

  void setStatus(String value) {
    _status = value;
    _resetPaging();
    notifyListeners();
  }

  void setOrder(String value) {
    _order = _clean(value);
    _resetPaging();
    notifyListeners();
  }

  void setAmount(String value) {
    _amount = _clean(value.replaceAll(RegExp(r'[^0-9]'), ''));
    _resetPaging();
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
    _resetPaging();
    notifyListeners();
  }

  void setLimit(int value) {
    if (_limit == value) return;
    _limit = value;
    _page = 0;
    if (_hasSearched) {
      unawaited(search(page: 0));
    }
    notifyListeners();
  }

  Future<void> search({int? page}) async {
    if (_isLoading) return;
    _isLoading = true;
    _errorMessage = null;
    if (page != null) _page = page;
    notifyListeners();
    final query = _query(page: _page);
    try {
      await AppLogger.instance.info(
        'OffsetAdjustment',
        'Offset adjustment search started',
        context: _logContext(),
      );
      final result = await _repository.fetchList(query);
      _items
        ..clear()
        ..addAll(result.items);
      _page = result.page;
      _limit = result.limit;
      _total = result.total;
      _canReview = result.canReview || _canReview;
      _hasSearched = true;
      await AppLogger.instance.info(
        'OffsetAdjustment',
        'Offset adjustment search succeeded',
        context: {..._logContext(), 'count': _items.length, 'total': _total},
      );
    } catch (error) {
      _errorMessage = _messageFor(error, 'Chưa tải được danh sách cấn trừ.');
      await AppLogger.instance.error(
        'OffsetAdjustment',
        'Offset adjustment search failed',
        error: error,
        context: _logContext(),
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> nextPage() async {
    if (canGoNext) await search(page: _page + 1);
  }

  Future<void> previousPage() async {
    if (canGoPrevious) await search(page: _page - 1);
  }

  Future<void> loadPendingTotal() async {
    if (!_canReview) return;
    try {
      final result = await _repository.fetchList(_pendingQuery(limit: 1));
      _pendingTotal = result.total;
      notifyListeners();
    } catch (error) {
      await AppLogger.instance.warn(
        'OffsetAdjustment',
        'Offset adjustment pending count failed',
        context: {'error': error.toString()},
      );
    }
  }

  Future<void> loadPendingItems() async {
    if (!_canReview || _isLoadingPendingItems) return;
    _isLoadingPendingItems = true;
    notifyListeners();
    try {
      await AppLogger.instance.info(
        'OffsetAdjustment',
        'Offset adjustment pending notification load started',
        context: _pendingLogContext(),
      );
      final result = await _repository.fetchList(_pendingQuery(limit: 20));
      _pendingItems
        ..clear()
        ..addAll(result.items);
      _pendingTotal = result.total;
      await AppLogger.instance.info(
        'OffsetAdjustment',
        'Offset adjustment pending notification load succeeded',
        context: {
          ..._pendingLogContext(),
          'count': _pendingItems.length,
          'total': _pendingTotal,
        },
      );
    } catch (error) {
      await AppLogger.instance.warn(
        'OffsetAdjustment',
        'Offset adjustment pending notification load failed',
        context: {..._pendingLogContext(), 'error': error.toString()},
      );
    } finally {
      _isLoadingPendingItems = false;
      notifyListeners();
    }
  }

  Future<void> exportCsv({String type = 'ALL'}) async {
    if (_isExporting) return;
    final exportType = type.trim().isEmpty ? 'ALL' : type.trim();
    _isExporting = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
    try {
      await AppLogger.instance.info(
        'OffsetAdjustment',
        'Offset adjustment export started',
        context: {..._logContext(), 'exportType': exportType},
      );
      final csvBytes = await _repository.exportCsv(
        _query(page: 0, limit: 100, type: exportType),
      );
      final path = await FilePicker.saveFile(
        dialogTitle: 'Lưu file cấn trừ',
        fileName:
            'opshub_can_tru_${_fileTypeToken(exportType)}_${_timestampForFile()}.csv',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: _ensureUtf8BomForCsv(csvBytes),
        lockParentWindow: true,
      );
      _successMessage = path == null ? 'Đã hủy lưu file.' : 'Đã xuất file.';
      await AppLogger.instance.info(
        'OffsetAdjustment',
        'Offset adjustment export succeeded',
        context: {
          'exportType': exportType,
          'saved': path != null,
          'bytes': csvBytes.length,
        },
      );
    } catch (error) {
      _errorMessage = _messageFor(error, 'Xuất file thất bại.');
      await AppLogger.instance.error(
        'OffsetAdjustment',
        'Offset adjustment export failed',
        error: error,
        context: {..._logContext(), 'exportType': exportType},
      );
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  Future<String?> create(OffsetAdjustmentInput input) async {
    return _save('create', () => _repository.create(input));
  }

  Future<String?> resubmit(String id, OffsetAdjustmentInput input) async {
    return _save('resubmit', () => _repository.resubmit(id, input));
  }

  Future<String?> complete(String id, {String? ctCode}) async {
    return _save('complete', () => _repository.complete(id, ctCode: ctCode));
  }

  Future<String?> reject(String id, String reason) async {
    return _save('reject', () => _repository.reject(id, reason));
  }

  Future<String?> _save(
    String action,
    Future<OffsetAdjustment> Function() call,
  ) async {
    if (_isSaving) return null;
    _isSaving = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
    try {
      await AppLogger.instance.info(
        'OffsetAdjustment',
        'Offset adjustment $action started',
        context: _logContext(),
      );
      final row = await call();
      _successMessage = switch (action) {
        'create' => 'Đã gửi Kế toán xác nhận.',
        'resubmit' => 'Đã gửi lại Kế toán xác nhận.',
        'complete' => 'Đã hoàn thành hồ sơ cấn trừ.',
        'reject' => 'Đã từ chối hồ sơ cấn trừ.',
        _ => 'Đã cập nhật hồ sơ cấn trừ.',
      };
      await AppLogger.instance.info(
        'OffsetAdjustment',
        'Offset adjustment $action succeeded',
        context: {'id': row.id, 'type': row.type, 'status': row.status},
      );
      await loadPendingTotal();
      await search(page: _page);
      return null;
    } catch (error) {
      final message = _messageFor(error, 'Chưa lưu được hồ sơ cấn trừ.');
      _errorMessage = message;
      await AppLogger.instance.error(
        'OffsetAdjustment',
        'Offset adjustment $action failed',
        error: error,
        context: _logContext(),
      );
      notifyListeners();
      return message;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  OffsetAdjustmentQuery _query({
    int? page,
    int? limit,
    String? status,
    String? type,
  }) {
    final defaultStartDate = _usesImplicitRecentDateRange
        ? _defaultRecentStartDate()
        : null;
    final defaultEndDate = _usesImplicitRecentDateRange
        ? _defaultRecentEndDate()
        : null;
    return OffsetAdjustmentQuery(
      allStores: _allStores || (_canReview && _selectedStoreIds.isEmpty),
      storeIds: _selectedStoreIds.toList()..sort(),
      type: type ?? _type,
      status: status ?? _status,
      order: _order,
      amount: _amount,
      startDate: _startDate ?? defaultStartDate,
      endDate: _endDate ?? defaultEndDate,
      page: page ?? _page,
      limit: limit ?? _limit,
    );
  }

  OffsetAdjustmentQuery _pendingQuery({int limit = 20}) {
    return OffsetAdjustmentQuery(
      allStores: _canReview && (_allStores || _selectedStoreIds.isEmpty),
      storeIds: _selectedStoreIds.toList()..sort(),
      type: 'ALL',
      status: OffsetAdjustmentStatus.pending,
      order: null,
      amount: null,
      startDate: null,
      endDate: null,
      page: 0,
      limit: limit,
    );
  }

  void _handleRealtimeEnvelope(RealtimeEnvelope envelope) {
    if (envelope.kind != _offsetRealtimeEventType ||
        envelope.topic != _offsetRealtimeTopic) {
      return;
    }
    final adjustmentId = envelope.data['adjustmentId']?.toString().trim();
    final storeCode = envelope.data['storeCode']?.toString().trim();
    if (adjustmentId == null ||
        adjustmentId.isEmpty ||
        storeCode == null ||
        storeCode.isEmpty ||
        !_isRealtimeStoreRelevant(storeCode)) {
      return;
    }
    unawaited(
      AppLogger.instance.info(
        'OffsetAdjustment',
        'Offset adjustment realtime received',
        context: {
          'eventId': envelope.id,
          'storeCode': storeCode,
          'canReview': _canReview,
        },
      ),
    );
    _queueRealtimeRefresh(reason: 'event');
  }

  void _handleRealtimeSyncRequest(RealtimeSyncReason reason) {
    if (_disposed) return;
    _realtimeDirty = true;
    if (!_canConsumeRealtime) {
      unawaited(
        AppLogger.instance.info(
          'OffsetAdjustment',
          'Offset adjustment realtime sync deferred',
          context: {'reason': reason.name},
        ),
      );
      return;
    }
    unawaited(
      AppLogger.instance.info(
        'OffsetAdjustment',
        'Offset adjustment realtime sync requested',
        context: {'reason': reason.name},
      ),
    );
    _queueRealtimeRefresh(reason: 'sync_${reason.name}', immediate: true);
  }

  void _queueRealtimeRefresh({required String reason, bool immediate = false}) {
    if (_disposed) return;
    _realtimeDirty = true;
    if (immediate) _realtimeImmediatePending = true;
    if (!_canConsumeRealtime) return;
    if (immediate) {
      _realtimeDebounceTimer?.cancel();
      _realtimeDebounceTimer = null;
      _realtimeMaxWaitTimer?.cancel();
      _realtimeMaxWaitTimer = null;
      unawaited(_flushRealtimeRefresh(reason));
      return;
    }
    _realtimeDebounceTimer?.cancel();
    if (_realtimeDebounce <= Duration.zero) {
      unawaited(_flushRealtimeRefresh(reason));
      return;
    }
    _realtimeDebounceTimer = Timer(_realtimeDebounce, () {
      _realtimeDebounceTimer = null;
      unawaited(_flushRealtimeRefresh('debounce'));
    });
    if (_realtimeMaxWaitTimer == null && _realtimeMaxWait > Duration.zero) {
      _realtimeMaxWaitTimer = Timer(_realtimeMaxWait, () {
        _realtimeMaxWaitTimer = null;
        unawaited(_flushRealtimeRefresh('max_wait'));
      });
    }
    unawaited(
      AppLogger.instance.info(
        'OffsetAdjustment',
        'Offset adjustment realtime refresh queued',
        context: {
          'reason': reason,
          'debounceMs': _realtimeDebounce.inMilliseconds,
          'maxWaitMs': _realtimeMaxWait.inMilliseconds,
        },
      ),
    );
  }

  Future<void> _flushRealtimeRefresh(String reason) async {
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = null;
    _realtimeMaxWaitTimer?.cancel();
    _realtimeMaxWaitTimer = null;
    if (_disposed || !_canConsumeRealtime) return;
    if (_realtimeRefreshInFlight) return;
    if (!_realtimeDirty) return;
    _realtimeDirty = false;
    _realtimeImmediatePending = false;
    _realtimeRefreshInFlight = true;
    final startedAt = DateTime.now();
    try {
      await AppLogger.instance.info(
        'OffsetAdjustment',
        'Offset adjustment realtime refresh started',
        context: {'reason': reason},
      );
      await loadPendingTotal();
      if (_pendingItems.isNotEmpty) await loadPendingItems();
      if (_hasSearched) await search(page: _page);
      await AppLogger.instance.info(
        'OffsetAdjustment',
        'Offset adjustment realtime refresh succeeded',
        context: {
          'reason': reason,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'OffsetAdjustment',
        'Offset adjustment realtime refresh failed',
        error: error,
        stackTrace: stackTrace,
        context: {'reason': reason},
      );
    } finally {
      _realtimeRefreshInFlight = false;
      if (!_disposed && _realtimeDirty) {
        if (_realtimeImmediatePending) {
          unawaited(_flushRealtimeRefresh('pending_sync'));
        } else {
          _queueRealtimeRefresh(reason: 'event_during_refresh');
        }
      }
    }
  }

  bool get _canConsumeRealtime =>
      !_disposed &&
      _isInitialized &&
      _user != null &&
      _user?.canUseOffsetAdjustments == true;

  bool _isRealtimeStoreRelevant(String storeCode) {
    if (_canReview) return true;
    return storeCode.trim().toUpperCase() ==
        (_user?.storeId ?? '').trim().toUpperCase();
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

  void _resetPaging() {
    _page = 0;
  }

  String? _clean(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  String _messageFor(Object error, String fallback) {
    if (error is ApiException) return error.message;
    return fallback;
  }

  bool get _usesImplicitRecentDateRange =>
      _startDate == null && _endDate == null;

  DateTime _defaultRecentStartDate() => appImplicitDateRangeStart(_now());

  DateTime _defaultRecentEndDate() => appImplicitDateRangeEnd(_now());

  Map<String, Object?> _logContext() {
    return {
      'allStores': _allStores || (_canReview && _selectedStoreIds.isEmpty),
      'storeCount': _selectedStoreIds.length,
      'type': _type,
      'status': _status,
      'hasOrder': (_order ?? '').isNotEmpty,
      'hasAmount': (_amount ?? '').isNotEmpty,
      'hasStartDate': _startDate != null,
      'hasEndDate': _endDate != null,
      'defaultRecentDateRange': _usesImplicitRecentDateRange,
      'page': _page,
      'limit': _limit,
      'canReview': _canReview,
    };
  }

  Map<String, Object?> _pendingLogContext() {
    return {
      'allStores': _canReview && (_allStores || _selectedStoreIds.isEmpty),
      'storeCount': _selectedStoreIds.length,
      'pendingTotal': _pendingTotal,
    };
  }

  String _timestampForFile() {
    final now = _now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  String _fileTypeToken(String type) {
    final normalized = type.trim().toUpperCase();
    if (normalized == 'ALL') return 'tat_ca';
    return normalized.toLowerCase();
  }

  void _cancelRealtimeRefresh() {
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = null;
    _realtimeMaxWaitTimer?.cancel();
    _realtimeMaxWaitTimer = null;
    _realtimeDirty = false;
    _realtimeImmediatePending = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelRealtimeRefresh();
    unawaited(_realtimeSubscription?.cancel());
    unawaited(_realtimeSyncSubscription?.cancel());
    super.dispose();
  }
}

Uint8List _ensureUtf8BomForCsv(Uint8List bytes) {
  const bom = [0xef, 0xbb, 0xbf];
  if (bytes.length >= bom.length &&
      bytes[0] == bom[0] &&
      bytes[1] == bom[1] &&
      bytes[2] == bom[2]) {
    return bytes;
  }
  return Uint8List.fromList([...bom, ...bytes]);
}
