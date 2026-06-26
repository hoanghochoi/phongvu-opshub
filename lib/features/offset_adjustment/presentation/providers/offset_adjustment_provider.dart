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
import '../../data/offset_adjustment_repository.dart';
import '../../domain/offset_adjustment.dart';

const _offsetRealtimeEventType = 'OFFSET_ADJUSTMENT_NOTIFICATION';

typedef OffsetRealtimeConnector = WebSocketChannel Function(Uri uri);

class OffsetAdjustmentProvider extends ChangeNotifier {
  final OffsetAdjustmentRepository _repository;
  final DateTime Function() _now;
  final OffsetRealtimeConnector _realtimeConnector;
  final List<OffsetAdjustment> _items = [];
  final List<OffsetAdjustment> _pendingItems = [];
  final List<StoreBranch> _stores = [];
  StreamSubscription<dynamic>? _realtimeSubscription;
  WebSocketChannel? _realtimeChannel;
  String? _realtimeUrl;
  User? _user;

  bool _storesLoaded = false;
  bool _allStores = false;
  bool _isLoading = false;
  bool _isLoadingPendingItems = false;
  bool _isSaving = false;
  bool _isExporting = false;
  bool _hasSearched = false;
  bool _canReview = false;
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
    OffsetRealtimeConnector? realtimeConnector,
  }) : _now = now ?? DateTime.now,
       _realtimeConnector =
           realtimeConnector ?? ((uri) => WebSocketChannel.connect(uri));

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
    _connectRealtime();
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
    _connectRealtime();
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
      _successMessage = path == null ? 'Đã hủy lưu CSV.' : 'Đã export CSV.';
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
      _errorMessage = _messageFor(error, 'Export CSV thất bại.');
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
    return OffsetAdjustmentQuery(
      allStores: _allStores || (_canReview && _selectedStoreIds.isEmpty),
      storeIds: _selectedStoreIds.toList()..sort(),
      type: type ?? _type,
      status: status ?? _status,
      order: _order,
      amount: _amount,
      startDate: _startDate,
      endDate: _endDate,
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

  void _connectRealtime() {
    final token = ApiClient().authToken?.trim();
    if (token == null || token.isEmpty) return;
    final url = ApiConstants.realtimeWsUrl(
      storeId: _realtimeStoreId(),
      accessToken: token,
    );
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
              'OffsetAdjustment',
              'Offset adjustment realtime failed',
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
          'OffsetAdjustment',
          'Offset adjustment realtime connected',
          context: {'storeId': _realtimeStoreId(), 'canReview': _canReview},
        ),
      );
    } catch (error, stackTrace) {
      unawaited(
        AppLogger.instance.warn(
          'OffsetAdjustment',
          'Offset adjustment realtime connect failed',
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
          decoded['type']?.toString() != _offsetRealtimeEventType) {
        return;
      }
      final payload = decoded['payload'];
      final storeCode = payload is Map
          ? payload['storeCode']?.toString()
          : null;
      if (!_canReview &&
          (storeCode ?? '').toUpperCase() !=
              (_user?.storeId ?? '').toUpperCase()) {
        return;
      }
      unawaited(
        AppLogger.instance.info(
          'OffsetAdjustment',
          'Offset adjustment realtime received',
          context: {'storeCode': storeCode, 'canReview': _canReview},
        ),
      );
      unawaited(loadPendingTotal());
      if (_pendingItems.isNotEmpty) unawaited(loadPendingItems());
      if (_hasSearched) unawaited(search(page: _page));
    } catch (error, stackTrace) {
      unawaited(
        AppLogger.instance.warn(
          'OffsetAdjustment',
          'Offset adjustment realtime parse failed',
          context: {
            'error': error.toString(),
            'stackTrace': stackTrace.toString(),
          },
        ),
      );
    }
  }

  String? _realtimeStoreId() {
    if (_selectedStoreIds.length == 1) return _selectedStoreIds.single;
    if (!_canReview) return _user?.storeId;
    return null;
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

  Map<String, Object?> _logContext() {
    return {
      'allStores': _allStores || (_canReview && _selectedStoreIds.isEmpty),
      'storeCount': _selectedStoreIds.length,
      'type': _type,
      'status': _status,
      'hasOrder': (_order ?? '').isNotEmpty,
      'hasAmount': (_amount ?? '').isNotEmpty,
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
    _closeRealtime();
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
