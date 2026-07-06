import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/date_range_defaults.dart';
import '../../../auth/domain/entities/user.dart';
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
  HomeSummaryProvider(this._repository, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _resetSelectedDateRangeToToday();
  }

  static final DateFormat _queryDateFormat = DateFormat('yyyy-MM-dd');

  final HomeSummaryRepository _repository;
  final DateTime Function() _now;

  User? _user;
  HomeSummary? _summary;
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  String _selectedScope = HomeSummaryScopeFilters.auto;
  List<HomeSummaryScopeOption> _scopeOptions = const [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _errorMessage;
  String? _syncedSessionKey;
  int _requestToken = 0;

  HomeSummary? get summary => _summary;
  DateTime get selectedDate => selectedEndDate ?? currentDate;
  DateTime? get selectedStartDate => _selectedStartDate;
  DateTime? get selectedEndDate => _selectedEndDate;
  String get selectedScope => _selectedScope;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  bool get isInitialLoading => _isLoading && _summary == null;
  bool get canRefresh => !_isLoading && !_isRefreshing && _user != null;
  String? get errorMessage => _errorMessage;
  List<HomeSummaryScopeOption> get scopeOptions {
    if (_scopeOptions.isNotEmpty) return _scopeOptions;
    return _fallbackScopeOptions(_user, _summary);
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
    } else if (user?.canUseFeature('ADMIN_SALES_REPORTS') == true) {
      options.add(
        const HomeSummaryScopeOption(
          value: HomeSummaryScopeFilters.managed,
          label: 'Showroom được gán',
          requestScope: HomeSummaryScopeFilters.managed,
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

  void syncAuth(User? user, {required bool isInitialized}) {
    _requestToken += 1;
    _user = user;
    final nextSessionKey = isInitialized && user != null
        ? _sessionKey(user)
        : null;
    final sessionChanged = _syncedSessionKey != nextSessionKey;
    _syncedSessionKey = nextSessionKey;

    if (!isInitialized || user == null) {
      if (_summary != null ||
          _scopeOptions.isNotEmpty ||
          _errorMessage != null ||
          _isLoading ||
          _isRefreshing) {
        _summary = null;
        _scopeOptions = const [];
        _errorMessage = null;
        _isLoading = false;
        _isRefreshing = false;
        notifyListeners();
      }
      return;
    }

    if (sessionChanged) {
      _resetSelectedDateRangeToToday();
      _scopeOptions = const [];
      _selectedScope = _defaultScopeFor(user, const []);
      _summary = null;
      _errorMessage = null;
      _isLoading = true;
      _isRefreshing = false;
      notifyListeners();
      unawaited(_bootstrapSessionSummary(user));
    }
  }

  Future<void> _bootstrapSessionSummary(User user) async {
    await _loadScopeOptions(user, reason: 'auth_sync');
    await loadSummary(reason: 'auth_sync');
  }

  Future<void> _loadScopeOptions(User user, {required String reason}) async {
    await AppLogger.instance.info(
      'HomeSummary',
      'Home summary scope options load started',
      context: {'userId': user.id, 'role': user.role, 'reason': reason},
    );
    try {
      final options = (await _repository.fetchScopeOptions())
          .map(HomeSummaryScopeOption.fromDto)
          .toList(growable: false);
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
    } on ApiException catch (error) {
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
    } catch (error, stackTrace) {
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
    }
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
    _selectedScope = nextScope;
    notifyListeners();
    final selectedOption = _scopeOptionFor(nextScope);

    await AppLogger.instance.info(
      'HomeSummary',
      'Home summary scope changed',
      context: {
        'userId': _user?.id,
        'previousScope': previousScope,
        'nextScope': _selectedScope,
        'requestScope': selectedOption?.requestScope,
        'organizationNodeId': selectedOption?.organizationNodeId,
        'startDate': formattedSelectedStartDate,
        'endDate': formattedSelectedEndDate,
        'hasExplicitDateRange': hasExplicitDateRange,
      },
    );
    await loadSummary(reason: 'scope_change');
  }

  Future<void> loadSummary({required String reason}) async {
    final user = _user;
    if (user == null) return;

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
      );
      if (requestToken != _requestToken) return;

      _summary = summary;
      _errorMessage = null;
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
        },
      );
    } on ApiException catch (error) {
      if (requestToken != _requestToken) return;
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
          'reason': reason,
          'message': error.message,
        },
      );
    } catch (error, stackTrace) {
      if (requestToken != _requestToken) return;
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

  static String _sessionKey(User user) =>
      '${user.id ?? user.email}|${user.role ?? ''}|${user.organizationNodeId ?? ''}|${user.organizationNodeIds.join(',')}';
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
