import 'dart:async';
import 'dart:convert';

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
  final List<StoreBranch> _stores = [];
  StreamSubscription<dynamic>? _realtimeSubscription;
  WebSocketChannel? _realtimeChannel;
  String? _realtimeUrl;
  User? _user;

  bool _storesLoaded = false;
  bool _allStores = false;
  bool _isLoading = false;
  bool _isSaving = false;
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
  List<StoreBranch> get stores => List.unmodifiable(_stores);
  bool get allStores => _allStores;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
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
      _stores
        ..clear()
        ..addAll(
          _canReview
              ? stores
              : stores.where((store) => store.storeId == _user?.storeId),
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
      final result = await _repository.fetchList(
        _query(page: 0, limit: 1, status: OffsetAdjustmentStatus.pending),
      );
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
        'create' => 'Đã gửi ACC xác nhận.',
        'resubmit' => 'Đã gửi lại ACC xác nhận.',
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

  OffsetAdjustmentQuery _query({int? page, int? limit, String? status}) {
    final today = _today();
    return OffsetAdjustmentQuery(
      allStores: _allStores || (_canReview && _selectedStoreIds.isEmpty),
      storeIds: _selectedStoreIds.toList()..sort(),
      type: _type,
      status: status ?? _status,
      order: _order,
      amount: _amount,
      startDate: _startDate ?? today,
      endDate: _endDate ?? today,
      page: page ?? _page,
      limit: limit ?? _limit,
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

  DateTime _today() {
    final now = _now();
    return DateTime(now.year, now.month, now.day);
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
