import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/realtime_connection_manager.dart';
import '../../../../core/utils/date_range_defaults.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/domain/realtime_session_identity.dart';
import '../../data/repositories/home_summary_repository.dart';
import '../../domain/home_summary.dart';

class HomeSummaryScopeFilters {
  const HomeSummaryScopeFilters._();

  static const auto = 'AUTO';
  static const all = 'ALL';
  static const managed = 'MANAGED_SCOPE';
  static const own = 'OWN';
}

class HomeSummaryScopeOption {
  final String value;
  final String label;
  final String requestScope;
  final String? organizationNodeId;
  final String? organizationNodeType;
  final int? storeCount;
  final bool isDefault;

  const HomeSummaryScopeOption({
    required this.value,
    required this.label,
    this.requestScope = HomeSummaryScopeFilters.auto,
    this.organizationNodeId,
    this.organizationNodeType,
    this.storeCount,
    this.isDefault = false,
  });

  bool get isNodeScope => organizationNodeId?.trim().isNotEmpty == true;

  factory HomeSummaryScopeOption.fromDto(HomeSummaryScopeOptionDto dto) {
    return HomeSummaryScopeOption(
      value: dto.value,
      label: dto.label,
      requestScope: dto.scope,
      organizationNodeId: dto.organizationNodeId,
      organizationNodeType: dto.organizationNodeType,
      storeCount: dto.storeCount,
      isDefault: dto.isDefault,
    );
  }
}

class HomeSummaryProvider extends ChangeNotifier {
  HomeSummaryProvider(
    this._repository, {
    DateTime Function()? now,
    RealtimeClient? realtimeClient,
  }) : _now = now ?? DateTime.now {
    _resetSelectedDateRangeToToday();
    if (realtimeClient != null) {
      _realtimeEventSubscription = realtimeClient.events.listen(
        _handleRealtimeEnvelope,
      );
      _realtimeSyncSubscription = realtimeClient.syncRequests.listen(
        _handleRealtimeSyncRequest,
      );
    }
  }

  static final DateFormat _queryDateFormat = DateFormat('yyyy-MM-dd');
  static final DateFormat _updatedAtFormat = DateFormat('HH:mm dd/MM/yyyy');
  static const Duration _realtimeRefreshDebounce = Duration(milliseconds: 500);
  static const Duration _realtimeRefreshMaxWait = Duration(seconds: 2);

  final HomeSummaryRepository _repository;
  final DateTime Function() _now;

  StreamSubscription<RealtimeEnvelope>? _realtimeEventSubscription;
  StreamSubscription<RealtimeSyncReason>? _realtimeSyncSubscription;
  Timer? _realtimeRefreshTimer;
  Timer? _realtimeRefreshMaxTimer;
  final Set<String> _pendingAffectedDates = <String>{};
  final Map<String, int> _pendingProjectionVersionByDate = <String, int>{};
  final Map<String, int> _lastAppliedProjectionVersionByDate = <String, int>{};
  String? _pendingRealtimeReason;
  DateTime? _lastSuccessfulLoadAt;

  User? _user;
  HomeSummary? _summary;
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  String _selectedScope = HomeSummaryScopeFilters.auto;
  String? _selectedSalesProgressUserId;
  List<HomeSummaryScopeOption> _scopeOptions = const [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _isRouteActive = true;
  bool _isForeground = true;
  bool _sessionBootstrapPending = false;
  String? _errorMessage;
  String? _syncedSessionKey;
  int _requestToken = 0;

  HomeSummary? get summary => _summary;
  DateTime get selectedDate => selectedEndDate ?? currentDate;
  DateTime? get selectedStartDate => _selectedStartDate;
  DateTime? get selectedEndDate => _selectedEndDate;
  String get selectedScope => _selectedScope;
  String? get selectedSalesProgressUserId => _selectedSalesProgressUserId;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  bool get isInitialLoading => _isLoading && _summary == null;
  bool get canRefresh => !_isLoading && !_isRefreshing && _user != null;
  DateTime? get lastSuccessfulLoadAt => _lastSuccessfulLoadAt;
  bool get canOpenSalesReportAdmin =>
      _user?.canUseFeature('ADMIN_SALES_REPORTS') == true;
  bool get canOpenBankStatement => _user?.canUseBankStatements == true;
  String? get errorMessage => _errorMessage;
  List<HomeSalesProgressAssignee> get salesProgressAssignees =>
      _summary?.salesProgressAssignees ?? const [];
  List<HomeSummaryScopeOption> get scopeOptions {
    if (_scopeOptions.isNotEmpty) return _scopeOptions;
    return _fallbackScopeOptions(_user, _summary);
  }

  void syncRuntime({required bool isRouteActive, required bool isForeground}) {
    final wasEligible = _isRouteActive && _isForeground;
    _isRouteActive = isRouteActive;
    _isForeground = isForeground;
    final isEligible = isRouteActive && isForeground;
    if (!isEligible) {
      _cancelRealtimeRefreshTimers();
      return;
    }
    final becameActive = !wasEligible;
    if (!becameActive || _user == null) return;
    if (_sessionBootstrapPending || _summary == null) {
      _sessionBootstrapPending = false;
      unawaited(_bootstrapSessionSummary(_user!));
      return;
    }
    if (_hasPendingRealtimeRefresh) {
      _scheduleRealtimeRefresh(reason: 'route_activated', immediate: true);
      return;
    }
    final lastLoadedAt = _lastSuccessfulLoadAt;
    if (lastLoadedAt == null ||
        _now().difference(lastLoadedAt) >=
            HomeSummaryRepository.summaryFreshTtl) {
      unawaited(loadSummary(reason: 'route_revalidation'));
      return;
    }
    unawaited(
      AppLogger.instance.info(
        'HomeSummary',
        'Home summary route activation reused cached data',
        context: {
          'ageSeconds': _now().difference(lastLoadedAt).inSeconds,
          'ttlSeconds': HomeSummaryRepository.summaryFreshTtl.inSeconds,
        },
      ),
    );
  }

  static List<HomeSummaryScopeOption> _fallbackScopeOptions(
    User? user,
    HomeSummary? summary,
  ) {
    final options = <HomeSummaryScopeOption>[];

    if (user?.isSuperAdmin == true) {
      options.add(
        const HomeSummaryScopeOption(
          value: HomeSummaryScopeFilters.all,
          label: 'Toàn hệ thống',
          requestScope: HomeSummaryScopeFilters.all,
        ),
      );
    } else if (user?.canUseFeature('ADMIN_SALES_REPORTS') == true ||
        (user?.hasMultipleAssignedStores == true &&
            user?.canUseFeature('SALES_REPORT') == true)) {
      options.add(
        HomeSummaryScopeOption(
          value: HomeSummaryScopeFilters.managed,
          label: user?.hasMultipleAssignedStores == true
              ? 'Tất cả SR được gán'
              : 'Showroom được gán',
          requestScope: HomeSummaryScopeFilters.managed,
          storeCount: user?.assignedStores.length,
        ),
      );
    }

    if (user?.canUseFeature('SALES_REPORT') == true ||
        summary?.scope == HomeSummaryScopeFilters.own) {
      options.add(
        const HomeSummaryScopeOption(
          value: HomeSummaryScopeFilters.own,
          label: 'Phạm vi cá nhân',
          requestScope: HomeSummaryScopeFilters.own,
        ),
      );
    }

    if (options.isEmpty && summary != null) {
      options.add(
        HomeSummaryScopeOption(
          value: summary.scope,
          label: summary.resolvedScopeLabel,
          requestScope: summary.scope,
        ),
      );
    }

    final seen = <String>{};
    return [
      for (final option in options)
        if (seen.add(option.value)) option,
    ];
  }

  String get selectedScopeLabel {
    for (final option in scopeOptions) {
      if (option.value == _selectedScope) return option.label;
    }
    if (_selectedScope == HomeSummaryScopeFilters.auto) {
      return _summary?.resolvedScopeLabel ?? 'Toàn hệ thống';
    }
    return _summary?.resolvedScopeLabel ?? 'Theo quyền hiện tại';
  }

  void syncAuth(
    User? user, {
    required bool isInitialized,
    bool isAccessReady = true,
    String? accessIdentity,
  }) {
    final effectiveUser = isAccessReady ? user : null;
    _user = effectiveUser;
    final nextSessionKey = isInitialized && effectiveUser != null
        ? _sessionKey(effectiveUser, accessIdentity: accessIdentity)
        : null;
    final sessionChanged = _syncedSessionKey != nextSessionKey;
    _syncedSessionKey = nextSessionKey;
    if (sessionChanged) {
      _requestToken += 1;
      _cancelRealtimeRefreshTimers();
      _pendingAffectedDates.clear();
      _pendingProjectionVersionByDate.clear();
      _lastAppliedProjectionVersionByDate.clear();
      _pendingRealtimeReason = null;
      _lastSuccessfulLoadAt = null;
    }

    if (!isInitialized || effectiveUser == null) {
      if (_summary != null ||
          _scopeOptions.isNotEmpty ||
          _errorMessage != null ||
          _isLoading ||
          _isRefreshing) {
        _summary = null;
        _scopeOptions = const [];
        _selectedSalesProgressUserId = null;
        _errorMessage = null;
        _isLoading = false;
        _isRefreshing = false;
        _sessionBootstrapPending = false;
        notifyListeners();
      }
      return;
    }

    if (sessionChanged) {
      _resetSelectedDateRangeToToday();
      _scopeOptions = const [];
      _selectedScope = _defaultScopeFor(effectiveUser, const []);
      _selectedSalesProgressUserId = null;
      _summary = null;
      _errorMessage = null;
      _isLoading = true;
      _isRefreshing = false;
      _sessionBootstrapPending = !_isRouteActive || !_isForeground;
      if (_sessionBootstrapPending) _isLoading = false;
      notifyListeners();
      if (!_sessionBootstrapPending) {
        unawaited(_bootstrapSessionSummary(effectiveUser));
      }
    }
  }

  Future<void> _bootstrapSessionSummary(User user) async {
    final expectedSessionKey = _syncedSessionKey;
    if (expectedSessionKey == null) return;
    final scopeIsCurrent = await _loadScopeOptions(
      user,
      reason: 'auth_sync',
      expectedSessionKey: expectedSessionKey,
    );
    if (!scopeIsCurrent || _syncedSessionKey != expectedSessionKey) return;
    await loadSummary(reason: 'auth_sync');
  }

  Future<bool> _loadScopeOptions(
    User user, {
    required String reason,
    required String expectedSessionKey,
  }) async {
    await AppLogger.instance.info(
      'HomeSummary',
      'Home summary scope options load started',
      context: {'userId': user.id, 'role': user.role, 'reason': reason},
    );
    try {
      final options = (await _repository.fetchScopeOptions(
        cacheIdentity: _cacheIdentity(user),
      )).map(HomeSummaryScopeOption.fromDto).toList(growable: false);
      if (_syncedSessionKey != expectedSessionKey) {
        await _logDiscardedScopeOptions(user, reason);
        return false;
      }
      final fallbackOptions = _fallbackScopeOptions(user, _summary);
      _scopeOptions = options.isNotEmpty ? options : fallbackOptions;
      _selectedScope = _defaultScopeFor(user, _scopeOptions);
      notifyListeners();
      await AppLogger.instance.info(
        'HomeSummary',
        'Home summary scope options load succeeded',
        context: {
          'userId': user.id,
          'count': _scopeOptions.length,
          'nodeCount': _scopeOptions
              .where((option) => option.isNodeScope)
              .length,
          'selectedScope': _selectedScope,
        },
      );
      return true;
    } on ApiException catch (error) {
      if (_syncedSessionKey != expectedSessionKey) {
        await _logDiscardedScopeOptions(user, reason);
        return false;
      }
      _scopeOptions = _fallbackScopeOptions(user, _summary);
      _selectedScope = _defaultScopeFor(user, _scopeOptions);
      notifyListeners();
      await AppLogger.instance.warn(
        'HomeSummary',
        'Home summary scope options load failed',
        context: {
          'userId': user.id,
          'reason': reason,
          'message': error.message,
          'fallbackCount': _scopeOptions.length,
        },
      );
      return true;
    } catch (error, stackTrace) {
      if (_syncedSessionKey != expectedSessionKey) {
        await _logDiscardedScopeOptions(user, reason);
        return false;
      }
      _scopeOptions = _fallbackScopeOptions(user, _summary);
      _selectedScope = _defaultScopeFor(user, _scopeOptions);
      notifyListeners();
      await AppLogger.instance.error(
        'HomeSummary',
        'Home summary scope options load failed unexpectedly',
        error: error,
        stackTrace: stackTrace,
        context: {
          'userId': user.id,
          'reason': reason,
          'fallbackCount': _scopeOptions.length,
        },
        upload: true,
      );
      return true;
    }
  }

  Future<void> _logDiscardedScopeOptions(User user, String reason) {
    return AppLogger.instance.info(
      'HomeSummary',
      'Home summary scope options discarded for stale session',
      context: {'userId': user.id, 'reason': reason},
    );
  }

  Future<void> refreshNow() async {
    if (_user == null) return;
    await AppLogger.instance.info(
      'HomeSummary',
      'Home summary manual refresh requested',
      context: {
        'userId': _user?.id,
        'startDate': formattedSelectedStartDate,
        'endDate': formattedSelectedEndDate,
        'hasExplicitDateRange': hasExplicitDateRange,
        'hasCachedSummary': _summary != null,
      },
    );
    await loadSummary(reason: 'manual_refresh');
  }

  Future<HomeSummaryDetailsPage<HomeNotPurchasedReportDetail>>
  fetchNotPurchasedDetails({
    required String source,
    String? cursor,
    int limit = 50,
  }) => _fetchDetailsPage(
    source: source,
    kind: HomeSummaryDetailKind.notPurchased,
    cursor: cursor,
    limit: limit,
    loader: () => _repository.fetchNotPurchasedDetails(
      startDate: formattedSelectedStartDate,
      endDate: formattedSelectedEndDate,
      scope: _requestScopeForSelectedScope,
      organizationNodeId: _organizationNodeIdForSelectedScope,
      salesProgressUserId: _selectedSalesProgressUserId,
      cursor: cursor,
      limit: limit,
    ),
  );

  Future<HomeSummaryDetailsPage<HomeUnreportedOrderDetail>>
  fetchUnreportedOrderDetails({
    required String source,
    String? cursor,
    int limit = 50,
  }) => _fetchDetailsPage(
    source: source,
    kind: HomeSummaryDetailKind.unreportedOrder,
    cursor: cursor,
    limit: limit,
    loader: () => _repository.fetchUnreportedOrderDetails(
      startDate: formattedSelectedStartDate,
      endDate: formattedSelectedEndDate,
      scope: _requestScopeForSelectedScope,
      organizationNodeId: _organizationNodeIdForSelectedScope,
      salesProgressUserId: _selectedSalesProgressUserId,
      cursor: cursor,
      limit: limit,
    ),
  );

  Future<HomeSummaryDetailsPage<HomeInstallmentNeedDetail>>
  fetchInstallmentNeedDetails({
    required String source,
    String? cursor,
    int limit = 50,
  }) => _fetchDetailsPage(
    source: source,
    kind: HomeSummaryDetailKind.installmentNeed,
    cursor: cursor,
    limit: limit,
    loader: () => _repository.fetchInstallmentNeedDetails(
      startDate: formattedSelectedStartDate,
      endDate: formattedSelectedEndDate,
      scope: _requestScopeForSelectedScope,
      organizationNodeId: _organizationNodeIdForSelectedScope,
      salesProgressUserId: _selectedSalesProgressUserId,
      cursor: cursor,
      limit: limit,
    ),
  );

  Future<HomeSummaryDetailsPage<T>> _fetchDetailsPage<T>({
    required String source,
    required HomeSummaryDetailKind kind,
    required String? cursor,
    required int limit,
    required Future<HomeSummaryDetailsPage<T>> Function() loader,
  }) async {
    final user = _user;
    if (user == null) {
      throw ApiException('Vui lòng đăng nhập lại để xem chi tiết báo cáo.');
    }

    await AppLogger.instance.info(
      'HomeSummary',
      'Home summary details page load started',
      context: {
        'userId': user.id,
        'source': source,
        'kind': kind.apiValue,
        'startDate': formattedSelectedStartDate,
        'endDate': formattedSelectedEndDate,
        'scopeFilter': _selectedScope,
        'requestScope': _requestScopeForSelectedScope,
        'organizationNodeId': _organizationNodeIdForSelectedScope,
        'salesProgressUserId': _selectedSalesProgressUserId,
        'limit': limit.clamp(1, 100),
        'hasCursor': cursor?.trim().isNotEmpty == true,
      },
    );

    try {
      final page = await loader();
      await AppLogger.instance.info(
        'HomeSummary',
        'Home summary details page load succeeded',
        context: {
          'userId': user.id,
          'source': source,
          'kind': page.kind.apiValue,
          'scope': page.scope,
          'selectedSalesProgressUserId': page.selectedSalesProgressUserId,
          'rows': page.items.length,
          'total': page.total,
          'limit': page.limit,
          'hasNextPage': page.hasNextPage,
        },
      );
      return page;
    } on ApiException catch (error) {
      await AppLogger.instance.warn(
        'HomeSummary',
        'Home summary details page load failed',
        context: {
          'userId': user.id,
          'source': source,
          'kind': kind.apiValue,
          'hasCursor': cursor?.trim().isNotEmpty == true,
          'message': error.message,
        },
      );
      rethrow;
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'HomeSummary',
        'Home summary details page load failed unexpectedly',
        error: error,
        stackTrace: stackTrace,
        context: {
          'userId': user.id,
          'source': source,
          'kind': kind.apiValue,
          'hasCursor': cursor?.trim().isNotEmpty == true,
        },
        upload: true,
      );
      throw ApiException('Chưa tải được chi tiết báo cáo. Vui lòng thử lại.');
    }
  }

  Future<void> setSelectedDate(DateTime value) async {
    await setSelectedDateRange(value, value);
  }

  Future<void> setSelectedDateRange(DateTime? start, DateTime? end) async {
    final nextStart = start == null ? null : _normalizeDate(start);
    final nextEnd = end == null ? null : _normalizeDate(end);
    if (_selectedStartDate == nextStart && _selectedEndDate == nextEnd) return;
    final previousStartDate = formattedSelectedStartDate;
    final previousEndDate = formattedSelectedEndDate;
    final previousExplicit = hasExplicitDateRange;
    _selectedStartDate = nextStart;
    _selectedEndDate = nextEnd;
    notifyListeners();

    await AppLogger.instance.info(
      'HomeSummary',
      'Home summary date range changed',
      context: {
        'userId': _user?.id,
        'previousStartDate': previousStartDate,
        'previousEndDate': previousEndDate,
        'nextStartDate': formattedSelectedStartDate,
        'nextEndDate': formattedSelectedEndDate,
        'previousExplicitDateRange': previousExplicit,
        'nextExplicitDateRange': hasExplicitDateRange,
      },
    );
    await loadSummary(reason: 'date_range_change');
  }

  Future<void> setSelectedScope(String value) async {
    final nextScope = _normalizeScope(value);
    if (_selectedScope == nextScope) return;
    final previousScope = _selectedScope;
    final previousSalesProgressUserId = _selectedSalesProgressUserId;
    _selectedScope = nextScope;
    _selectedSalesProgressUserId = null;
    notifyListeners();
    final selectedOption = _scopeOptionFor(nextScope);

    await AppLogger.instance.info(
      'HomeSummary',
      'Home summary scope changed',
      context: {
        'userId': _user?.id,
        'previousScope': previousScope,
        'nextScope': _selectedScope,
        'previousSalesProgressUserId': previousSalesProgressUserId,
        'requestScope': selectedOption?.requestScope,
        'organizationNodeId': selectedOption?.organizationNodeId,
        'startDate': formattedSelectedStartDate,
        'endDate': formattedSelectedEndDate,
        'hasExplicitDateRange': hasExplicitDateRange,
      },
    );
    await loadSummary(reason: 'scope_change');
  }

  Future<void> setSelectedSalesProgressUser(String? userId) async {
    final nextUserId = _normalizeOptionalId(userId);
    if (_selectedSalesProgressUserId == nextUserId) return;
    final previousUserId = _selectedSalesProgressUserId;
    _selectedSalesProgressUserId = nextUserId;
    notifyListeners();

    await AppLogger.instance.info(
      'HomeSummary',
      'Home summary sales KPI assignee changed',
      context: {
        'userId': _user?.id,
        'previousSalesProgressUserId': previousUserId,
        'nextSalesProgressUserId': _selectedSalesProgressUserId,
        'scopeFilter': _selectedScope,
        'requestScope': _requestScopeForSelectedScope,
        'organizationNodeId': _organizationNodeIdForSelectedScope,
        'affectsSalesKpis': true,
        'financeKeepsScopeFilter': true,
      },
    );
    await loadSummary(reason: 'sales_progress_assignee_change');
  }

  Future<void> loadSummary({required String reason}) async {
    await _loadSummary(reason: reason);
  }

  Future<bool> _loadSummary({required String reason}) async {
    final user = _user;
    if (user == null) return false;

    final requestToken = ++_requestToken;
    final hadCachedSummary = _summary != null;
    _errorMessage = null;
    _isLoading = !hadCachedSummary;
    _isRefreshing = hadCachedSummary;
    notifyListeners();

    await AppLogger.instance.info(
      'HomeSummary',
      'Home summary load started',
      context: {
        'userId': user.id,
        'role': user.role,
        'scopeStoreCount': user.assignedStores.length,
        'startDate': formattedSelectedStartDate,
        'endDate': formattedSelectedEndDate,
        'hasExplicitDateRange': hasExplicitDateRange,
        'scopeFilter': _selectedScope,
        'requestScope': _requestScopeForSelectedScope,
        'organizationNodeId': _organizationNodeIdForSelectedScope,
        'salesProgressUserId': _selectedSalesProgressUserId,
        'reason': reason,
        'cached': hadCachedSummary,
      },
    );

    try {
      final summary = await _repository.fetchSummary(
        startDate: formattedSelectedStartDate,
        endDate: formattedSelectedEndDate,
        scope: _requestScopeForSelectedScope,
        organizationNodeId: _organizationNodeIdForSelectedScope,
        salesProgressUserId: _selectedSalesProgressUserId,
        cacheIdentity: _cacheIdentity(user),
        forceRefresh: _shouldForceNetworkForReason(reason),
      );
      if (requestToken != _requestToken) return false;

      _summary = summary;
      _lastSuccessfulLoadAt = _repository.lastSummaryFetchedAt ?? _now();
      _selectedSalesProgressUserId = summary.selectedSalesProgressUserId;
      _errorMessage = _repository.lastSummaryWasStale
          ? _staleCacheMessage(_lastSuccessfulLoadAt)
          : null;
      await AppLogger.instance.info(
        'HomeSummary',
        'Home summary load succeeded',
        context: {
          'userId': user.id,
          'date': summary.date,
          'startDate': summary.startDate,
          'endDate': summary.endDate,
          'hasExplicitDateRange': hasExplicitDateRange,
          'scopeFilter': _selectedScope,
          'requestScope': _requestScopeForSelectedScope,
          'organizationNodeId': _organizationNodeIdForSelectedScope,
          'selectedSalesProgressUserId': _selectedSalesProgressUserId,
          'salesProgressAssigneeCount': summary.salesProgressAssignees.length,
          'available': summary.available,
          'scope': summary.scope,
          'totalRevenue': summary.totalRevenue,
          'totalOrders': summary.totalOrders,
          'totalReports': summary.totalReports,
          'reportedOrders': summary.reportedOrders,
          'notPurchasedReports': summary.notPurchasedReports,
          'unreportedOrders': summary.unreportedOrders,
          'averageOrderValue': summary.averageOrderValue,
          'completedRevenue': summary.completedRevenue,
          'pendingRevenue': summary.pendingRevenue,
          'businessCustomerRevenue': summary.businessCustomerRevenue,
          'personalCustomerRevenue': summary.personalCustomerRevenue,
          'examScorePromotionCount': summary.examScorePromotionCount,
          'studentPromotionCount': summary.studentPromotionCount,
          'installmentNeedCount': summary.installmentNeedCount,
          'successfulInstallmentCount': summary.successfulInstallmentCount,
          'extendedInsuranceQuantity': summary.extendedInsuranceQuantity,
          'laptopQuantity': summary.laptopQuantity,
          'pcQuantity': summary.pcQuantity,
          'assembledPcQuantity': summary.assembledPcQuantity,
          'appleQuantity': summary.appleQuantity,
          'monitorQuantity': summary.monitorQuantity,
          'printerQuantity': summary.printerQuantity,
          'accessoriesQuantity': summary.accessoriesQuantity,
          'coverageRate': summary.coverageRate,
          'conversionRate': summary.conversionRate,
          'consultedSolutionRate': summary.consultedSolutionRate,
          'experiencedRate': summary.experiencedRate,
          'zaloRate': summary.zaloRate,
          'appDownloadRate': summary.appDownloadRate,
          'salesAvailable': summary.salesAvailable,
          'financeAvailable': summary.financeAvailable,
          'totalStatements': summary.totalStatements,
          'totalStatementsWithOrder': summary.totalStatementsWithOrder,
          'totalStatementsWithoutOrder': summary.totalStatementsWithoutOrder,
          'statementOrderRate': summary.statementOrderRate,
          'projectionGeneratedAt': summary.freshness?.projectionGeneratedAt
              ?.toIso8601String(),
          'projectionLagSeconds': summary.freshness?.projectionLagSeconds,
          'projectionVersion': summary.freshness?.projectionVersion,
          'isStale': summary.isStale,
        },
      );
      return true;
    } on ApiException catch (error) {
      if (requestToken != _requestToken) return false;
      _errorMessage = error.message;
      await AppLogger.instance.warn(
        'HomeSummary',
        'Home summary load failed',
        context: {
          'userId': user.id,
          'startDate': formattedSelectedStartDate,
          'endDate': formattedSelectedEndDate,
          'hasExplicitDateRange': hasExplicitDateRange,
          'scopeFilter': _selectedScope,
          'requestScope': _requestScopeForSelectedScope,
          'organizationNodeId': _organizationNodeIdForSelectedScope,
          'salesProgressUserId': _selectedSalesProgressUserId,
          'reason': reason,
          'message': error.message,
        },
      );
    } catch (error, stackTrace) {
      if (requestToken != _requestToken) return false;
      _errorMessage = 'Chưa tải được dashboard. Vui lòng thử lại.';
      await AppLogger.instance.error(
        'HomeSummary',
        'Home summary load failed unexpectedly',
        error: error,
        stackTrace: stackTrace,
        context: {
          'userId': user.id,
          'startDate': formattedSelectedStartDate,
          'endDate': formattedSelectedEndDate,
          'hasExplicitDateRange': hasExplicitDateRange,
          'scopeFilter': _selectedScope,
          'requestScope': _requestScopeForSelectedScope,
          'organizationNodeId': _organizationNodeIdForSelectedScope,
          'salesProgressUserId': _selectedSalesProgressUserId,
          'reason': reason,
        },
        upload: true,
      );
    } finally {
      if (requestToken == _requestToken) {
        _isLoading = false;
        _isRefreshing = false;
        notifyListeners();
      }
    }
    return false;
  }

  void _handleRealtimeEnvelope(RealtimeEnvelope envelope) {
    if (envelope.kind != 'HOME_SUMMARY_UPDATED' ||
        envelope.topic != 'home.summary' ||
        _user == null) {
      return;
    }
    final affectedDates = (envelope.data['affectedDates'] as List? ?? const [])
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final projectionVersion = _intOf(envelope.data['projectionVersion']);
    if (affectedDates.isEmpty || projectionVersion == null) {
      unawaited(
        AppLogger.instance.warn(
          'HomeSummaryRealtime',
          'Home realtime event ignored',
          context: {
            'eventId': envelope.id,
            'reason': 'invalid_home_payload',
            'affectedDateCount': affectedDates.length,
            'hasProjectionVersion': projectionVersion != null,
          },
        ),
      );
      return;
    }
    if (!_overlapsSelectedRange(affectedDates)) {
      unawaited(
        AppLogger.instance.info(
          'HomeSummaryRealtime',
          'Home realtime event ignored',
          context: {
            'eventId': envelope.id,
            'reason': 'date_range_not_affected',
            'affectedDateCount': affectedDates.length,
            'projectionVersion': projectionVersion,
          },
        ),
      );
      return;
    }
    final changedDates = affectedDates.where((date) {
      final appliedVersion = _lastAppliedProjectionVersionByDate[date] ?? -1;
      final pendingVersion = _pendingProjectionVersionByDate[date] ?? -1;
      return projectionVersion > appliedVersion &&
          projectionVersion > pendingVersion;
    }).toSet();
    if (changedDates.isEmpty) {
      unawaited(
        AppLogger.instance.info(
          'HomeSummaryRealtime',
          'Home realtime projection deduplicated',
          context: {
            'eventId': envelope.id,
            'projectionVersion': projectionVersion,
            'affectedDateCount': affectedDates.length,
          },
        ),
      );
      return;
    }
    for (final date in changedDates) {
      _pendingProjectionVersionByDate[date] = projectionVersion;
    }
    _pendingAffectedDates.addAll(changedDates);
    _scheduleRealtimeRefresh(reason: 'realtime_event');
  }

  void _handleRealtimeSyncRequest(RealtimeSyncReason reason) {
    if (_user == null) return;
    _scheduleRealtimeRefresh(
      reason: switch (reason) {
        RealtimeSyncReason.reconnected => 'realtime_reconnected',
        RealtimeSyncReason.appResumed => 'app_resumed',
      },
      force: true,
    );
  }

  void _scheduleRealtimeRefresh({
    required String reason,
    bool force = false,
    bool immediate = false,
  }) {
    _pendingRealtimeReason = force ? reason : _pendingRealtimeReason ?? reason;
    if (force) _pendingAffectedDates.clear();
    if (!_isRouteActive || !_isForeground) {
      _cancelRealtimeRefreshTimers();
      unawaited(
        AppLogger.instance.info(
          'HomeSummaryRealtime',
          'Home realtime refresh deferred',
          context: {
            'reason': reason,
            'routeActive': _isRouteActive,
            'foreground': _isForeground,
          },
        ),
      );
      return;
    }
    if (immediate) {
      _cancelRealtimeRefreshTimers();
      _realtimeRefreshTimer = Timer(Duration.zero, _refreshFromRealtime);
      return;
    }
    _realtimeRefreshTimer?.cancel();
    _realtimeRefreshTimer = Timer(
      _realtimeRefreshDebounce,
      _refreshFromRealtime,
    );
    _realtimeRefreshMaxTimer ??= Timer(
      _realtimeRefreshMaxWait,
      _refreshFromRealtime,
    );
  }

  Future<void> _refreshFromRealtime() async {
    _cancelRealtimeRefreshTimers();
    if (_user == null) return;
    if (!_isRouteActive || !_isForeground) return;
    final reason = _pendingRealtimeReason ?? 'realtime_sync';
    final pendingVersions = Map<String, int>.from(
      _pendingProjectionVersionByDate,
    );
    final projectionVersion = pendingVersions.values.fold<int?>(
      null,
      (highest, value) => highest == null || value > highest ? value : highest,
    );
    final affectedDates = Set<String>.from(_pendingAffectedDates);
    _pendingRealtimeReason = null;
    _pendingProjectionVersionByDate.clear();
    _pendingAffectedDates.clear();
    if (affectedDates.isNotEmpty && !_overlapsSelectedRange(affectedDates)) {
      await AppLogger.instance.info(
        'HomeSummaryRealtime',
        'Home realtime refresh skipped',
        context: {
          'reason': 'date_range_changed',
          'projectionVersion': projectionVersion,
        },
      );
      return;
    }

    await AppLogger.instance.info(
      'HomeSummaryRealtime',
      'Home realtime refresh started',
      context: {
        'reason': reason,
        'projectionVersion': projectionVersion,
        'startDate': formattedSelectedStartDate,
        'endDate': formattedSelectedEndDate,
      },
    );
    final succeeded = await _loadSummary(reason: reason);
    if (succeeded) {
      for (final entry in pendingVersions.entries) {
        final applied = _lastAppliedProjectionVersionByDate[entry.key] ?? -1;
        if (entry.value > applied) {
          _lastAppliedProjectionVersionByDate[entry.key] = entry.value;
        }
      }
    }
    if (succeeded) {
      await AppLogger.instance.info(
        'HomeSummaryRealtime',
        'Home realtime refresh succeeded',
        context: {'reason': reason, 'projectionVersion': projectionVersion},
      );
    } else {
      await AppLogger.instance.warn(
        'HomeSummaryRealtime',
        'Home realtime refresh failed',
        context: {'reason': reason, 'projectionVersion': projectionVersion},
      );
    }
  }

  bool _overlapsSelectedRange(Set<String> affectedDates) {
    final start = resolvedStartDate;
    final end = resolvedEndDate;
    for (final value in affectedDates) {
      final parsed = DateTime.tryParse(value);
      if (parsed == null) continue;
      final date = _normalizeDate(parsed);
      if (!date.isBefore(start) && !date.isAfter(end)) return true;
    }
    return false;
  }

  static int? _intOf(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  bool get hasExplicitDateRange =>
      _selectedStartDate != null || _selectedEndDate != null;

  DateTime get currentDate => _normalizeDate(_now());

  void _resetSelectedDateRangeToToday() {
    final today = currentDate;
    _selectedStartDate = today;
    _selectedEndDate = today;
  }

  DateTime get resolvedStartDate =>
      _selectedStartDate ??
      _selectedEndDate ??
      appImplicitDateRangeStart(currentDate);

  DateTime get resolvedEndDate =>
      _selectedEndDate ??
      _selectedStartDate ??
      appImplicitDateRangeEnd(currentDate);

  String get formattedSelectedDate => formattedSelectedEndDate;

  String get formattedSelectedStartDate =>
      _queryDateFormat.format(resolvedStartDate);

  String get formattedSelectedEndDate =>
      _queryDateFormat.format(resolvedEndDate);

  HomeSummaryScopeOption? _scopeOptionFor(String value) {
    final normalized = _normalizeScope(value);
    for (final option in scopeOptions) {
      if (_normalizeScope(option.value) == normalized) return option;
    }
    return null;
  }

  String? get _requestScopeForSelectedScope {
    final option = _scopeOptionFor(_selectedScope);
    final requestScope = option?.requestScope.trim().toUpperCase();
    if (requestScope != null && requestScope.isNotEmpty) return requestScope;
    final normalized = _normalizeScope(_selectedScope);
    if (normalized.startsWith('NODE:')) return HomeSummaryScopeFilters.managed;
    return normalized == HomeSummaryScopeFilters.auto ? null : normalized;
  }

  String? get _organizationNodeIdForSelectedScope {
    final option = _scopeOptionFor(_selectedScope);
    final optionNodeId = option?.organizationNodeId?.trim();
    if (optionNodeId != null && optionNodeId.isNotEmpty) return optionNodeId;
    final normalized = _normalizeScope(_selectedScope);
    if (!normalized.startsWith('NODE:')) return null;
    final nodeId = normalized.substring(5).trim();
    return nodeId.isEmpty ? null : nodeId;
  }

  static DateTime _normalizeDate(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _normalizeScope(String value) {
    final trimmed = value.trim();
    final upper = trimmed.toUpperCase();
    if (upper.startsWith('NODE:') && trimmed.length > 5) {
      return 'NODE:${trimmed.substring(trimmed.indexOf(':') + 1).trim()}';
    }
    final normalized = upper;
    if (normalized == HomeSummaryScopeFilters.all ||
        normalized == HomeSummaryScopeFilters.managed ||
        normalized == HomeSummaryScopeFilters.own) {
      return normalized;
    }
    return HomeSummaryScopeFilters.auto;
  }

  static String? _normalizeOptionalId(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String _defaultScopeFor(
    User user,
    List<HomeSummaryScopeOption> options,
  ) {
    if (options.isNotEmpty) {
      final defaultOption = options
          .where((option) => option.isDefault)
          .firstOrNull;
      if (defaultOption != null) return defaultOption.value;
      if (user.isSuperAdmin) {
        final allOption = options
            .where((option) => option.value == HomeSummaryScopeFilters.all)
            .firstOrNull;
        if (allOption != null) return allOption.value;
      }
      final nodeOption = options
          .where((option) => option.isNodeScope)
          .firstOrNull;
      if (nodeOption != null) return nodeOption.value;
      return options.first.value;
    }
    if (user.isSuperAdmin) return HomeSummaryScopeFilters.all;
    if (user.canUseFeature('ADMIN_SALES_REPORTS')) {
      return HomeSummaryScopeFilters.managed;
    }
    return HomeSummaryScopeFilters.own;
  }

  String _cacheIdentity(User user) => _syncedSessionKey ?? _sessionKey(user);

  static String _sessionKey(User user, {String? accessIdentity}) =>
      RealtimeSessionIdentity.forUser(user, accessIdentity: accessIdentity);

  static bool _shouldForceNetworkForReason(String reason) =>
      reason == 'manual_refresh' ||
      reason == 'app_resumed' ||
      reason.startsWith('realtime_');

  static String _staleCacheMessage(DateTime? updatedAt) {
    final timestamp = updatedAt == null
        ? ''
        : ' lúc ${_updatedAtFormat.format(updatedAt.toLocal())}';
    return 'Đang hiển thị dữ liệu đã lưu$timestamp vì chưa kết nối được hệ thống.';
  }

  @override
  void dispose() {
    _cancelRealtimeRefreshTimers();
    unawaited(_realtimeEventSubscription?.cancel());
    unawaited(_realtimeSyncSubscription?.cancel());
    _realtimeEventSubscription = null;
    _realtimeSyncSubscription = null;
    super.dispose();
  }

  bool get _hasPendingRealtimeRefresh =>
      _pendingRealtimeReason != null ||
      _pendingProjectionVersionByDate.isNotEmpty ||
      _pendingAffectedDates.isNotEmpty;

  void _cancelRealtimeRefreshTimers() {
    _realtimeRefreshTimer?.cancel();
    _realtimeRefreshMaxTimer?.cancel();
    _realtimeRefreshTimer = null;
    _realtimeRefreshMaxTimer = null;
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
