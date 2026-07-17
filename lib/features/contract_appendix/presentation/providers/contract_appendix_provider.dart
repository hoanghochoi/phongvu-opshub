import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_exception.dart';
import '../../data/contract_appendix_clipboard.dart';
import '../../data/contract_appendix_repository.dart';
import '../../domain/contract_appendix.dart';

class ContractAppendixProvider extends ChangeNotifier {
  static const _logSource = 'ContractAppendix';
  static const _historyLimit = 20;
  static const manualVatRates = <int>[0, 500, 800, 1000];

  final ContractAppendixDataSource _dataSource;
  final ContractAppendixClipboardWriter _clipboardWriter;

  ContractAppendixDocument? _draft;
  ContractAppendixDocument? _saved;
  ContractAppendixDocument? _historyDetail;
  List<ContractAppendixHistoryItem> _history = const [];
  bool _isLookingUp = false;
  bool _isRefreshingPreview = false;
  bool _isSaving = false;
  bool _isCopying = false;
  bool _isLoadingHistory = false;
  bool _isLoadingHistoryDetail = false;
  bool _isDirty = false;
  String? _errorMessage;
  String? _successMessage;
  String _historyQuery = '';
  int _historyPage = 0;
  int _historyTotal = 0;
  bool _historyHasMore = false;

  ContractAppendixProvider(
    this._dataSource, {
    ContractAppendixClipboardWriter clipboardWriter =
        const SuperClipboardContractAppendixWriter(),
  }) : _clipboardWriter = clipboardWriter;

  ContractAppendixDocument? get draft => _draft;
  ContractAppendixDocument? get saved => _saved;
  ContractAppendixDocument? get historyDetail => _historyDetail;
  List<ContractAppendixHistoryItem> get history => List.unmodifiable(_history);
  bool get isLookingUp => _isLookingUp;
  bool get isRefreshingPreview => _isRefreshingPreview;
  bool get isSaving => _isSaving;
  bool get isCopying => _isCopying;
  bool get isLoadingHistory => _isLoadingHistory;
  bool get isLoadingHistoryDetail => _isLoadingHistoryDetail;
  bool get isDirty => _isDirty;
  bool get isBusy => _isLookingUp || _isRefreshingPreview || _isSaving;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;
  String get historyQuery => _historyQuery;
  int get historyPage => _historyPage;
  int get historyTotal => _historyTotal;
  bool get historyHasMore => _historyHasMore;
  bool get canGoHistoryPrevious => _historyPage > 0;
  bool get canCopy =>
      _saved != null &&
      _draft != null &&
      !_isDirty &&
      _draft!.id == _saved!.id &&
      !_isCopying;

  String get copyDisabledReason {
    if (_saved == null) return 'Hãy lưu phụ lục trước khi sao chép.';
    if (_isDirty) return 'Nội dung đã thay đổi. Hãy lưu bản mới để sao chép.';
    return 'Chưa thể sao chép bảng lúc này.';
  }

  Future<void> initialize() async {
    await AppLogger.instance.info(
      _logSource,
      'Contract appendix screen opened',
    );
  }

  Future<bool> lookupOrder(String orderCode) async {
    final normalized = orderCode.trim();
    if (normalized.isEmpty) {
      _setError('Vui lòng nhập mã đơn hàng.');
      return false;
    }
    if (_isLookingUp) return false;
    final startedAt = DateTime.now();
    _isLookingUp = true;
    _clearMessages();
    notifyListeners();
    await AppLogger.instance.info(
      _logSource,
      'Contract appendix order lookup started',
      context: {'orderCodeLength': normalized.length},
    );
    try {
      final document = await _dataSource.preview(orderCode: normalized);
      _draft = document;
      _saved = null;
      _isDirty = false;
      _successMessage = document.unresolvedTaxCount > 0
          ? 'Đã lấy thông tin đơn. Vui lòng chọn thuế cho sản phẩm còn thiếu.'
          : 'Đã lấy thông tin đơn hàng và tính bảng phụ lục.';
      await AppLogger.instance.info(
        _logSource,
        'Contract appendix order lookup succeeded',
        context: _documentLogContext(document, startedAt),
      );
      return true;
    } catch (error, stackTrace) {
      _errorMessage = _messageForError(
        error,
        fallback: 'Không lấy được thông tin đơn hàng. Vui lòng thử lại.',
      );
      await AppLogger.instance.error(
        _logSource,
        'Contract appendix order lookup failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'orderCodeLength': normalized.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return false;
    } finally {
      _isLookingUp = false;
      notifyListeners();
    }
  }

  void updateProductName(String sourceLineKey, String value) {
    _updateItem(sourceLineKey, (item) => item.copyWith(productName: value));
  }

  void updateUnit(String sourceLineKey, String value) {
    _updateItem(sourceLineKey, (item) => item.copyWith(unit: value));
  }

  void updateManualVatRate(String sourceLineKey, int? vatRateBps) {
    final document = _draft;
    if (document == null) return;
    final index = document.items.indexWhere(
      (item) => item.sourceLineKey == sourceLineKey,
    );
    if (index < 0) return;
    final current = document.items[index];
    if (!current.canEnterManualTax) return;
    if (vatRateBps != null && !manualVatRates.contains(vatRateBps)) {
      _setError('Mức thuế nhập tay không hợp lệ.');
      return;
    }
    final updated = current.copyWith(
      vatRateBps: vatRateBps,
      taxCode: null,
      taxLabel: vatRateBps == null
          ? null
          : 'Thuế nhập tay ${vatRateBps / 100}%',
      taxSource: vatRateBps == null ? 'MISSING' : 'MANUAL',
      taxFetchedAt: null,
      unitPriceBeforeVat: null,
      lineBeforeVat: null,
      lineVatAmount: null,
    );
    _replaceItem(index, updated, invalidateMoney: true);
  }

  Future<bool> refreshPreview() async {
    final current = _draft;
    if (current == null) {
      _setError('Vui lòng lấy thông tin đơn hàng trước.');
      return false;
    }
    if (_isRefreshingPreview) return false;
    final validation = _validateOverrides(current);
    if (validation != null) {
      _setError(validation);
      return false;
    }
    final startedAt = DateTime.now();
    _isRefreshingPreview = true;
    _clearMessages();
    notifyListeners();
    await AppLogger.instance.info(
      _logSource,
      'Contract appendix preview refresh started',
      context: {
        'itemCount': current.items.length,
        'manualTaxItemCount': current.manualTaxItemCount,
      },
    );
    try {
      final refreshed = await _dataSource.preview(
        orderCode: current.orderCode,
        overrides: current.buildOverrides(),
      );
      _draft = refreshed;
      _isDirty = _saved != null && refreshed.id != _saved!.id;
      if (_saved == null) _isDirty = false;
      _successMessage = refreshed.unresolvedTaxCount > 0
          ? 'Bảng còn thiếu thuế. Vui lòng chọn thuế nhập tay.'
          : 'Đã cập nhật bảng xem trước.';
      await AppLogger.instance.info(
        _logSource,
        'Contract appendix preview refresh succeeded',
        context: _documentLogContext(refreshed, startedAt),
      );
      return true;
    } catch (error, stackTrace) {
      _errorMessage = _messageForError(
        error,
        fallback: 'Chưa cập nhật được bảng. Vui lòng thử lại.',
      );
      await AppLogger.instance.error(
        _logSource,
        'Contract appendix preview refresh failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'itemCount': current.items.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return false;
    } finally {
      _isRefreshingPreview = false;
      notifyListeners();
    }
  }

  Future<bool> saveCurrent() async {
    if (_isSaving) return false;
    var current = _draft;
    if (current == null) {
      _setError('Vui lòng lấy thông tin đơn hàng trước khi lưu.');
      return false;
    }
    if (_isDirty) {
      final refreshed = await refreshPreview();
      if (!refreshed) return false;
      current = _draft;
    }
    if (current == null || !current.canSave || current.unresolvedTaxCount > 0) {
      final count = current?.unresolvedTaxCount ?? 0;
      _setError(
        count > 0
            ? 'Chưa xác định được thuế cho $count sản phẩm. '
                  'Vui lòng chọn thuế trước khi lưu.'
            : 'Bảng chưa đủ dữ liệu để lưu. Vui lòng xem lại.',
      );
      return false;
    }
    final validation = _validateOverrides(current);
    if (validation != null) {
      _setError(validation);
      return false;
    }

    final startedAt = DateTime.now();
    _isSaving = true;
    _clearMessages();
    notifyListeners();
    await AppLogger.instance.info(
      _logSource,
      'Contract appendix save started',
      context: {
        'itemCount': current.items.length,
        'manualTaxItemCount': current.manualTaxItemCount,
      },
    );
    try {
      final result = await _dataSource.save(
        orderCode: current.orderCode,
        quoteVersion: current.quoteVersion,
        overrides: current.buildOverrides(),
      );
      _saved = result;
      _draft = result;
      _isDirty = false;
      _successMessage = 'Đã lưu phụ lục. Bạn có thể sao chép bảng vào Word.';
      await AppLogger.instance.info(
        _logSource,
        'Contract appendix save succeeded',
        context: _documentLogContext(result, startedAt),
      );
      return true;
    } catch (error, stackTrace) {
      _errorMessage = _messageForError(
        error,
        fallback: 'Chưa lưu được phụ lục. Vui lòng thử lại.',
      );
      await AppLogger.instance.error(
        _logSource,
        'Contract appendix save failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'itemCount': current.items.length,
          'manualTaxItemCount': current.manualTaxItemCount,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> copySaved() => _copyDocument(
    _saved,
    operation: 'current',
    unavailableMessage: copyDisabledReason,
  );

  Future<bool> copyHistoryDetail() => _copyDocument(
    _historyDetail,
    operation: 'history',
    unavailableMessage: 'Vui lòng mở một phụ lục trong lịch sử trước.',
  );

  Future<bool> _copyDocument(
    ContractAppendixDocument? document, {
    required String operation,
    required String unavailableMessage,
  }) async {
    if (document == null || (operation == 'current' && !canCopy)) {
      _setError(unavailableMessage);
      return false;
    }
    final startedAt = DateTime.now();
    _isCopying = true;
    _clearMessages();
    notifyListeners();
    try {
      // Web Clipboard requires transient user activation. Start the platform
      // write synchronously from the button handler, before any awaited log.
      final writeFuture = _clipboardWriter.write(document);
      final startLogFuture = AppLogger.instance.info(
        _logSource,
        'Contract appendix copy started',
        context: {'source': operation, 'itemCount': document.items.length},
      );
      await writeFuture;
      await startLogFuture;
      _successMessage = 'Đã sao chép bảng. Bạn có thể dán trực tiếp vào Word.';
      await AppLogger.instance.info(
        _logSource,
        'Contract appendix copy succeeded',
        context: {
          'source': operation,
          'itemCount': document.items.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return true;
    } catch (error, stackTrace) {
      _errorMessage = _messageForError(
        error,
        fallback: 'Chưa sao chép được bảng. Vui lòng thử lại.',
      );
      await AppLogger.instance.error(
        _logSource,
        'Contract appendix copy failed',
        error: error,
        stackTrace: stackTrace,
        context: {'source': operation, 'itemCount': document.items.length},
      );
      return false;
    } finally {
      _isCopying = false;
      notifyListeners();
    }
  }

  Future<bool> loadHistory({String? query, int? page}) async {
    if (_isLoadingHistory) return false;
    final normalizedQuery = (query ?? _historyQuery).trim();
    final targetPage = page ?? _historyPage;
    final startedAt = DateTime.now();
    _isLoadingHistory = true;
    _clearMessages();
    notifyListeners();
    await AppLogger.instance.info(
      _logSource,
      'Contract appendix history load started',
      context: {'page': targetPage, 'queryLength': normalizedQuery.length},
    );
    try {
      final result = await _dataSource.list(
        page: targetPage,
        limit: _historyLimit,
        query: normalizedQuery,
      );
      _history = result.items;
      _historyQuery = normalizedQuery;
      _historyPage = result.page;
      _historyTotal = result.total;
      _historyHasMore = result.hasMore;
      await AppLogger.instance.info(
        _logSource,
        'Contract appendix history load succeeded',
        context: {
          'page': result.page,
          'visibleCount': result.items.length,
          'total': result.total,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return true;
    } catch (error, stackTrace) {
      _errorMessage = _messageForError(
        error,
        fallback: 'Chưa tải được lịch sử phụ lục. Vui lòng thử lại.',
      );
      await AppLogger.instance.error(
        _logSource,
        'Contract appendix history load failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'page': targetPage,
          'queryLength': normalizedQuery.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return false;
    } finally {
      _isLoadingHistory = false;
      notifyListeners();
    }
  }

  Future<bool> openHistoryDetail(String id) async {
    if (_isLoadingHistoryDetail) return false;
    final startedAt = DateTime.now();
    _isLoadingHistoryDetail = true;
    _historyDetail = null;
    _clearMessages();
    notifyListeners();
    await AppLogger.instance.info(
      _logSource,
      'Contract appendix history detail started',
      context: {'idLength': id.length},
    );
    try {
      final result = await _dataSource.detail(id);
      _historyDetail = result;
      await AppLogger.instance.info(
        _logSource,
        'Contract appendix history detail succeeded',
        context: _documentLogContext(result, startedAt),
      );
      return true;
    } catch (error, stackTrace) {
      _errorMessage = _messageForError(
        error,
        fallback: 'Chưa mở được phụ lục. Vui lòng thử lại.',
      );
      await AppLogger.instance.error(
        _logSource,
        'Contract appendix history detail failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'idLength': id.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return false;
    } finally {
      _isLoadingHistoryDetail = false;
      notifyListeners();
    }
  }

  void clearHistoryDetail() {
    _historyDetail = null;
    notifyListeners();
  }

  void clearMessages() {
    if (_errorMessage == null && _successMessage == null) return;
    _clearMessages();
    notifyListeners();
  }

  void _updateItem(
    String sourceLineKey,
    ContractAppendixItem Function(ContractAppendixItem) update,
  ) {
    final document = _draft;
    if (document == null) return;
    final index = document.items.indexWhere(
      (item) => item.sourceLineKey == sourceLineKey,
    );
    if (index < 0) return;
    _replaceItem(index, update(document.items[index]));
  }

  void _replaceItem(
    int index,
    ContractAppendixItem item, {
    bool invalidateMoney = false,
  }) {
    final document = _draft;
    if (document == null) return;
    final items = [...document.items]..[index] = item;
    final unresolved = items.where((row) => row.vatRateBps == null).length;
    final manual = items.where((row) => row.taxSource == 'MANUAL').length;
    _draft = document.copyWith(
      items: items,
      totalBeforeVat: invalidateMoney ? null : document.totalBeforeVat,
      totalVatAmount: invalidateMoney ? null : document.totalVatAmount,
      totalAfterVat: invalidateMoney ? null : document.totalAfterVat,
      amountInWords: invalidateMoney ? null : document.amountInWords,
      unresolvedTaxCount: unresolved,
      manualTaxItemCount: manual,
      canSave: invalidateMoney ? false : document.canSave,
    );
    _isDirty = true;
    _clearMessages();
    notifyListeners();
  }

  String? _validateOverrides(ContractAppendixDocument document) {
    for (final item in document.items) {
      if (item.productName.trim().isEmpty) {
        return 'Tên hàng hóa ở dòng ${item.position} không được để trống.';
      }
      if (item.unit.trim().isEmpty) {
        return 'Đơn vị tính ở dòng ${item.position} không được để trống.';
      }
    }
    return null;
  }

  Map<String, Object?> _documentLogContext(
    ContractAppendixDocument document,
    DateTime startedAt,
  ) {
    final skuCount = document.items.map((item) => item.sku).toSet().length;
    return {
      'itemCount': document.items.length,
      'skuCount': skuCount,
      'batchCount': (skuCount / 50).ceil(),
      'manualTaxItemCount': document.manualTaxItemCount,
      'unresolvedTaxCount': document.unresolvedTaxCount,
      'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
    };
  }

  String _messageForError(Object error, {required String fallback}) {
    if (error is ApiException && error.message.trim().isNotEmpty) {
      return error.message.trim();
    }
    if (error is StateError) {
      final message = error.message.toString().trim();
      if (message.isNotEmpty) return message;
    }
    return fallback;
  }

  void _setError(String message) {
    _errorMessage = message;
    _successMessage = null;
    notifyListeners();
  }

  void _clearMessages() {
    _errorMessage = null;
    _successMessage = null;
  }
}
