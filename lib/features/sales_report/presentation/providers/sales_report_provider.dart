import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/realtime_connection_manager.dart';
import '../../../../core/utils/date_range_defaults.dart';
import '../../../auth/domain/entities/user.dart';
import '../../data/sales_report_repository.dart';
import '../../domain/sales_report.dart';

class SalesReportProvider extends ChangeNotifier {
  static const int _defaultOrdersLimit = 20;
  static const String _realtimeTopic = 'sales-report.orders';
  static const String _realtimeKind = 'SALES_REPORT_ORDERS_UPDATED';

  final SalesReportRepository _repository;
  final DateTime Function() _now;
  final RealtimeClient _realtimeClient;
  final Duration _realtimeDebounce;
  final Duration _realtimeMaxWait;

  final List<SalesReportCategoryGroup> _categories = [];
  final List<Map<String, dynamic>> _adminItems = [];
  SalesReportOrderCockpit? _orderCockpit;
  SalesReportOrderCheck? _checkedOrder;
  bool _isLoadingCategories = false;
  bool _isLoadingOrders = false;
  bool _isCheckingOrder = false;
  bool _isSubmitting = false;
  bool _isLoadingAdminList = false;
  bool _isExporting = false;
  String? _errorMessage;
  String? _successMessage;
  int _adminTotal = 0;
  int _adminPage = 0;
  int _adminLimit = 20;
  int _reportedOrdersPage = 0;
  int _unreportedOrdersPage = 0;
  int _ordersLimit = _defaultOrdersLimit;
  DateTime? _ordersStartDate;
  DateTime? _ordersEndDate;
  String? _ordersStoreCode;
  String? _ordersUserEmail;
  User? _user;
  StreamSubscription<RealtimeEnvelope>? _realtimeEventSubscription;
  StreamSubscription<RealtimeSyncReason>? _realtimeSyncSubscription;
  Timer? _realtimeDebounceTimer;
  Timer? _realtimeMaxWaitTimer;
  bool _ordersRealtimeActive = false;
  bool _realtimeRefreshDirty = false;
  bool _realtimeRefreshInFlight = false;
  bool _disposed = false;

  SalesReportProvider(
    this._repository, {
    DateTime Function()? now,
    RealtimeClient? realtimeClient,
    Duration realtimeDebounce = const Duration(seconds: 2),
    Duration realtimeMaxWait = const Duration(seconds: 5),
  }) : _now = now ?? DateTime.now,
       _realtimeClient = realtimeClient ?? RealtimeConnectionManager.instance,
       _realtimeDebounce = realtimeDebounce,
       _realtimeMaxWait = realtimeMaxWait {
    _resetOrdersDateRangeToToday();
    _realtimeEventSubscription = _realtimeClient.events.listen(
      _handleRealtimeEnvelope,
    );
    _realtimeSyncSubscription = _realtimeClient.syncRequests.listen(
      _handleRealtimeSyncRequest,
    );
  }

  List<SalesReportCategoryGroup> get categories =>
      List.unmodifiable(_categories);
  List<Map<String, dynamic>> get adminItems => List.unmodifiable(_adminItems);
  SalesReportOrderCockpit? get orderCockpit => _orderCockpit;
  List<SalesReportOrderCockpitItem> get reportedOrders =>
      List.unmodifiable(_orderCockpit?.reportedOrders ?? const []);
  List<SalesReportOrderCockpitItem> get unreportedOrders =>
      List.unmodifiable(_orderCockpit?.unreportedOrders ?? const []);
  int get reportedOrdersTotal =>
      _orderCockpit?.reportedTotal ?? reportedOrders.length;
  int get unreportedOrdersTotal =>
      _orderCockpit?.unreportedTotal ?? unreportedOrders.length;
  int get reportedOrdersPage =>
      _orderCockpit?.reportedPage ?? _reportedOrdersPage;
  int get unreportedOrdersPage =>
      _orderCockpit?.unreportedPage ?? _unreportedOrdersPage;
  int get ordersLimit => _orderCockpit?.limit ?? _ordersLimit;
  DateTime? get ordersStartDate => _ordersStartDate;
  DateTime? get ordersEndDate => _ordersEndDate;
  String? get ordersStoreCode => _ordersStoreCode;
  String? get ordersUserEmail => _ordersUserEmail;
  DateTime get currentDate {
    final now = _now();
    return DateTime(now.year, now.month, now.day);
  }

  List<SalesReportFilterOption> get orderStoreOptions =>
      List.unmodifiable(_orderCockpit?.storeOptions ?? const []);
  List<SalesReportFilterOption> get orderUserOptions =>
      List.unmodifiable(_orderCockpit?.userOptions ?? const []);
  bool get canGoPreviousReportedOrders => reportedOrdersPage > 0;
  bool get canGoNextReportedOrders =>
      (reportedOrdersPage + 1) * ordersLimit < reportedOrdersTotal;
  bool get canGoPreviousUnreportedOrders => unreportedOrdersPage > 0;
  bool get canGoNextUnreportedOrders =>
      (unreportedOrdersPage + 1) * ordersLimit < unreportedOrdersTotal;
  SalesReportOrderCheck? get checkedOrder => _checkedOrder;
  bool get isLoadingCategories => _isLoadingCategories;
  bool get isLoadingOrders => _isLoadingOrders;
  bool get isCheckingOrder => _isCheckingOrder;
  bool get isSubmitting => _isSubmitting;
  bool get isLoadingAdminList => _isLoadingAdminList;
  bool get isExporting => _isExporting;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;
  int get adminTotal => _adminTotal;
  int get adminPage => _adminPage;
  int get adminLimit => _adminLimit;
  bool get canGoPrevious => _adminPage > 0;
  bool get canGoNext => (_adminPage + 1) * _adminLimit < _adminTotal;

  Future<void> initialize(
    User? user, {
    bool admin = false,
    bool orders = false,
    bool categories = true,
    SalesReportQuery? adminQuery,
  }) async {
    _user = user;
    _ordersRealtimeActive = orders && user != null;
    await AppLogger.instance.info(
      'SalesReport',
      admin ? 'Sales report admin screen opened' : 'Sales report screen opened',
      context: {
        'admin': admin,
        'orders': orders,
        'categories': categories,
        'userId': user?.id,
        'storeId': user?.storeId,
        'hasSalesReport': user?.canUseFeature('SALES_REPORT') == true,
        'hasAdminSalesReports':
            user?.canUseFeature('ADMIN_SALES_REPORTS') == true,
      },
    );
    if (categories) await loadCategories(admin: admin);
    if (admin) await loadAdminList(query: adminQuery);
    if (orders) {
      await loadOrderCockpit();
    }
  }

  Future<void> loadCategories({bool admin = false}) async {
    if (_isLoadingCategories) return;
    _isLoadingCategories = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report categories load started',
        context: {'admin': admin},
      );
      final categories = await _repository.fetchCategories(admin: admin);
      _categories
        ..clear()
        ..addAll(categories);
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report categories load succeeded',
        context: {'admin': admin, 'count': categories.length},
      );
    } catch (error) {
      _errorMessage = _messageFor(error, 'Chưa tải được danh sách ngành hàng.');
      await AppLogger.instance.error(
        'SalesReport',
        'Sales report categories load failed',
        error: error,
        context: {'admin': admin},
      );
    } finally {
      _isLoadingCategories = false;
      notifyListeners();
    }
  }

  Future<SalesReportOrderCheck?> checkOrder(
    String orderCode, {
    String? entrySource,
    String? followUpCaseId,
  }) async {
    if (_isCheckingOrder) return null;
    _isCheckingOrder = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
    final startedAt = DateTime.now();
    try {
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report order check started',
        context: {
          if (entrySource != null) 'entrySource': entrySource,
          'orderLength': orderCode.trim().length,
        },
      );
      final result = await _repository.checkOrder(
        orderCode,
        followUpCaseId: followUpCaseId,
      );
      _checkedOrder = result;
      _successMessage = result.willConvertSyncedReport
          ? 'Đơn hàng này đã có trong danh sách đồng bộ. Nếu lưu mua hàng, hệ thống sẽ chuyển báo cáo sang Khách quay lại.'
          : 'Đã kiểm tra đơn hàng.';
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report order check succeeded',
        context: {
          'orderLength': result.orderCode.length,
          if (entrySource != null) 'entrySource': entrySource,
          if (followUpCaseId != null) 'followUpCaseId': followUpCaseId,
          'hasCategory': result.categoryGroup != null,
          'categoryCount': result.categoryGroups.length,
          'itemCount': result.items.length,
          'paymentCount': result.payments.length,
          'promotionCount': result.promotionCodes.length,
          'customerIsStudent': result.customerIsStudent,
          'installmentAutoFilled': result.installmentNeed,
          'hasInstallmentLoanAmount': result.installmentLoanAmount != null,
          'paymentStatus': result.order['paymentStatus']?.toString(),
          'pendingPaymentBlocked': result.isPendingPayment,
          'willConvertSyncedReport': result.willConvertSyncedReport,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return result;
    } catch (error) {
      _checkedOrder = null;
      _errorMessage = _messageFor(error, 'Chưa kiểm tra được mã đơn hàng.');
      await AppLogger.instance.error(
        'SalesReport',
        'Sales report order check failed',
        error: error,
        context: {
          'orderLength': orderCode.trim().length,
          if (entrySource != null) 'entrySource': entrySource,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return null;
    } finally {
      _isCheckingOrder = false;
      notifyListeners();
    }
  }

  Future<void> loadOrderCockpit({SalesReportOrdersQuery? query}) async {
    if (_isLoadingOrders) return;
    _isLoadingOrders = true;
    _errorMessage = null;
    notifyListeners();
    final startedAt = DateTime.now();
    final effectiveQuery = query ?? _currentOrdersQuery();
    try {
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report order cockpit load started',
        context: _ordersQueryLogContext(effectiveQuery),
      );
      final result = await _repository.fetchOrders(effectiveQuery);
      _orderCockpit = result;
      _reportedOrdersPage = result.reportedPage;
      _unreportedOrdersPage = result.unreportedPage;
      _ordersLimit = result.limit;
      _ordersStoreCode = result.selectedStoreCode;
      _ordersUserEmail = result.selectedUserEmail;
      if ((result.syncError ?? '').trim().isNotEmpty) {
        _errorMessage = result.syncError;
      }
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report order cockpit load succeeded',
        context: {
          ..._ordersQueryLogContext(effectiveQuery),
          'reportedCount': result.reportedOrders.length,
          'reportedTotal': result.reportedTotal,
          'unreportedCount': result.unreportedOrders.length,
          'unreportedTotal': result.unreportedTotal,
          'syncSucceeded': result.syncSucceeded,
          'syncCount': result.syncCount,
          'scope': result.scope,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error) {
      _errorMessage = _messageFor(error, 'Chưa tải được danh sách đơn hàng.');
      await AppLogger.instance.error(
        'SalesReport',
        'Sales report order cockpit load failed',
        error: error,
        context: _ordersQueryLogContext(effectiveQuery),
      );
    } finally {
      _isLoadingOrders = false;
      notifyListeners();
      if (_realtimeRefreshDirty &&
          !_realtimeRefreshInFlight &&
          _ordersRealtimeActive &&
          !_disposed) {
        _scheduleRealtimeRefresh(immediate: true);
      }
    }
  }

  Future<void> loadReportedOrdersPage(int page) async {
    await loadOrderCockpit(
      query: SalesReportOrdersQuery(
        startDate: _resolvedOrdersStartDate,
        endDate: _resolvedOrdersEndDate,
        storeCode: _ordersStoreCode,
        userEmail: _ordersUserEmail,
        reportedPage: page < 0 ? 0 : page,
        unreportedPage: unreportedOrdersPage,
        limit: ordersLimit,
      ),
    );
  }

  Future<void> loadUnreportedOrdersPage(int page) async {
    await loadOrderCockpit(
      query: SalesReportOrdersQuery(
        startDate: _resolvedOrdersStartDate,
        endDate: _resolvedOrdersEndDate,
        storeCode: _ordersStoreCode,
        userEmail: _ordersUserEmail,
        reportedPage: reportedOrdersPage,
        unreportedPage: page < 0 ? 0 : page,
        limit: ordersLimit,
      ),
    );
  }

  Future<void> setOrderFilters({
    DateTime? startDate,
    DateTime? endDate,
    String? storeCode,
    String? userEmail,
    bool updateDateRange = false,
    bool updateStore = false,
    bool updateUser = false,
  }) async {
    if (_isLoadingOrders) return;
    if (updateDateRange) {
      _ordersStartDate = startDate;
      _ordersEndDate = endDate;
    }
    if (updateStore) _ordersStoreCode = _cleanFilter(storeCode);
    if (updateUser) _ordersUserEmail = _cleanFilter(userEmail)?.toLowerCase();
    _reportedOrdersPage = 0;
    _unreportedOrdersPage = 0;
    await loadOrderCockpit();
  }

  Future<bool> submit(
    SalesReportInput input,
    User? user, {
    String? followUpCaseId,
  }) async {
    if (_isSubmitting) return false;
    _isSubmitting = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
    final startedAt = DateTime.now();
    try {
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report submit started',
        context: {
          'type': input.reportType,
          'categoryGroupId': input.categoryGroupId,
          'categoryGroupCount': input.categoryGroupIds.length,
          'hasOrder': (input.orderCode ?? '').trim().isNotEmpty,
          'orderLength': (input.orderCode ?? '').trim().length,
          'orderSuffix': _orderSuffix(input.orderCode),
          'entrySource': input.entrySource,
          'hasCustomerName': (input.customerName ?? '').trim().isNotEmpty,
          'contactNumberProvided': (input.customerPhone ?? '')
              .trim()
              .isNotEmpty,
          'contactChannelCount': input.customerContactChannels.length,
          'hasZaloPersonal': input.customerContactChannels.contains(
            salesReportContactChannelZaloPersonal,
          ),
          'hasZaloOa': input.customerContactChannels.contains(
            salesReportContactChannelZaloOa,
          ),
          if (followUpCaseId != null) 'followUpCaseId': followUpCaseId,
          'customerType': input.customerType,
          'customerIsStudent': input.customerIsStudent,
          'promotionCount': input.promotionCodes.length,
          'installmentSelected': input.installmentNeed,
          'installmentApproved': input.installmentApproved,
          'installmentPartnerCount': input.installmentPartnerCodes.length,
          'userId': user?.id,
          'storeId': user?.storeId,
        },
      );
      final response = await _repository.create(
        input,
        followUpCaseId: followUpCaseId,
      );
      final convertedExistingReport =
          response['convertedExistingReport'] == true ||
          (response['report'] is Map &&
              (response['report'] as Map)['convertedExistingReport'] == true);
      _successMessage = convertedExistingReport
          ? 'Đã ghi nhận khách quay lại và chuyển nguồn báo cáo.'
          : 'Đã gửi báo cáo.';
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report submit succeeded',
        context: {
          'type': input.reportType,
          'entrySource': input.entrySource,
          if (followUpCaseId != null) 'followUpCaseId': followUpCaseId,
          'convertedExistingReport': convertedExistingReport,
          'orderLength': (input.orderCode ?? '').trim().length,
          'orderSuffix': _orderSuffix(input.orderCode),
          'categoryGroupId': input.categoryGroupId,
          'categoryGroupCount': input.categoryGroupIds.length,
          'hasCustomerName': (input.customerName ?? '').trim().isNotEmpty,
          'contactNumberProvided': (input.customerPhone ?? '')
              .trim()
              .isNotEmpty,
          'contactChannelCount': input.customerContactChannels.length,
          'customerType': input.customerType,
          'customerIsStudent': input.customerIsStudent,
          'promotionCount': input.promotionCodes.length,
          'installmentSelected': input.installmentNeed,
          'installmentApproved': input.installmentApproved,
          'installmentPartnerCount': input.installmentPartnerCodes.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return true;
    } catch (error) {
      _errorMessage = _messageFor(error, 'Chưa gửi được báo cáo.');
      await AppLogger.instance.error(
        'SalesReport',
        'Sales report submit failed',
        error: error,
        context: {
          'type': input.reportType,
          'entrySource': input.entrySource,
          if (followUpCaseId != null) 'followUpCaseId': followUpCaseId,
          'orderLength': (input.orderCode ?? '').trim().length,
          'orderSuffix': _orderSuffix(input.orderCode),
          'categoryGroupId': input.categoryGroupId,
          'categoryGroupCount': input.categoryGroupIds.length,
          'hasCustomerName': (input.customerName ?? '').trim().isNotEmpty,
          'contactNumberProvided': (input.customerPhone ?? '')
              .trim()
              .isNotEmpty,
          'contactChannelCount': input.customerContactChannels.length,
          'customerType': input.customerType,
          'promotionCount': input.promotionCodes.length,
          'installmentSelected': input.installmentNeed,
          'installmentApproved': input.installmentApproved,
          'installmentPartnerCount': input.installmentPartnerCodes.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  void clearCheckedOrder() {
    _checkedOrder = null;
    _successMessage = null;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> loadAdminList({int? page, SalesReportQuery? query}) async {
    if (_isLoadingAdminList) return;
    _isLoadingAdminList = true;
    _errorMessage = null;
    if (page != null) _adminPage = page;
    notifyListeners();
    final requestedQuery =
        query ?? SalesReportQuery(page: _adminPage, limit: _adminLimit);
    final usesImplicitRecentDateRange = _usesImplicitAdminDateRange(
      requestedQuery,
    );
    final effectiveQuery = _applyImplicitAdminDateRange(requestedQuery);
    final startedAt = DateTime.now();
    final queryContext = _adminQueryLogContext(
      effectiveQuery,
      defaultRecentDateRange: usesImplicitRecentDateRange,
    );
    try {
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report admin list started',
        context: queryContext,
      );
      final data = await _repository.fetchList(effectiveQuery);
      final rows = data['items'] is List ? data['items'] as List : const [];
      _adminItems
        ..clear()
        ..addAll(
          rows.whereType<Map>().map(
            (row) => row.map((key, value) => MapEntry(key.toString(), value)),
          ),
        );
      _adminPage =
          int.tryParse(data['page']?.toString() ?? '') ?? effectiveQuery.page;
      _adminLimit =
          int.tryParse(data['limit']?.toString() ?? '') ?? effectiveQuery.limit;
      _adminTotal =
          int.tryParse(data['total']?.toString() ?? '') ?? _adminItems.length;
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report admin list succeeded',
        context: {
          ...queryContext,
          'count': _adminItems.length,
          'total': _adminTotal,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error) {
      _errorMessage = _messageFor(error, 'Chưa tải được danh sách báo cáo.');
      await AppLogger.instance.error(
        'SalesReport',
        'Sales report admin list failed',
        error: error,
        context: queryContext,
      );
    } finally {
      _isLoadingAdminList = false;
      notifyListeners();
    }
  }

  Future<void> exportXlsx({
    SalesReportQuery query = const SalesReportQuery(),
  }) async {
    if (_isExporting) return;
    _isExporting = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
    final startedAt = DateTime.now();
    final usesImplicitRecentDateRange = _usesImplicitAdminDateRange(query);
    final effectiveQuery = _applyImplicitAdminDateRange(query);
    final queryContext = _adminQueryLogContext(
      effectiveQuery,
      defaultRecentDateRange: usesImplicitRecentDateRange,
    );
    try {
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report export started',
        context: queryContext,
      );
      final workbookBytes = await _repository.exportXlsx(effectiveQuery);
      final path = await FilePicker.saveFile(
        dialogTitle: 'Lưu file báo cáo bán hàng',
        fileName:
            'opshub_${_exportTypeFilePart(effectiveQuery.exportType)}_${_timestampForFile()}.xlsx',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: workbookBytes,
        lockParentWindow: true,
      );
      _successMessage = path == null ? 'Đã hủy lưu file.' : 'Đã xuất file.';
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report export succeeded',
        context: {
          ...queryContext,
          'saved': path != null,
          'bytes': workbookBytes.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error) {
      _errorMessage = _messageFor(error, 'Xuất file thất bại.');
      await AppLogger.instance.error(
        'SalesReport',
        'Sales report export failed',
        error: error,
        context: queryContext,
      );
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  Future<void> nextPage() async {
    if (canGoNext) await loadAdminList(page: _adminPage + 1);
  }

  Future<void> previousPage() async {
    if (canGoPrevious) await loadAdminList(page: _adminPage - 1);
  }

  String _messageFor(Object error, String fallback) {
    if (error is ApiException) return error.message;
    return fallback;
  }

  String _timestampForFile() {
    final now = _now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  bool _usesImplicitAdminDateRange(SalesReportQuery query) {
    return query.startDate == null || query.endDate == null;
  }

  SalesReportQuery _applyImplicitAdminDateRange(SalesReportQuery query) {
    if (!_usesImplicitAdminDateRange(query)) return query;
    return SalesReportQuery(
      reportType: query.reportType,
      orderCode: query.orderCode,
      categoryGroupId: query.categoryGroupId,
      exportType: query.exportType,
      startDate: appImplicitDateRangeStart(_now()),
      endDate: appImplicitDateRangeEnd(_now()),
      reporter: query.reporter,
      storeIds: query.storeIds,
      page: query.page,
      limit: query.limit,
    );
  }

  Map<String, Object?> _adminQueryLogContext(
    SalesReportQuery query, {
    required bool defaultRecentDateRange,
  }) {
    return {
      'type': query.reportType,
      'exportType': query.exportType,
      'page': query.page,
      'limit': query.limit,
      'hasOrderCode': (query.orderCode ?? '').trim().isNotEmpty,
      'hasCategoryGroup': (query.categoryGroupId ?? '').trim().isNotEmpty,
      'hasStoreFilter': query.storeIds.isNotEmpty,
      'storeFilterCount': query.storeIds.length,
      'hasStartDate': query.startDate != null,
      'hasEndDate': query.endDate != null,
      'defaultRecentDateRange': defaultRecentDateRange,
      if (query.startDate != null) 'startDate': _dateForLog(query.startDate!),
      if (query.endDate != null) 'endDate': _dateForLog(query.endDate!),
    };
  }

  Map<String, Object?> _ordersQueryLogContext(SalesReportOrdersQuery query) {
    return {
      'reportedPage': query.reportedPage,
      'unreportedPage': query.unreportedPage,
      'limit': query.limit,
      'hasStartDate': query.startDate != null,
      'hasEndDate': query.endDate != null,
      'defaultRecentDateRange':
          _ordersStartDate == null && _ordersEndDate == null,
      'hasStoreFilter': (query.storeCode ?? '').trim().isNotEmpty,
      'hasUserFilter': (query.userEmail ?? '').trim().isNotEmpty,
      if (query.startDate != null) 'startDate': _dateForLog(query.startDate!),
      if (query.endDate != null) 'endDate': _dateForLog(query.endDate!),
    };
  }

  SalesReportOrdersQuery _currentOrdersQuery() {
    return SalesReportOrdersQuery(
      startDate: _resolvedOrdersStartDate,
      endDate: _resolvedOrdersEndDate,
      storeCode: _ordersStoreCode,
      userEmail: _ordersUserEmail,
      reportedPage: _reportedOrdersPage,
      unreportedPage: _unreportedOrdersPage,
      limit: _ordersLimit,
    );
  }

  DateTime get _resolvedOrdersStartDate {
    return _ordersStartDate ??
        _ordersEndDate ??
        appImplicitDateRangeStart(_now());
  }

  DateTime get _resolvedOrdersEndDate {
    return _ordersEndDate ??
        _ordersStartDate ??
        appImplicitDateRangeEnd(_now());
  }

  void _resetOrdersDateRangeToToday() {
    final today = currentDate;
    _ordersStartDate = today;
    _ordersEndDate = today;
  }

  String? _orderSuffix(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    return text.length <= 4 ? text : text.substring(text.length - 4);
  }

  String? _cleanFilter(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  void _handleRealtimeEnvelope(RealtimeEnvelope envelope) {
    if (_disposed ||
        !_ordersRealtimeActive ||
        envelope.topic != _realtimeTopic ||
        envelope.kind != _realtimeKind ||
        !_isRelevantRealtimePayload(envelope.data)) {
      return;
    }
    _scheduleRealtimeRefresh();
    unawaited(
      AppLogger.instance.info(
        'SalesReportRealtime',
        'Sales report realtime invalidation received',
        context: {
          'eventId': envelope.id,
          'sequence': envelope.sequence,
          'newOrderCount': envelope.data['newOrderCount'],
          'dateCount': envelope.data['dates'] is List
              ? (envelope.data['dates'] as List).length
              : 0,
        },
      ),
    );
  }

  void _handleRealtimeSyncRequest(RealtimeSyncReason reason) {
    if (_disposed || !_ordersRealtimeActive) return;
    unawaited(
      AppLogger.instance.info(
        'SalesReportRealtime',
        'Sales report realtime sync requested',
        context: {'reason': reason.name},
      ),
    );
    _scheduleRealtimeRefresh(immediate: true);
  }

  void _scheduleRealtimeRefresh({bool immediate = false}) {
    if (_disposed || !_ordersRealtimeActive) return;
    _realtimeRefreshDirty = true;
    if (immediate) {
      _cancelRealtimeTimers();
      unawaited(_refreshFromRealtime());
      return;
    }
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = Timer(
      _realtimeDebounce,
      () => unawaited(_refreshFromRealtime()),
    );
    _realtimeMaxWaitTimer ??= Timer(
      _realtimeMaxWait,
      () => unawaited(_refreshFromRealtime()),
    );
  }

  Future<void> _refreshFromRealtime() async {
    _cancelRealtimeTimers();
    if (_disposed || !_ordersRealtimeActive || !_realtimeRefreshDirty) return;
    if (_isLoadingOrders) return;
    if (_realtimeRefreshInFlight) return;
    _realtimeRefreshDirty = false;
    _realtimeRefreshInFlight = true;
    final startedAt = DateTime.now();
    try {
      await AppLogger.instance.info(
        'SalesReportRealtime',
        'Sales report realtime refresh started',
      );
      await loadOrderCockpit();
      await AppLogger.instance.info(
        'SalesReportRealtime',
        'Sales report realtime refresh succeeded',
        context: {
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'SalesReportRealtime',
        'Sales report realtime refresh failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } finally {
      _realtimeRefreshInFlight = false;
      if (_realtimeRefreshDirty && !_disposed && _ordersRealtimeActive) {
        _scheduleRealtimeRefresh(immediate: true);
      }
    }
  }

  bool _isRelevantRealtimePayload(Map<String, dynamic> payload) {
    final dates =
        (payload['dates'] is List ? payload['dates'] as List : const [])
            .map((value) => value.toString())
            .toSet();
    if (dates.isNotEmpty) {
      final start = _resolvedOrdersStartDate;
      final end = _resolvedOrdersEndDate;
      final overlaps = dates.any((value) {
        final date = DateTime.tryParse(value);
        if (date == null) return false;
        final day = DateTime(date.year, date.month, date.day);
        return !day.isBefore(start) && !day.isAfter(end);
      });
      if (!overlaps) return false;
    }
    final user = _user;
    if (user == null || user.isSuperAdmin) return user != null;
    final recipientIds =
        (payload['recipientUserIds'] is List
                ? payload['recipientUserIds'] as List
                : const [])
            .map((value) => value.toString())
            .toSet();
    if (user.id != null && recipientIds.contains(user.id)) return true;
    final eventStores =
        (payload['storeCodes'] is List
                ? payload['storeCodes'] as List
                : const [])
            .map((value) => value.toString().trim().toUpperCase())
            .where((value) => value.isNotEmpty)
            .toSet();
    final assignedStores = {
      ...user.assignedStoreIds.map((value) => value.trim().toUpperCase()),
      if ((user.storeId ?? '').trim().isNotEmpty)
        user.storeId!.trim().toUpperCase(),
    };
    if (eventStores.intersection(assignedStores).isNotEmpty) return true;
    return recipientIds.isEmpty && eventStores.isEmpty;
  }

  void _cancelRealtimeTimers() {
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = null;
    _realtimeMaxWaitTimer?.cancel();
    _realtimeMaxWaitTimer = null;
  }

  @visibleForTesting
  void handleRealtimeMessageForTesting(RealtimeEnvelope envelope) {
    _handleRealtimeEnvelope(envelope);
  }

  @override
  void dispose() {
    _disposed = true;
    _ordersRealtimeActive = false;
    _cancelRealtimeTimers();
    unawaited(_realtimeEventSubscription?.cancel());
    unawaited(_realtimeSyncSubscription?.cancel());
    super.dispose();
  }

  String _dateForLog(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  String _exportTypeFilePart(String? exportType) {
    return switch (exportType) {
      'REVENUE' => 'bao_cao_doanh_so',
      'INSTALLMENT' => 'bao_cao_tra_gop',
      _ => 'bao_cao_hvtc',
    };
  }
}
