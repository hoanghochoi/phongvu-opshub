import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../auth/domain/entities/user.dart';
import '../../data/sales_report_repository.dart';
import '../../domain/sales_report.dart';

typedef SalesReportRealtimeConnector = WebSocketChannel Function(Uri uri);

class SalesReportProvider extends ChangeNotifier {
  static const int _defaultOrdersLimit = 20;

  final SalesReportRepository _repository;
  final DateTime Function() _now;
  final SalesReportRealtimeConnector _realtimeConnector;
  final Duration _realtimeDebounce;
  final Duration _realtimeReconnectBaseDelay;

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
  DateTime? _ordersDate;
  String? _ordersStoreCode;
  String? _ordersUserEmail;
  User? _user;
  WebSocketChannel? _realtimeChannel;
  StreamSubscription<dynamic>? _realtimeSubscription;
  Timer? _realtimeDebounceTimer;
  Timer? _realtimeReconnectTimer;
  int _realtimeReconnectAttempt = 0;
  bool _realtimeConnectedOnce = false;
  bool _disposed = false;

  SalesReportProvider(
    this._repository, {
    DateTime Function()? now,
    SalesReportRealtimeConnector? realtimeConnector,
    Duration realtimeDebounce = const Duration(milliseconds: 350),
    Duration realtimeReconnectBaseDelay = const Duration(seconds: 2),
  }) : _now = now ?? DateTime.now,
       _realtimeConnector =
           realtimeConnector ?? ((uri) => WebSocketChannel.connect(uri)),
       _realtimeDebounce = realtimeDebounce,
       _realtimeReconnectBaseDelay = realtimeReconnectBaseDelay;

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
  DateTime get ordersDate =>
      _ordersDate ?? DateTime(_now().year, _now().month, _now().day);
  String? get ordersStoreCode => _ordersStoreCode;
  String? get ordersUserEmail => _ordersUserEmail;
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
  }) async {
    _user = user;
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
    if (admin) await loadAdminList();
    if (orders) {
      await loadOrderCockpit();
      _connectRealtime();
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

  Future<SalesReportOrderCheck?> checkOrder(String orderCode) async {
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
        context: {'orderLength': orderCode.trim().length},
      );
      final result = await _repository.checkOrder(orderCode);
      _checkedOrder = result;
      _successMessage = 'Đã kiểm tra đơn hàng.';
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report order check succeeded',
        context: {
          'orderLength': result.orderCode.length,
          'hasCategory': result.categoryGroup != null,
          'categoryCount': result.categoryGroups.length,
          'itemCount': result.items.length,
          'paymentCount': result.payments.length,
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
    final effectiveQuery =
        query ??
        SalesReportOrdersQuery(
          date: _ordersDate,
          storeCode: _ordersStoreCode,
          userEmail: _ordersUserEmail,
          reportedPage: _reportedOrdersPage,
          unreportedPage: _unreportedOrdersPage,
          limit: _ordersLimit,
        );
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
      _ordersDate = DateTime.tryParse(result.date) ?? effectiveQuery.date;
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
    }
  }

  Future<void> loadReportedOrdersPage(int page) async {
    await loadOrderCockpit(
      query: SalesReportOrdersQuery(
        date: ordersDate,
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
        date: ordersDate,
        storeCode: _ordersStoreCode,
        userEmail: _ordersUserEmail,
        reportedPage: reportedOrdersPage,
        unreportedPage: page < 0 ? 0 : page,
        limit: ordersLimit,
      ),
    );
  }

  Future<void> setOrderFilters({
    DateTime? date,
    String? storeCode,
    String? userEmail,
    bool updateDate = false,
    bool updateStore = false,
    bool updateUser = false,
  }) async {
    if (_isLoadingOrders) return;
    if (updateDate) _ordersDate = date;
    if (updateStore) _ordersStoreCode = _cleanFilter(storeCode);
    if (updateUser) _ordersUserEmail = _cleanFilter(userEmail)?.toLowerCase();
    _reportedOrdersPage = 0;
    _unreportedOrdersPage = 0;
    await loadOrderCockpit();
  }

  SalesReportQuery cockpitExportQuery(String exportType) {
    final date = ordersDate;
    return SalesReportQuery(
      exportType: exportType,
      startDate: date,
      endDate: date,
      reporter: _ordersUserEmail,
      storeIds: _ordersStoreCode == null ? const [] : [_ordersStoreCode!],
    );
  }

  Future<bool> submit(SalesReportInput input, User? user) async {
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
          'hasCustomerName': (input.customerName ?? '').trim().isNotEmpty,
          'hasPhone': (input.customerPhone ?? '').trim().isNotEmpty,
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
      await _repository.create(input);
      _successMessage = 'Đã gửi báo cáo.';
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report submit succeeded',
        context: {
          'type': input.reportType,
          'categoryGroupId': input.categoryGroupId,
          'categoryGroupCount': input.categoryGroupIds.length,
          'hasCustomerName': (input.customerName ?? '').trim().isNotEmpty,
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
          'categoryGroupId': input.categoryGroupId,
          'categoryGroupCount': input.categoryGroupIds.length,
          'hasCustomerName': (input.customerName ?? '').trim().isNotEmpty,
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
    final effectiveQuery =
        query ?? SalesReportQuery(page: _adminPage, limit: _adminLimit);
    final startedAt = DateTime.now();
    final queryContext = _adminQueryLogContext(effectiveQuery);
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

  Future<void> exportCsv({
    SalesReportQuery query = const SalesReportQuery(),
  }) async {
    if (_isExporting) return;
    _isExporting = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
    final startedAt = DateTime.now();
    final queryContext = _adminQueryLogContext(query);
    try {
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report export started',
        context: queryContext,
      );
      final csvBytes = await _repository.exportCsv(query);
      final path = await FilePicker.saveFile(
        dialogTitle: 'Lưu file báo cáo sale',
        fileName:
            'opshub_${_exportTypeFilePart(query.exportType)}_${_timestampForFile()}.csv',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: _ensureUtf8BomForCsv(csvBytes),
        lockParentWindow: true,
      );
      _successMessage = path == null ? 'Đã hủy lưu file.' : 'Đã xuất file.';
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report export succeeded',
        context: {
          ...queryContext,
          'saved': path != null,
          'bytes': csvBytes.length,
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

  Map<String, Object?> _adminQueryLogContext(SalesReportQuery query) {
    return {
      'type': query.reportType,
      'exportType': query.exportType,
      'page': query.page,
      'limit': query.limit,
      'hasOrderCode': (query.orderCode ?? '').trim().isNotEmpty,
      'hasCategoryGroup': (query.categoryGroupId ?? '').trim().isNotEmpty,
      'hasStartDate': query.startDate != null,
      'hasEndDate': query.endDate != null,
      if (query.startDate != null) 'startDate': _dateForLog(query.startDate!),
      if (query.endDate != null) 'endDate': _dateForLog(query.endDate!),
    };
  }

  Map<String, Object?> _ordersQueryLogContext(SalesReportOrdersQuery query) {
    return {
      'reportedPage': query.reportedPage,
      'unreportedPage': query.unreportedPage,
      'limit': query.limit,
      'hasDate': query.date != null,
      'hasStoreFilter': (query.storeCode ?? '').trim().isNotEmpty,
      'hasUserFilter': (query.userEmail ?? '').trim().isNotEmpty,
      if (query.date != null) 'date': _dateForLog(query.date!),
    };
  }

  String? _cleanFilter(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  void _connectRealtime() {
    if (_disposed || _user == null) return;
    final token = ApiClient().authToken?.trim();
    if (token == null || token.isEmpty) {
      unawaited(
        AppLogger.instance.warn(
          'SalesReportRealtime',
          'Sales report realtime connection skipped',
          context: {'reason': 'missing_token'},
        ),
      );
      return;
    }
    _closeRealtime('reconnect');
    try {
      final channel = _realtimeConnector(
        Uri.parse(ApiConstants.realtimeWsUrl(accessToken: token)),
      );
      _realtimeChannel = channel;
      _realtimeReconnectAttempt = 0;
      _realtimeSubscription = channel.stream.listen(
        _handleRealtimeMessage,
        onError: (Object error, StackTrace stackTrace) {
          unawaited(
            AppLogger.instance.error(
              'SalesReportRealtime',
              'Sales report realtime connection failed',
              error: error,
              stackTrace: stackTrace,
            ),
          );
          _handleRealtimeClosed('error');
        },
        onDone: () => _handleRealtimeClosed('done'),
      );
      if (_realtimeConnectedOnce) unawaited(loadOrderCockpit());
      _realtimeConnectedOnce = true;
      unawaited(
        AppLogger.instance.info(
          'SalesReportRealtime',
          'Sales report realtime connected',
          context: {'userId': _user?.id},
        ),
      );
    } catch (error, stackTrace) {
      unawaited(
        AppLogger.instance.error(
          'SalesReportRealtime',
          'Sales report realtime connect failed',
          error: error,
          stackTrace: stackTrace,
        ),
      );
      _scheduleRealtimeReconnect('connect_failed');
    }
  }

  void _handleRealtimeMessage(dynamic message) {
    try {
      final decoded = jsonDecode(message.toString());
      if (decoded is! Map ||
          decoded['type']?.toString() != 'SALES_REPORT_ORDERS_UPDATED') {
        return;
      }
      final payload = decoded['payload'];
      if (payload is! Map || !_isRelevantRealtimePayload(payload)) return;
      _realtimeDebounceTimer?.cancel();
      _realtimeDebounceTimer = Timer(_realtimeDebounce, () {
        if (!_disposed) unawaited(loadOrderCockpit());
      });
      unawaited(
        AppLogger.instance.info(
          'SalesReportRealtime',
          'Sales report realtime update received',
          context: {
            'newOrderCount': payload['newOrderCount'],
            'dateCount': payload['dates'] is List
                ? (payload['dates'] as List).length
                : 0,
          },
        ),
      );
    } catch (error) {
      unawaited(
        AppLogger.instance.warn(
          'SalesReportRealtime',
          'Sales report realtime event ignored',
          context: {'error': error.toString()},
        ),
      );
    }
  }

  bool _isRelevantRealtimePayload(Map<dynamic, dynamic> payload) {
    final dates =
        (payload['dates'] is List ? payload['dates'] as List : const [])
            .map((value) => value.toString())
            .toSet();
    if (dates.isNotEmpty && !dates.contains(_dateForLog(ordersDate))) {
      return false;
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

  void _handleRealtimeClosed(String reason) {
    _realtimeSubscription = null;
    _realtimeChannel = null;
    _scheduleRealtimeReconnect(reason);
  }

  void _scheduleRealtimeReconnect(String reason) {
    if (_disposed || _realtimeReconnectTimer != null) return;
    final multiplier = 1 << math.min(_realtimeReconnectAttempt, 4);
    _realtimeReconnectAttempt += 1;
    final delay = Duration(
      milliseconds: math.min(
        _realtimeReconnectBaseDelay.inMilliseconds * multiplier,
        const Duration(seconds: 30).inMilliseconds,
      ),
    );
    _realtimeReconnectTimer = Timer(delay, () {
      _realtimeReconnectTimer = null;
      _connectRealtime();
    });
    unawaited(
      AppLogger.instance.info(
        'SalesReportRealtime',
        'Sales report realtime reconnect scheduled',
        context: {'reason': reason, 'delayMs': delay.inMilliseconds},
      ),
    );
  }

  void _closeRealtime(String reason) {
    _realtimeReconnectTimer?.cancel();
    _realtimeReconnectTimer = null;
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = null;
    unawaited(_realtimeSubscription?.cancel());
    _realtimeSubscription = null;
    unawaited(_realtimeChannel?.sink.close());
    _realtimeChannel = null;
    if (reason != 'reconnect') {
      unawaited(
        AppLogger.instance.info(
          'SalesReportRealtime',
          'Sales report realtime disconnected',
          context: {'reason': reason},
        ),
      );
    }
  }

  @visibleForTesting
  void handleRealtimeMessageForTesting(dynamic message) {
    _handleRealtimeMessage(message);
  }

  @override
  void dispose() {
    _disposed = true;
    _closeRealtime('dispose');
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
