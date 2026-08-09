import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_combobox.dart';
import '../../../../app/widgets/app_dialogs.dart';
import '../../../../app/widgets/app_filter_dropdowns.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_pagination.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/app_toast.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/realtime_connection_manager.dart';
import '../../../../core/utils/date_range_defaults.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/domain/entities/store_branch.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/sales_report_repository.dart';
import '../../domain/sales_report.dart';
import '../providers/sales_report_provider.dart';
import 'sales_report_screen.dart';
import 'sales_report_import_dialog.dart';

const _outcomeNotPurchased = 'NOT_PURCHASED';
const _outcomePurchased = 'PURCHASED';
const _outcomePurchasedElsewhere = 'PURCHASED_ELSEWHERE';
const _outcomeNoLongerInterested = 'NO_LONGER_INTERESTED';
const _maxFollowUpDateRangeDays = 90;

typedef SalesReportFollowUpHistorySaver =
    Future<String?> Function({
      required String fileName,
      required Uint8List bytes,
    });

typedef SalesReportCategoryLoader =
    Future<List<SalesReportCategoryGroup>> Function();

const _reasonOptions = <String, String>{
  'NOT_SOLD': 'Chưa kinh doanh',
  'SERVICE': 'Dịch vụ',
  'CUSTOMER_BROWSING': 'Khách tham khảo',
  'NO_DEMO_STOCK': 'Không có hàng trải nghiệm',
  'NO_AVAILABLE_STOCK': 'Không có sẵn hàng',
  'PRICE_HESITATION': 'Phân vân giá',
  'COMPARE_COMPETITOR': 'So sánh đối thủ',
  'SPEC_NOT_COMPATIBLE': 'Thông số kỹ thuật chưa tương thích',
  'OTHER': 'Khác',
};

class NotPurchasedCustomersScreen extends StatefulWidget {
  final SalesReportRepository? repository;
  final AuthRepository? authRepository;
  final Future<List<StoreBranch>> Function()? storeLoader;
  final SalesReportCategoryLoader? categoryLoader;
  final RealtimeClient? realtimeClient;
  final Duration realtimeDebounce;
  final Duration realtimeMaxWait;
  final SalesReportImportFilePicker? importFilePicker;
  final SalesReportFollowUpHistorySaver? historySaver;
  final DateTime Function()? now;

  const NotPurchasedCustomersScreen({
    super.key,
    this.repository,
    this.authRepository,
    this.storeLoader,
    this.categoryLoader,
    this.realtimeClient,
    this.realtimeDebounce = const Duration(seconds: 2),
    this.realtimeMaxWait = const Duration(seconds: 5),
    this.importFilePicker,
    this.historySaver,
    this.now,
  });

  @override
  State<NotPurchasedCustomersScreen> createState() =>
      _NotPurchasedCustomersScreenState();
}

class _NotPurchasedCustomersScreenState
    extends State<NotPurchasedCustomersScreen> {
  static const String _realtimeTopic = 'sales-report.orders';
  static const String _realtimeKind = 'SALES_REPORT_ORDERS_UPDATED';

  late final SalesReportRepository _repository;
  late final Future<List<StoreBranch>> Function() _storeLoader;
  late final SalesReportCategoryLoader _categoryLoader;
  late final RealtimeClient _realtimeClient;
  final _searchController = TextEditingController();
  SalesReportFollowUpPage? _data;
  Timer? _searchDebounce;
  String _status = 'OPEN';
  int _page = 0;
  bool _loading = false;
  bool _loadQueued = false;
  int? _queuedPage;
  String? _error;
  StreamSubscription<RealtimeEnvelope>? _realtimeEventSubscription;
  StreamSubscription<RealtimeSyncReason>? _realtimeSyncSubscription;
  Timer? _realtimeDebounceTimer;
  Timer? _realtimeMaxWaitTimer;
  bool _realtimeRefreshDirty = false;
  bool _realtimeRefreshInFlight = false;
  bool _isSuperAdmin = false;
  bool _canImport = false;
  bool _exportingHistory = false;
  bool _storeLoading = false;
  String? _storeError;
  bool _categoryLoading = false;
  String? _categoryError;
  String? _selectedStoreCode;
  String? _selectedCategoryGroupId;
  bool _advancedFiltersOpen = false;
  DateTime? _startDate;
  DateTime? _endDate;
  List<StoreBranch> _stores = const [];
  List<SalesReportCategoryGroup> _categories = const [];

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? SalesReportRepository(ApiClient());
    final authRepository = widget.authRepository ?? AuthRepository(ApiClient());
    _storeLoader = widget.storeLoader ?? authRepository.getStores;
    _categoryLoader =
        widget.categoryLoader ??
        () => _repository.fetchCategories(admin: _canImport);
    _realtimeClient =
        widget.realtimeClient ?? RealtimeConnectionManager.instance;
    _realtimeEventSubscription = _realtimeClient.events.listen(
      _handleRealtimeEnvelope,
    );
    _realtimeSyncSubscription = _realtimeClient.syncRequests.listen(
      _handleRealtimeSyncRequest,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAccess();
      unawaited(_load());
    });
  }

  void _initializeAccess() {
    final user = Provider.of<AuthProvider?>(context, listen: false)?.user;
    final isSuperAdmin = user?.isSuperAdmin == true;
    final canImport = user?.canUseFeature('ADMIN_SALES_REPORTS') == true;
    if (_isSuperAdmin != isSuperAdmin || _canImport != canImport) {
      setState(() {
        _isSuperAdmin = isSuperAdmin;
        _canImport = canImport;
      });
    }
    if (isSuperAdmin) {
      unawaited(_loadSuperAdminStores());
    } else {
      setState(() {
        _stores = user?.assignedStores ?? const [];
        _storeError = null;
      });
      unawaited(
        AppLogger.instance.info(
          'SalesReportFollowUp',
          'Scoped showroom options resolved from authenticated profile',
          context: {'count': _stores.length, 'isSuperAdmin': false},
        ),
      );
    }
    unawaited(_loadCategories());
  }

  Future<void> _loadSuperAdminStores() async {
    if (!_isSuperAdmin || _storeLoading) return;
    setState(() {
      _storeLoading = true;
      _storeError = null;
    });
    final startedAt = DateTime.now();
    await AppLogger.instance.info(
      'SalesReportFollowUp',
      'Super Admin showroom filter load started',
    );
    try {
      final stores = await _storeLoader();
      if (!mounted) return;
      setState(() => _stores = stores);
      await AppLogger.instance.info(
        'SalesReportFollowUp',
        'Super Admin showroom filter load succeeded',
        context: {
          'count': stores.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      if (mounted) {
        setState(
          () => _storeError =
              'Chưa tải được danh sách showroom. Vui lòng thử lại.',
        );
      }
      await AppLogger.instance.error(
        'SalesReportFollowUp',
        'Super Admin showroom filter load failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } finally {
      if (mounted) setState(() => _storeLoading = false);
    }
  }

  Future<void> _loadCategories() async {
    if (_categoryLoading) return;
    setState(() {
      _categoryLoading = true;
      _categoryError = null;
    });
    final startedAt = DateTime.now();
    await AppLogger.instance.info(
      'SalesReportFollowUp',
      'Follow-up category filter load started',
      context: {'usesAdminCatalog': _canImport},
    );
    try {
      final categories = await _categoryLoader();
      if (!mounted) return;
      setState(() => _categories = categories);
      await AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up category filter load succeeded',
        context: {
          'count': categories.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      if (mounted) {
        setState(
          () => _categoryError =
              'Chưa tải được danh sách ngành hàng. Vui lòng thử lại.',
        );
      }
      await AppLogger.instance.error(
        'SalesReportFollowUp',
        'Follow-up category filter load failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } finally {
      if (mounted) setState(() => _categoryLoading = false);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _cancelRealtimeTimers();
    unawaited(_realtimeEventSubscription?.cancel());
    unawaited(_realtimeSyncSubscription?.cancel());
    _searchController.dispose();
    super.dispose();
  }

  void _handleRealtimeEnvelope(RealtimeEnvelope envelope) {
    if (!mounted ||
        envelope.topic != _realtimeTopic ||
        envelope.kind != _realtimeKind ||
        !envelope.data['source'].toString().startsWith('follow_up_')) {
      return;
    }
    _scheduleRealtimeRefresh();
    unawaited(
      AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up realtime invalidation received',
        context: {
          'eventId': envelope.id,
          'sequence': envelope.sequence,
          'source': envelope.data['source'],
        },
      ),
    );
  }

  void _handleRealtimeSyncRequest(RealtimeSyncReason reason) {
    if (!mounted) return;
    unawaited(
      AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up realtime sync requested',
        context: {'reason': reason.name},
      ),
    );
    _scheduleRealtimeRefresh(immediate: true);
  }

  void _scheduleRealtimeRefresh({bool immediate = false}) {
    if (!mounted) return;
    _realtimeRefreshDirty = true;
    if (immediate) {
      _cancelRealtimeTimers();
      unawaited(_refreshFromRealtime());
      return;
    }
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = Timer(
      widget.realtimeDebounce,
      () => unawaited(_refreshFromRealtime()),
    );
    _realtimeMaxWaitTimer ??= Timer(
      widget.realtimeMaxWait,
      () => unawaited(_refreshFromRealtime()),
    );
  }

  Future<void> _refreshFromRealtime() async {
    _cancelRealtimeTimers();
    if (!mounted || !_realtimeRefreshDirty) return;
    if (_loading) return;
    if (_realtimeRefreshInFlight) return;
    _realtimeRefreshDirty = false;
    _realtimeRefreshInFlight = true;
    final startedAt = DateTime.now();
    try {
      await AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up realtime refresh started',
      );
      await _load();
      await AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up realtime refresh completed',
        context: {
          'succeeded': _error == null,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } finally {
      _realtimeRefreshInFlight = false;
      if (_realtimeRefreshDirty && mounted) {
        _scheduleRealtimeRefresh(immediate: true);
      }
    }
  }

  void _cancelRealtimeTimers() {
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = null;
    _realtimeMaxWaitTimer?.cancel();
    _realtimeMaxWaitTimer = null;
  }

  Future<void> _load({int? page}) async {
    if (_loading) {
      _loadQueued = true;
      _queuedPage = page ?? _queuedPage;
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      if (page != null) _page = page;
    });
    final startedAt = DateTime.now();
    final requestedStatus = _status;
    final requestedPage = _page;
    final requestedSearch = _searchController.text;
    final requestedStoreCode = _selectedStoreCode;
    final requestedCategoryGroupId = _selectedCategoryGroupId;
    final effectiveStartDate = _effectiveStartDate;
    final effectiveEndDate = _effectiveEndDate;
    bool requestMatchesCurrent() =>
        requestedStatus == _status &&
        requestedPage == _page &&
        requestedSearch == _searchController.text &&
        requestedStoreCode == _selectedStoreCode &&
        requestedCategoryGroupId == _selectedCategoryGroupId &&
        effectiveStartDate == _effectiveStartDate &&
        effectiveEndDate == _effectiveEndDate;
    try {
      await AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up customer list load started',
        context: {
          'status': _status,
          'page': _page,
          'hasSearch': _searchController.text.trim().isNotEmpty,
          'storeCode': _selectedStoreCode,
          'categoryGroupId': _selectedCategoryGroupId,
          'startDate': _apiDate(effectiveStartDate),
          'endDate': _apiDate(effectiveEndDate),
          'usesImplicitDateRange': _startDate == null && _endDate == null,
        },
      );
      final result = await _repository.fetchFollowUpCases(
        status: requestedStatus,
        search: requestedSearch,
        storeCode: requestedStoreCode,
        categoryGroupId: requestedCategoryGroupId,
        startDate: effectiveStartDate,
        endDate: effectiveEndDate,
        page: requestedPage,
      );
      if (!mounted) return;
      if (requestMatchesCurrent()) setState(() => _data = result);
      await AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up customer list load succeeded',
        context: {
          'status': _status,
          'page': result.page,
          'count': result.items.length,
          'total': result.total,
          'managedScope': result.managedScope,
          'contactGracePeriodActive': result.contactGracePeriodActive,
          'contactGracePeriodEndsAt': result.contactGracePeriodEndsAt
              ?.toUtc()
              .toIso8601String(),
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      if (mounted && requestMatchesCurrent()) {
        setState(
          () =>
              _error = 'Chưa tải được danh sách khách hàng. Vui lòng thử lại.',
        );
      }
      await AppLogger.instance.error(
        'SalesReportFollowUp',
        'Follow-up customer list load failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'status': _status,
          'page': _page,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_loadQueued) {
          final queuedPage = _queuedPage;
          _loadQueued = false;
          _queuedPage = null;
          unawaited(_load(page: queuedPage));
        }
        if (_realtimeRefreshDirty && !_realtimeRefreshInFlight) {
          _scheduleRealtimeRefresh(immediate: true);
        }
      }
    }
  }

  void _searchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) unawaited(_load(page: 0));
    });
  }

  DateTime get _effectiveEndDate =>
      _endDate ?? appImplicitDateRangeEnd((widget.now ?? DateTime.now)());

  DateTime get _effectiveStartDate =>
      _startDate ?? appImplicitDateRangeStart((widget.now ?? DateTime.now)());

  Future<void> _setDateRange(DateTime? start, DateTime? end) async {
    if (start != null && end != null) {
      final days = end.difference(start).inDays + 1;
      if (days > _maxFollowUpDateRangeDays) {
        AppToast.show(
          context,
          const SnackBar(
            content: Text('Chỉ có thể chọn tối đa 90 ngày. Vui lòng chọn lại.'),
          ),
        );
        await AppLogger.instance.warn(
          'SalesReportFollowUp',
          'Follow-up date range rejected',
          context: {'days': days, 'maximumDays': _maxFollowUpDateRangeDays},
        );
        return;
      }
    }
    setState(() {
      _startDate = start;
      _endDate = end;
    });
    await AppLogger.instance.info(
      'SalesReportFollowUp',
      'Follow-up date range changed',
      context: {
        'hasExplicitRange': start != null && end != null,
        'startDate': _apiDate(_effectiveStartDate),
        'endDate': _apiDate(_effectiveEndDate),
      },
    );
    if (mounted) await _load(page: 0);
  }

  Future<void> _openCase(SalesReportFollowUpCase item) async {
    await AppLogger.instance.info(
      'SalesReportFollowUp',
      'Follow-up customer dialog opened',
      context: {'caseId': item.id, 'status': item.status},
    );
    if (!mounted) return;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) =>
          _FollowUpCaseDialog(repository: _repository, initial: item),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _openImport() async {
    await AppLogger.instance.info(
      'SalesReportImport',
      'Historical customer import dialog opened from follow-up workspace',
    );
    if (!mounted) return;
    final changed = await showSalesReportImportDialog(
      context: context,
      repository: _repository,
      filePicker: widget.importFilePicker,
    );
    if (changed == true && mounted) await _load(page: 0);
  }

  Future<void> _exportHistory() async {
    if (_exportingHistory || _data?.managedScope != true) return;
    setState(() => _exportingHistory = true);
    final startedAt = DateTime.now();
    final startDate = _effectiveStartDate;
    final endDate = _effectiveEndDate;
    final contextData = <String, Object?>{
      'startDate': _apiDate(startDate),
      'endDate': _apiDate(endDate),
      'storeCode': _selectedStoreCode,
      'categoryGroupId': _selectedCategoryGroupId,
      'hasSearch': _searchController.text.trim().isNotEmpty,
    };
    try {
      await AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up history export started',
        context: contextData,
      );
      final bytes = await _repository.exportFollowUpHistory(
        search: _searchController.text,
        storeCode: _selectedStoreCode,
        categoryGroupId: _selectedCategoryGroupId,
        startDate: startDate,
        endDate: endDate,
      );
      final fileName =
          'opshub-lich-su-cham-soc-${_apiDate(startDate).replaceAll('-', '')}-${_apiDate(endDate).replaceAll('-', '')}.xlsx';
      final saver = widget.historySaver ?? _saveHistoryFile;
      final path = await saver(fileName: fileName, bytes: bytes);
      if (!mounted) return;
      AppToast.show(
        context,
        SnackBar(
          content: Text(
            path == null
                ? 'Đã hủy lưu file lịch sử chăm sóc.'
                : 'Đã tải lịch sử chăm sóc.',
          ),
        ),
      );
      await AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up history export succeeded',
        context: {
          ...contextData,
          'saved': path != null,
          'bytes': bytes.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      if (mounted) {
        final message = error is ApiException
            ? error.message
            : 'Chưa tải được lịch sử chăm sóc. Vui lòng thử lại.';
        AppToast.show(context, SnackBar(content: Text(message)));
      }
      await AppLogger.instance.error(
        'SalesReportFollowUp',
        'Follow-up history export failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          ...contextData,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } finally {
      if (mounted) setState(() => _exportingHistory = false);
    }
  }

  Future<String?> _saveHistoryFile({
    required String fileName,
    required Uint8List bytes,
  }) {
    return FilePicker.saveFile(
      dialogTitle: 'Lưu lịch sử chăm sóc',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      bytes: bytes,
      lockParentWindow: true,
    );
  }

  String _apiDate(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final visibleItems =
        data?.items
            .where(
              (item) => data.contactGracePeriodActive || item.hasVisibleContact,
            )
            .toList(growable: false) ??
        const <SalesReportFollowUpCase>[];
    return LayoutBuilder(
      builder: (context, routeConstraints) => AppResponsiveScrollView(
        maxWidth: AppLayoutTokens.commandWorkspaceMaxWidth,
        padding: AppLayoutTokens.commandWorkspacePagePaddingFor(
          routeConstraints.maxWidth,
        ),
        onRefresh: _load,
        refreshLogSource: 'SalesReportFollowUp',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FollowUpStatusTabs(
              status: _status,
              onChanged: (status) {
                setState(() => _status = status);
                unawaited(
                  AppLogger.instance.info(
                    'SalesReportFollowUp',
                    'Follow-up list status changed',
                    context: {'status': status},
                  ),
                );
                unawaited(_load(page: 0));
              },
            ),
            const SizedBox(height: 16),
            _buildCommandSurface(
              context,
              compact:
                  routeConstraints.maxWidth < AppLayoutTokens.compactBreakpoint,
              canExport: data?.managedScope == true,
            ),
            if (data != null) ...[
              const SizedBox(height: 12),
              _FollowUpResultSummary(data: data),
            ],
            const SizedBox(height: 16),
            if (_loading && data == null)
              AppStatePanel.loading(
                title: _status == 'HISTORY'
                    ? 'Đang tải lịch sử chăm sóc...'
                    : 'Đang tải danh sách khách hàng...',
              )
            else if (_error != null)
              AppStatePanel.error(
                title: 'Chưa tải được danh sách',
                message: _error,
                actionLabel: 'Thử lại',
                onAction: _load,
              )
            else if (data == null || visibleItems.isEmpty)
              AppStatePanel.empty(
                title: _status == 'OPEN'
                    ? 'Không có khách hàng cần chăm sóc'
                    : _status == 'HISTORY'
                    ? 'Chưa có lịch sử chăm sóc'
                    : 'Chưa có hồ sơ đã ẩn',
                message: data?.contactGracePeriodActive == true
                    ? 'Chưa có hồ sơ khách hàng chưa mua trong phạm vi được phân công.'
                    : 'Màn hình chỉ hiển thị khách có số điện thoại hợp lệ hoặc đã lưu kênh Zalo cá nhân/Zalo OA.',
                actionLabel: 'Tải lại',
                onAction: _load,
              )
            else ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 16.0;
                  final width = constraints.maxWidth;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final item in visibleItems)
                        SizedBox(
                          width: width,
                          child: _FollowUpCard(
                            item: item,
                            showStore: data.managedScope,
                            onTap: () => _openCase(item),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              AppPaginationControls(
                pageIndex: data.page,
                totalItems: data.total,
                itemLabel: 'khách hàng',
                onPrevious: data.page > 0 && !_loading
                    ? () => _load(page: data.page - 1)
                    : null,
                onNext: data.hasMore && !_loading
                    ? () => _load(page: data.page + 1)
                    : null,
                onRefresh: _loading ? null : _load,
                isRefreshing: _loading,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCommandSurface(
    BuildContext context, {
    required bool compact,
    required bool canExport,
  }) {
    final search = AppCommandTextInput(
      key: const Key('follow-up-search-filter'),
      controller: _searchController,
      hintText: 'Tìm theo tên, điện thoại hoặc Zalo',
      semanticLabel: 'Tìm khách hàng theo tên, điện thoại hoặc Zalo',
      onChanged: _searchChanged,
    );
    final dateRangeFilter = AppDateRangeDropdown(
      label: 'Khoảng ngày',
      start: _startDate,
      end: _endDate,
      onChanged: (start, end) => unawaited(_setDateRange(start, end)),
      fieldStyle: true,
      fieldLabelInside: true,
      showEmptyRangeHelperText: false,
      firstDate: DateTime(2020),
      lastDate: (widget.now ?? DateTime.now)(),
    );
    final storeFilter = _FollowUpFilterField(
      control: AppCombobox<String>.single(
        key: const Key('follow-up-store-filter'),
        label: 'Showroom',
        value: _selectedStoreCode,
        emptyLabel: _storeLoading
            ? 'Đang tải danh sách showroom'
            : _storeOptions.isEmpty
            ? 'Chưa có showroom trong phạm vi'
            : 'Tất cả showroom',
        icon: PhosphorIconsRegular.storefront,
        showLabel: false,
        fixedHeight: 48,
        closedIcon: PhosphorIconsRegular.caretDown,
        enabled: !_storeLoading && _storeOptions.isNotEmpty,
        options: _storeOptions,
        onChanged: (value) {
          setState(() => _selectedStoreCode = value);
          unawaited(
            AppLogger.instance.info(
              'SalesReportFollowUp',
              'Follow-up showroom filter changed',
              context: {'storeCode': value, 'isSuperAdmin': _isSuperAdmin},
            ),
          );
          unawaited(_load(page: 0));
        },
      ),
      error: _storeError,
      errorKey: const Key('follow-up-store-error'),
      retryKey: const Key('follow-up-store-retry'),
      retryTooltip: 'Tải lại danh sách showroom',
      onRetry: _isSuperAdmin && !_storeLoading
          ? () => unawaited(_loadSuperAdminStores())
          : null,
    );
    final categoryFilter = _FollowUpFilterField(
      control: AppCombobox<String>.single(
        key: const Key('follow-up-category-filter'),
        label: 'Ngành hàng',
        value: _selectedCategoryGroupId,
        emptyLabel: _categoryLoading
            ? 'Đang tải danh sách ngành hàng'
            : _categoryOptions.isEmpty
            ? 'Chưa có ngành hàng khả dụng'
            : 'Tất cả ngành hàng',
        icon: PhosphorIconsRegular.squaresFour,
        showLabel: false,
        fixedHeight: 48,
        closedIcon: PhosphorIconsRegular.caretDown,
        enabled: !_categoryLoading && _categoryOptions.isNotEmpty,
        options: _categoryOptions,
        onChanged: (value) {
          setState(() => _selectedCategoryGroupId = value);
          unawaited(
            AppLogger.instance.info(
              'SalesReportFollowUp',
              'Follow-up category filter changed',
              context: {'categoryGroupId': value},
            ),
          );
          unawaited(_load(page: 0));
        },
      ),
      error: _categoryError,
      errorKey: const Key('follow-up-category-error'),
      retryKey: const Key('follow-up-category-retry'),
      retryTooltip: 'Tải lại danh sách ngành hàng',
      onRetry: _categoryLoading ? null : () => unawaited(_loadCategories()),
    );
    final advancedFilters = <Widget>[
      dateRangeFilter,
      storeFilter,
      categoryFilter,
    ];
    final actions = _buildPermissionActions(
      context,
      compact: compact,
      canExport: canExport,
    );
    return AppSurfaceCard(
      key: const Key('follow-up-filter-surface'),
      radius: AppRadius.cardFigma,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact) ...[
            search,
            const SizedBox(height: 12),
            Semantics(
              button: true,
              expanded: _advancedFiltersOpen,
              label: 'Tìm kiếm nâng cao',
              child: AppSecondaryButton(
                key: const Key('follow-up-advanced-filter-toggle'),
                onPressed: () {
                  setState(() => _advancedFiltersOpen = !_advancedFiltersOpen);
                  unawaited(
                    AppLogger.instance.info(
                      'SalesReportFollowUp',
                      'Follow-up advanced filters toggled',
                      context: {'open': _advancedFiltersOpen},
                    ),
                  );
                },
                icon: _advancedFiltersOpen
                    ? PhosphorIconsRegular.caretUp
                    : PhosphorIconsRegular.caretDown,
                label: 'Tìm kiếm nâng cao',
                expand: true,
                size: AppButtonSize.medium,
                height: 48,
              ),
            ),
            if (_advancedFiltersOpen)
              for (final field in advancedFilters) ...[
                const SizedBox(height: 12),
                field,
              ],
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: search),
                for (final field in advancedFilters) ...[
                  const SizedBox(width: 12),
                  Expanded(child: field),
                ],
              ],
            ),
          if (actions != null) ...[const SizedBox(height: 12), actions],
        ],
      ),
    );
  }

  Widget? _buildPermissionActions(
    BuildContext context, {
    required bool compact,
    required bool canExport,
  }) {
    if (!canExport && !_canImport) return null;
    final export = AppSecondaryButton(
      key: const Key('follow-up-export-action'),
      onPressed: canExport ? _exportHistory : null,
      icon: PhosphorIconsRegular.downloadSimple,
      label: 'Tải lịch sử chăm sóc',
      isLoading: _exportingHistory,
      loadingLabel: 'Đang tạo file...',
      expand: true,
      size: AppButtonSize.medium,
      height: 48,
    );
    final import = AppPrimaryButton(
      key: const Key('follow-up-import-action'),
      onPressed: _canImport ? _openImport : null,
      label: 'Nhập Excel',
      size: AppButtonSize.medium,
      height: 48,
    );
    if (compact) {
      final stackActions =
          _canImport &&
          canExport &&
          MediaQuery.textScalerOf(context).scale(14) > 17;
      if (stackActions) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [export, const SizedBox(height: 8), import],
        );
      }
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (canExport) Expanded(flex: _canImport ? 5 : 1, child: export),
          if (canExport && _canImport) const SizedBox(width: 8),
          if (_canImport) Expanded(flex: canExport ? 3 : 1, child: import),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (canExport) SizedBox(width: 220, child: export),
        if (canExport && _canImport) const SizedBox(width: 12),
        if (_canImport) SizedBox(width: 140, child: import),
      ],
    );
  }

  List<AppComboboxOption<String>> get _storeOptions {
    final seen = <String>{};
    final options = <AppComboboxOption<String>>[];
    for (final store in _stores) {
      final code = store.storeId.trim().toUpperCase();
      if (code.isEmpty || !seen.add(code)) continue;
      final name = store.storeName.trim();
      options.add(
        AppComboboxOption<String>(
          value: code,
          label: name.isEmpty ? code : '$code - $name',
          searchKeywords: [code, name],
        ),
      );
    }
    final selected = _selectedStoreCode?.trim().toUpperCase();
    if (selected != null && selected.isNotEmpty && seen.add(selected)) {
      options.add(
        AppComboboxOption<String>(
          value: selected,
          label: '$selected - Không còn trong phạm vi',
          searchKeywords: [selected],
        ),
      );
    }
    options.sort((a, b) => a.value.compareTo(b.value));
    return options;
  }

  List<AppComboboxOption<String>> get _categoryOptions {
    final seen = <String>{};
    final options = <AppComboboxOption<String>>[];
    for (final category in _categories) {
      final id = category.id.trim().toUpperCase();
      if (id.isEmpty || !seen.add(id)) continue;
      final vietnameseName = category.catGroupNameVi.trim();
      final englishName = category.catGroupName.trim();
      options.add(
        AppComboboxOption<String>(
          value: id,
          label: vietnameseName.isEmpty ? id : vietnameseName,
          subtitle: vietnameseName == englishName || englishName.isEmpty
              ? null
              : englishName,
          searchKeywords: [id, vietnameseName, englishName],
        ),
      );
    }
    final selected = _selectedCategoryGroupId?.trim().toUpperCase();
    if (selected != null && selected.isNotEmpty && seen.add(selected)) {
      options.add(
        AppComboboxOption<String>(
          value: selected,
          label: '$selected - Không còn khả dụng',
          searchKeywords: [selected],
        ),
      );
    }
    options.sort((a, b) => a.label.compareTo(b.label));
    return options;
  }
}

class _FollowUpResultSummary extends StatelessWidget {
  final SalesReportFollowUpPage data;

  const _FollowUpResultSummary({required this.data});

  @override
  Widget build(BuildContext context) {
    final graceEndsAt = data.contactGracePeriodEndsAt?.toLocal();
    return Column(
      key: const Key('follow-up-result-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppStatusChip(
          key: const Key('follow-up-total-chip'),
          label: '${data.total} hồ sơ',
          color: AppColors.infoOf(context),
        ),
        if (data.contactGracePeriodActive && graceEndsAt != null) ...[
          const SizedBox(height: 6),
          Text(
            'Tạm hiển thị toàn bộ khách chưa mua đến '
            '${DateFormat('HH:mm dd/MM/yyyy').format(graceEndsAt)}.',
            key: const Key('follow-up-contact-grace-message'),
            style: AppTextStyles.bodyS.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ],
      ],
    );
  }
}

class _FollowUpStatusTabs extends StatelessWidget {
  final String status;
  final ValueChanged<String> onChanged;

  const _FollowUpStatusTabs({required this.status, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const tabs = [
      ('OPEN', 'Cần chăm sóc'),
      ('HISTORY', 'Lịch sử'),
      ('HIDDEN', 'Đã ẩn'),
    ];
    return Row(
      children: [
        for (final tab in tabs)
          Expanded(
            child: Semantics(
              button: true,
              selected: status == tab.$1,
              label: tab.$2,
              child: InkWell(
                onTap: () => onChanged(tab.$1),
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: status == tab.$1
                            ? AppColors.primaryOf(context)
                            : AppColors.borderOf(context),
                        width: status == tab.$1 ? 3 : 1,
                      ),
                    ),
                  ),
                  child: ExcludeSemantics(
                    child: Text(
                      tab.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelM.copyWith(
                        color: status == tab.$1
                            ? AppColors.primaryOf(context)
                            : AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FollowUpFilterField extends StatelessWidget {
  final Widget control;
  final String? error;
  final Key errorKey;
  final Key retryKey;
  final String retryTooltip;
  final VoidCallback? onRetry;

  const _FollowUpFilterField({
    required this.control,
    required this.error,
    required this.errorKey,
    required this.retryKey,
    required this.retryTooltip,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      control,
      if (error != null) ...[
        const SizedBox(height: 8),
        Row(
          key: errorKey,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                error!,
                style: AppTextStyles.bodyS.copyWith(
                  color: AppColors.errorOf(context),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AppLinkButton(
              key: retryKey,
              onPressed: onRetry,
              icon: PhosphorIconsRegular.arrowsClockwise,
              label: 'Thử lại',
              tooltip: retryTooltip,
              compact: true,
            ),
          ],
        ),
      ],
    ],
  );
}

class _FollowUpCard extends StatelessWidget {
  final SalesReportFollowUpCase item;
  final bool showStore;
  final VoidCallback onTap;

  const _FollowUpCard({
    required this.item,
    required this.showStore,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tone = _careColor(context, item.careAgeDays);
    final contact = item.contactSummary;
    return AppSurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _text(item.customerName, 'Khách chưa cập nhật tên'),
                  style: AppTextStyles.titleEmphasis,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppLinkButton(
                onPressed: onTap,
                icon: PhosphorIconsRegular.arrowSquareOut,
                label: 'Mở hồ sơ',
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 6),
          _InfoLine(icon: PhosphorIconsRegular.phone, text: contact),
          _InfoLine(
            icon: PhosphorIconsRegular.shapes,
            text: item.categoryNames.isEmpty
                ? 'Chưa có ngành hàng'
                : item.categoryNames.join(', '),
          ),
          if (showStore && (item.storeCode ?? '').trim().isNotEmpty)
            _InfoLine(
              icon: PhosphorIconsRegular.storefront,
              text: 'Mã showroom: ${item.storeCode}',
            ),
          const SizedBox(height: 10),
          AppStatusChip(
            label: item.lastFollowUpAt == null
                ? '${item.careAgeDays} ngày • Chưa chăm sóc lại'
                : '${item.careAgeDays} ngày • Đã liên hệ ${item.followUpCount} lần',
            color: tone,
          ),
          if ((item.assigneeName ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Phụ trách: ${item.assigneeName}',
              style: AppTextStyles.bodyS.copyWith(
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FollowUpCaseDialog extends StatefulWidget {
  final SalesReportRepository repository;
  final SalesReportFollowUpCase initial;

  const _FollowUpCaseDialog({required this.repository, required this.initial});

  @override
  State<_FollowUpCaseDialog> createState() => _FollowUpCaseDialogState();
}

class _FollowUpCaseDialogState extends State<_FollowUpCaseDialog> {
  late SalesReportFollowUpCase _case;
  final _otherReasonController = TextEditingController();
  String _outcome = _outcomeNotPurchased;
  String? _reason;
  bool _loading = true;
  bool _saving = false;
  bool _purchaseMode = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _case = widget.initial;
    unawaited(_loadDetail());
  }

  @override
  void dispose() {
    _otherReasonController.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final startedAt = DateTime.now();
    const maxAttempts = 3;
    Object? lastError;
    StackTrace? lastStackTrace;
    await AppLogger.instance.info(
      'SalesReportFollowUp',
      'Follow-up case detail load started',
      context: {'caseId': _case.id, 'maxAttempts': maxAttempts},
    );
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final detail = await widget.repository.fetchFollowUpCase(_case.id);
        if (mounted) {
          setState(() {
            _case = detail;
            _error = null;
            _loading = false;
          });
        }
        await AppLogger.instance.info(
          'SalesReportFollowUp',
          'Follow-up case detail load succeeded',
          context: {
            'caseId': _case.id,
            'attempt': attempt,
            'historyCount': detail.entries.length,
            'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
          },
        );
        return;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        final retryable = _isRetryableDetailError(error);
        if (!retryable || attempt >= maxAttempts) break;
        final delay = Duration(milliseconds: 350 * attempt);
        await AppLogger.instance.warn(
          'SalesReportFollowUp',
          'Follow-up case detail load retry scheduled',
          context: {
            'caseId': _case.id,
            'attempt': attempt,
            'nextAttempt': attempt + 1,
            'delayMs': delay.inMilliseconds,
            'retryable': retryable,
          },
        );
        await Future<void>.delayed(delay);
      }
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _error = 'Không tải được lịch sử chăm sóc. Vui lòng thử lại.';
      });
    }
    await AppLogger.instance.error(
      'SalesReportFollowUp',
      'Follow-up case detail load failed',
      error: lastError,
      stackTrace: lastStackTrace,
      context: {
        'caseId': _case.id,
        'attempts': maxAttempts,
        'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
      },
    );
  }

  bool _isRetryableDetailError(Object error) {
    if (error is ApiException &&
        (error.statusCode == 401 ||
            error.statusCode == 403 ||
            error.statusCode == 404)) {
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_outcome == _outcomeNotPurchased && _reason == null) {
      setState(() => _error = 'Vui lòng chọn lý do khách chưa mua hàng.');
      return;
    }
    if (_reason == 'OTHER' && _otherReasonController.text.trim().isEmpty) {
      setState(() => _error = 'Vui lòng nhập lý do khác.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up entry submit started',
        context: {
          'caseId': _case.id,
          'outcome': _outcome,
          'sequenceNumber': _case.nextSequenceNumber,
        },
      );
      await widget.repository.createFollowUpEntry(
        _case.id,
        outcome: _outcome,
        reason: _reason,
        otherReason: _otherReasonController.text,
      );
      await AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up entry submit succeeded',
        context: {'caseId': _case.id, 'outcome': _outcome},
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      if (mounted) {
        setState(
          () => _error = 'Chưa lưu được lần chăm sóc. Vui lòng thử lại.',
        );
      }
      await AppLogger.instance.error(
        'SalesReportFollowUp',
        'Follow-up entry submit failed',
        error: error,
        stackTrace: stackTrace,
        context: {'caseId': _case.id, 'outcome': _outcome},
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _assign(String userId) async {
    setState(() => _saving = true);
    try {
      final updated = await widget.repository.assignFollowUpCase(
        _case.id,
        userId,
      );
      if (mounted) setState(() => _case = updated);
      await AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up customer reassigned',
        context: {'caseId': _case.id, 'assigneeUserId': userId},
      );
    } catch (error, stackTrace) {
      if (mounted) setState(() => _error = 'Chưa phân công được nhân viên.');
      await AppLogger.instance.error(
        'SalesReportFollowUp',
        'Follow-up customer reassign failed',
        error: error,
        stackTrace: stackTrace,
        context: {'caseId': _case.id, 'assigneeUserId': userId},
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reopen() async {
    setState(() => _saving = true);
    try {
      await widget.repository.reopenFollowUpCase(_case.id);
      await AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up customer reopened',
        context: {'caseId': _case.id},
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      if (mounted) setState(() => _error = 'Chưa mở lại được hồ sơ.');
      await AppLogger.instance.error(
        'SalesReportFollowUp',
        'Follow-up customer reopen failed',
        error: error,
        stackTrace: stackTrace,
        context: {'caseId': _case.id},
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AppDirtyFormGuard(
      source: 'SalesReportFollowUp',
      child: Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: size.width < 700 ? 8 : 24,
          vertical: size.height < 700 ? 8 : 24,
        ),
        child: SizedBox(
          width: 960,
          height: size.height * 0.9,
          child: Column(
            children: [
              _DialogHeader(
                item: _case,
                busy: _saving,
                onClose: () => Navigator.of(context).maybePop(),
                onAssign: _case.canReassign ? _assign : null,
                onContact: () => _contactCustomer(context, _case),
              ),
              const Divider(height: 1),
              if (_loading)
                const Expanded(
                  child: AppStatePanel.loading(
                    title: 'Đang tải lịch sử chăm sóc...',
                  ),
                )
              else if (_purchaseMode)
                Expanded(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: AppLinkButton(
                            onPressed: () => setState(() {
                              _purchaseMode = false;
                              _outcome = _outcomeNotPurchased;
                            }),
                            icon: PhosphorIconsRegular.arrowLeft,
                            label: 'Quay lại lịch sử chăm sóc',
                          ),
                        ),
                      ),
                      Expanded(
                        child: ChangeNotifierProvider(
                          create: (_) => SalesReportProvider(widget.repository),
                          child: SalesReportFormScreen.purchased(
                            entrySource: 'COMEBACK',
                            followUpCaseId: _case.id,
                            initialCustomerName: _case.customerName,
                            initialCustomerPhone: _case.customerPhone,
                            initialCustomerZaloContact:
                                _case.customerZaloContact,
                            closeOnSuccess: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_error != null) ...[
                        AppStatePanel.error(
                          title: 'Chưa thực hiện được',
                          message: _error,
                          actionLabel: _loading ? null : 'Tải lại lịch sử',
                          onAction: _loading
                              ? null
                              : () => unawaited(_loadDetail()),
                          compact: true,
                        ),
                        const SizedBox(height: 12),
                      ],
                      _FirstContactCard(item: _case),
                      const SizedBox(height: 12),
                      for (final entry in _case.entries) ...[
                        _HistoryCard(entry: entry),
                        const SizedBox(height: 10),
                      ],
                      if (_case.status == 'OPEN' && _case.canWrite)
                        _NewFollowUpCard(
                          sequenceNumber: _case.nextSequenceNumber,
                          outcome: _outcome,
                          reason: _reason,
                          otherReasonController: _otherReasonController,
                          saving: _saving,
                          onOutcomeChanged: (value) {
                            notifyAppFormChanged(context);
                            if (value == _outcomePurchased) {
                              setState(() {
                                _outcome = value;
                                _purchaseMode = true;
                              });
                            } else {
                              setState(() {
                                _outcome = value;
                                if (value != _outcomeNotPurchased) {
                                  _reason = null;
                                  _otherReasonController.clear();
                                }
                              });
                            }
                          },
                          onReasonChanged: (value) {
                            notifyAppFormChanged(context);
                            setState(() => _reason = value);
                          },
                          onSave: _save,
                        )
                      else if (_case.canReopen)
                        AppPrimaryButton(
                          onPressed: _saving ? null : _reopen,
                          icon: PhosphorIconsRegular.trayArrowUp,
                          label: 'Mở lại để tiếp tục chăm sóc',
                          isLoading: _saving,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  final SalesReportFollowUpCase item;
  final bool busy;
  final VoidCallback onClose;
  final ValueChanged<String>? onAssign;
  final VoidCallback onContact;

  const _DialogHeader({
    required this.item,
    required this.busy,
    required this.onClose,
    required this.onAssign,
    required this.onContact,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _careColor(
              context,
              item.careAgeDays,
            ).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            PhosphorIconsRegular.userFocus,
            color: _careColor(context, item.careAgeDays),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _text(item.customerName, 'Khách chưa cập nhật tên'),
                style: AppTextStyles.headingS,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Tooltip(
                message: 'Chạm để liên hệ',
                child: InkWell(
                  onTap: busy ? null : onContact,
                  child: Text(
                    '${item.contactSummary} • ${item.categoryNames.join(', ')}',
                    style: AppTextStyles.bodyS.copyWith(
                      color: AppColors.primaryOf(context),
                      decoration: TextDecoration.underline,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Liên hệ khách hàng',
          onPressed: busy ? null : onContact,
          icon: const Icon(PhosphorIconsRegular.phone),
        ),
        if (onAssign != null && item.assignmentCandidates.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: 'Phân công nhân viên',
            enabled: !busy,
            onSelected: onAssign,
            itemBuilder: (_) => [
              for (final assignee in item.assignmentCandidates)
                PopupMenuItem(
                  value: assignee.id,
                  child: Text(
                    assignee.personnelCode == null
                        ? assignee.name
                        : '${assignee.name} • ${assignee.personnelCode}',
                  ),
                ),
            ],
            icon: const Icon(PhosphorIconsRegular.identificationCard),
          ),
        IconButton(
          tooltip: 'Đóng',
          onPressed: busy ? null : onClose,
          icon: const Icon(PhosphorIconsRegular.x),
        ),
      ],
    ),
  );
}

class _FirstContactCard extends StatelessWidget {
  final SalesReportFollowUpCase item;

  const _FirstContactCard({required this.item});

  @override
  Widget build(BuildContext context) => AppSurfaceCard(
    backgroundColor: AppColors.warningOf(context).withValues(alpha: 0.10),
    borderColor: AppColors.warningOf(context).withValues(alpha: 0.28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tiếp xúc lần đầu', style: AppTextStyles.labelL),
        const SizedBox(height: 6),
        Text(
          '${_person(item.firstContactByName, item.firstContactByEmail)} • ${_date(item.firstContactAt)}',
        ),
        const SizedBox(height: 4),
        Text(
          'Lý do chưa mua: ${_text(item.firstReasonLabel, 'Chưa cập nhật')}${(item.firstOtherReason ?? '').trim().isEmpty ? '' : ' — ${item.firstOtherReason}'}',
        ),
        if ((item.assigneeName ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Đang phụ trách: ${item.assigneeName}'),
        ],
      ],
    ),
  );
}

class _HistoryCard extends StatelessWidget {
  final SalesReportFollowUpEntry entry;

  const _HistoryCard({required this.entry});

  @override
  Widget build(BuildContext context) => AppSurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lần chăm sóc ${entry.sequenceNumber} • ${entry.outcomeLabel}',
          style: AppTextStyles.labelL,
        ),
        const SizedBox(height: 5),
        Text(
          '${_person(entry.actorName, entry.actorEmail)} • ${_date(entry.contactedAt)}',
        ),
        if ((entry.reasonLabel ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Lý do: ${entry.reasonLabel}${(entry.otherReason ?? '').trim().isEmpty ? '' : ' — ${entry.otherReason}'}',
          ),
        ],
      ],
    ),
  );
}

class _NewFollowUpCard extends StatelessWidget {
  final int sequenceNumber;
  final String outcome;
  final String? reason;
  final TextEditingController otherReasonController;
  final bool saving;
  final ValueChanged<String> onOutcomeChanged;
  final ValueChanged<String?> onReasonChanged;
  final VoidCallback onSave;

  const _NewFollowUpCard({
    required this.sequenceNumber,
    required this.outcome,
    required this.reason,
    required this.otherReasonController,
    required this.saving,
    required this.onOutcomeChanged,
    required this.onReasonChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) => AppSurfaceCard(
    borderColor: AppColors.primaryOf(context).withValues(alpha: 0.32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Lần chăm sóc $sequenceNumber', style: AppTextStyles.headingS),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _OutcomeChip(
              value: _outcomePurchased,
              label: 'Mua hàng',
              icon: PhosphorIconsRegular.shoppingCart,
              selected: outcome == _outcomePurchased,
              onSelected: onOutcomeChanged,
            ),
            _OutcomeChip(
              value: _outcomeNotPurchased,
              label: 'Chưa mua',
              icon: PhosphorIconsRegular.clock,
              selected: outcome == _outcomeNotPurchased,
              onSelected: onOutcomeChanged,
            ),
            _OutcomeChip(
              value: _outcomePurchasedElsewhere,
              label: 'Đã mua nơi khác',
              icon: PhosphorIconsRegular.storefront,
              selected: outcome == _outcomePurchasedElsewhere,
              onSelected: onOutcomeChanged,
            ),
            _OutcomeChip(
              value: _outcomeNoLongerInterested,
              label: 'Hết nhu cầu',
              icon: PhosphorIconsRegular.prohibit,
              selected: outcome == _outcomeNoLongerInterested,
              onSelected: onOutcomeChanged,
            ),
          ],
        ),
        if (outcome == _outcomeNotPurchased) ...[
          const SizedBox(height: 14),
          AppCombobox<String>.single(
            label: 'Lý do chưa mua hàng',
            icon: PhosphorIconsRegular.question,
            value: reason,
            allowClear: false,
            enabled: !saving,
            options: [
              for (final entry in _reasonOptions.entries)
                AppComboboxOption(value: entry.key, label: entry.value),
            ],
            onChanged: onReasonChanged,
          ),
          if (reason == 'OTHER') ...[
            const SizedBox(height: 12),
            AppTextInput(
              controller: otherReasonController,
              label: 'Nhập lý do khác',
              icon: PhosphorIconsRegular.notePencil,
              maxLines: 3,
            ),
          ],
        ],
        const SizedBox(height: 16),
        AppPrimaryButton(
          onPressed: saving ? null : onSave,
          icon: PhosphorIconsRegular.floppyDisk,
          label: 'Lưu lần chăm sóc',
          isLoading: saving,
          loadingLabel: 'Đang lưu...',
        ),
      ],
    ),
  );
}

class _OutcomeChip extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final bool selected;
  final ValueChanged<String> onSelected;

  const _OutcomeChip({
    required this.value,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => ChoiceChip(
    selected: selected,
    avatar: Icon(icon, size: 18),
    label: Text(label),
    onSelected: (_) => onSelected(value),
  );
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: AppColors.neutral600Of(context)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodyS,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

Future<void> _contactCustomer(
  BuildContext context,
  SalesReportFollowUpCase item,
) async {
  final phone = item.customerPhone?.trim() ?? '';
  final zalo = item.customerZaloContact?.trim() ?? '';
  final channelLabels = item.contactChannelLabels;
  final mobile =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  try {
    if (mobile && phone.isNotEmpty) {
      await showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(PhosphorIconsRegular.phone),
                title: const Text('Gọi điện thoại'),
                subtitle: Text(phone),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await launchUrl(Uri(scheme: 'tel', path: phone));
                },
              ),
              if (item.hasPersonalZalo)
                ListTile(
                  leading: const Icon(PhosphorIconsRegular.chatCircle),
                  title: const Text('Mở Zalo cá nhân'),
                  subtitle: Text(phone),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final normalized = phone.replaceAll(RegExp(r'\D'), '');
                    await launchUrl(
                      Uri.parse('https://zalo.me/$normalized'),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                ),
              if (item.hasZaloOa)
                ListTile(
                  leading: const Icon(PhosphorIconsRegular.chatsCircle),
                  title: const Text('Khách có kênh Zalo OA'),
                  subtitle: const Text('Liên hệ qua Zalo OA của showroom'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    if (context.mounted) {
                      AppToast.show(
                        context,
                        const SnackBar(
                          content: Text(
                            'Vui lòng liên hệ khách qua Zalo OA của showroom.',
                          ),
                        ),
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      );
    } else if (phone.isNotEmpty || zalo.isNotEmpty) {
      final value = phone.isNotEmpty ? phone : zalo;
      await Clipboard.setData(ClipboardData(text: value));
      if (context.mounted) {
        AppToast.show(
          context,
          const SnackBar(content: Text('Đã sao chép thông tin liên hệ.')),
        );
      }
    } else if (channelLabels.isNotEmpty && context.mounted) {
      AppToast.show(
        context,
        SnackBar(
          content: Text(
            'Kênh liên hệ đã lưu: ${channelLabels.join(', ')}. Vui lòng liên hệ qua kênh tương ứng.',
          ),
        ),
      );
    } else if (context.mounted) {
      AppToast.show(
        context,
        const SnackBar(content: Text('Khách chưa có thông tin liên hệ.')),
      );
    }
    await AppLogger.instance.info(
      'SalesReportFollowUp',
      'Follow-up customer contact action succeeded',
      context: {
        'caseId': item.id,
        'mobile': mobile,
        'hasPhone': phone.isNotEmpty,
        'hasLegacyZaloContact': zalo.isNotEmpty,
        'contactChannelCount': item.customerContactChannels.length,
        'hasZaloPersonal': item.hasPersonalZalo,
        'hasZaloOa': item.hasZaloOa,
      },
    );
  } catch (error, stackTrace) {
    await AppLogger.instance.error(
      'SalesReportFollowUp',
      'Follow-up customer contact action failed',
      error: error,
      stackTrace: stackTrace,
      context: {'caseId': item.id, 'hasPhone': phone.isNotEmpty},
    );
    if (context.mounted) {
      AppToast.show(
        context,
        const SnackBar(
          content: Text('Chưa mở được kênh liên hệ. Vui lòng thử lại.'),
        ),
      );
    }
  }
}

Color _careColor(BuildContext context, int days) => switch (days) {
  <= 1 => AppColors.successOf(context),
  <= 3 => AppColors.warningOf(context),
  _ => AppColors.errorOf(context),
};

String _date(DateTime? value) => value == null
    ? 'Chưa cập nhật'
    : DateFormat('HH:mm dd/MM/yyyy').format(value.toLocal());

String _text(String? value, String fallback) =>
    (value ?? '').trim().isEmpty ? fallback : value!.trim();

String _person(String? name, String? email) =>
    _firstNonEmpty([name, email], fallback: 'Chưa cập nhật');

String _firstNonEmpty(
  List<String?> values, {
  String fallback = 'Chưa cập nhật',
}) {
  for (final value in values) {
    if ((value ?? '').trim().isNotEmpty) return value!.trim();
  }
  return fallback;
}
