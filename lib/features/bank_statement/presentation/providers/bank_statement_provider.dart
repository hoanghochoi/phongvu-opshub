import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../auth/domain/entities/store_branch.dart';
import '../../../auth/domain/entities/user.dart';
import '../../data/bank_statement_repository.dart';
import '../../domain/bank_statement_transaction.dart';

class BankStatementRowMessage {
  final String text;
  final bool success;

  const BankStatementRowMessage({required this.text, required this.success});
}

class BankStatementProvider extends ChangeNotifier {
  final BankStatementRepository _repository;
  final List<BankStatementTransaction> _transactions = [];
  final List<StoreBranch> _stores = [];
  final Set<String> _selectedIds = {};
  final Map<String, BankStatementRowMessage> _rowMessages = {};
  final Map<String, Timer> _messageTimers = {};

  User? _user;
  bool _storesLoaded = false;
  bool _allStores = false;
  bool _isLoading = false;
  bool _isExporting = false;
  bool _hasSearched = false;
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
  Set<String> _selectedStoreIds = {};

  BankStatementProvider(this._repository);

  List<BankStatementTransaction> get transactions =>
      List.unmodifiable(_transactions);
  List<StoreBranch> get stores => List.unmodifiable(_stores);
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  bool get allStores => _allStores;
  bool get isLoading => _isLoading;
  bool get isExporting => _isExporting;
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
  Set<String> get selectedStoreIds => Set.unmodifiable(_selectedStoreIds);
  bool get canGoPrevious => _page > 0;
  bool get canGoNext => (_page + 1) * _limit < _total;
  bool get allVisibleSelected =>
      _transactions.isNotEmpty &&
      _transactions.every((item) => _selectedIds.contains(item.id));

  bool get canSearch {
    return _hasEffectiveFilter && _primaryFilterCount <= 1;
  }

  bool get canUseAllStores => _user?.hasNationalWorkScope == true;

  BankStatementRowMessage? rowMessage(String id) => _rowMessages[id];

  Future<void> initialize(User? user) async {
    _user = user;
    await AppLogger.instance.info(
      'BankStatement',
      'Bank statement screen opened',
      context: {'role': user?.role, 'scope': user?.workScopeType},
    );
    if (_storesLoaded) return;
    await loadStores();
  }

  Future<void> loadStores() async {
    try {
      final user = _user;
      final stores = await _repository.fetchStores();
      _stores
        ..clear()
        ..addAll(
          user?.hasNationalWorkScope == true
              ? stores
              : stores.where((store) => store.storeId == user?.storeId),
        );
      _storesLoaded = true;
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement stores loaded',
        context: {'count': _stores.length, 'national': canUseAllStores},
      );
      notifyListeners();
    } catch (error) {
      _errorMessage = 'Chưa tải được danh sách showroom.';
      await AppLogger.instance.error(
        'BankStatement',
        'Bank statement store load failed',
        error: error,
      );
      notifyListeners();
    }
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
    _amount = _clean(value);
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
    if (start != null && end != null && end.isBefore(start)) {
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
    _resetPagingAndSelection();
    if (_hasSearched) unawaited(search());
    notifyListeners();
  }

  Future<void> nextPage() async {
    if (!canGoNext) return;
    _page += 1;
    await search();
  }

  Future<void> previousPage() async {
    if (!canGoPrevious) return;
    _page -= 1;
    await search();
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
    final query = _query();
    try {
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement search started',
        context: _logContext(),
      );
      final page = await _repository.fetchStatements(query);
      _transactions
        ..clear()
        ..addAll(page.transactions);
      _page = page.page;
      _limit = page.limit;
      _total = page.total;
      _hasSearched = true;
      _selectedIds.removeWhere(
        (id) => !_transactions.any((item) => item.id == id),
      );
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement search succeeded',
        context: {
          ..._logContext(),
          'count': _transactions.length,
          'total': _total,
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
    _isExporting = true;
    _exportMessage = null;
    notifyListeners();
    final selected = _selectedIds.toList(growable: false);
    try {
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement export started',
        context: {..._logContext(), 'selectedCount': selected.length},
      );
      final csv = await _repository.exportCsv(
        _query(),
        transactionIds: selected,
      );
      final path = await FilePicker.saveFile(
        dialogTitle: 'Lưu file sao kê',
        fileName: 'opshub_sao_ke_${_timestampForFile()}.csv',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: Uint8List.fromList(utf8.encode(csv)),
        lockParentWindow: true,
      );
      _exportMessage = path == null ? 'Đã hủy lưu CSV.' : 'Đã export CSV.';
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement export succeeded',
        context: {'selectedCount': selected.length, 'saved': path != null},
      );
    } catch (error) {
      _exportMessage = 'Export CSV thất bại.';
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

  Future<void> updateOrders(String transactionId, String rawInput) async {
    try {
      final orders = parseOrderInput(rawInput);
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement inline order save started',
        context: {'transactionId': transactionId, 'orderCount': orders.length},
      );
      final updated = await _repository.updateOrders(transactionId, orders);
      final index = _transactions.indexWhere(
        (item) => item.id == transactionId,
      );
      if (index >= 0) _transactions[index] = updated;
      _showRowMessage(transactionId, 'Đã lưu mã đơn hàng.', true);
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement inline order save succeeded',
        context: {'transactionId': transactionId, 'orderCount': orders.length},
      );
    } catch (error) {
      _showRowMessage(transactionId, 'Chưa lưu được mã đơn.', false);
      await AppLogger.instance.error(
        'BankStatement',
        'Bank statement inline order save failed',
        error: error,
        context: {'transactionId': transactionId},
      );
    }
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

  List<String> parseOrderInput(String input) {
    final seen = <String>{};
    final output = <String>[];
    for (final token in input.split(RegExp(r'[\s,;]+'))) {
      final value = token.trim();
      if (value.isEmpty || seen.contains(value)) continue;
      if (!_isValidOrder(value)) throw FormatException('Invalid order: $value');
      seen.add(value);
      output.add(value);
    }
    return output;
  }

  @override
  void dispose() {
    for (final timer in _messageTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  BankStatementQuery _query() {
    return BankStatementQuery(
      allStores: _allStores,
      storeIds: _selectedStoreIds.toList()..sort(),
      order: _order,
      amount: _amount,
      content: _content,
      orderStatus: _orderStatus,
      startDate: _startDate,
      endDate: _endDate,
      page: _page,
      limit: _limit,
    );
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
    _selectedIds.clear();
  }

  String? _clean(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
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

  bool _isValidOrder(String value) {
    if (!RegExp(r'^\d{14}$').hasMatch(value)) return false;
    final year = 2000 + int.parse(value.substring(0, 2));
    final month = int.parse(value.substring(2, 4));
    final day = int.parse(value.substring(4, 6));
    final date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day;
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
      'page': _page,
      'limit': _limit,
    };
  }

  String _timestampForFile() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
