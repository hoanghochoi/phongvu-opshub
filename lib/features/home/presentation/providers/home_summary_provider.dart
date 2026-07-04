import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_exception.dart';
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

  const HomeSummaryScopeOption({required this.value, required this.label});
}

class HomeSummaryProvider extends ChangeNotifier {
  HomeSummaryProvider(this._repository);

  static final DateFormat _queryDateFormat = DateFormat('yyyy-MM-dd');

  final HomeSummaryRepository _repository;

  User? _user;
  HomeSummary? _summary;
  DateTime _selectedDate = _normalizeDate(DateTime.now());
  String _selectedScope = HomeSummaryScopeFilters.auto;
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _errorMessage;
  String? _syncedSessionKey;
  int _requestToken = 0;

  HomeSummary? get summary => _summary;
  DateTime get selectedDate => _selectedDate;
  String get selectedScope => _selectedScope;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  bool get isInitialLoading => _isLoading && _summary == null;
  bool get canRefresh => !_isLoading && !_isRefreshing && _user != null;
  String? get errorMessage => _errorMessage;
  List<HomeSummaryScopeOption> get scopeOptions {
    final user = _user;
    final options = <HomeSummaryScopeOption>[];

    if (user?.isSuperAdmin == true) {
      options.add(
        const HomeSummaryScopeOption(
          value: HomeSummaryScopeFilters.all,
          label: 'Toàn hệ thống',
        ),
      );
    } else if (user?.canUseFeature('ADMIN_SALES_REPORTS') == true) {
      options.add(
        const HomeSummaryScopeOption(
          value: HomeSummaryScopeFilters.managed,
          label: 'Showroom được gán',
        ),
      );
    }

    if (user?.canUseFeature('SALES_REPORT') == true ||
        _summary?.scope == HomeSummaryScopeFilters.own) {
      options.add(
        const HomeSummaryScopeOption(
          value: HomeSummaryScopeFilters.own,
          label: 'Phạm vi cá nhân',
        ),
      );
    }

    if (options.isEmpty && _summary != null) {
      options.add(
        HomeSummaryScopeOption(
          value: _summary!.scope,
          label: _summary!.resolvedScopeLabel,
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
          _errorMessage != null ||
          _isLoading ||
          _isRefreshing) {
        _summary = null;
        _errorMessage = null;
        _isLoading = false;
        _isRefreshing = false;
        notifyListeners();
      }
      return;
    }

    if (sessionChanged) {
      _selectedDate = _normalizeDate(DateTime.now());
      _selectedScope = _defaultScopeFor(user);
      _summary = null;
      _errorMessage = null;
      _isLoading = true;
      _isRefreshing = false;
      notifyListeners();
      unawaited(loadSummary(reason: 'auth_sync'));
    }
  }

  Future<void> refreshNow() async {
    if (_user == null) return;
    await AppLogger.instance.info(
      'HomeSummary',
      'Home summary manual refresh requested',
      context: {
        'userId': _user?.id,
        'date': formattedSelectedDate,
        'hasCachedSummary': _summary != null,
      },
    );
    await loadSummary(reason: 'manual_refresh');
  }

  Future<void> setSelectedDate(DateTime value) async {
    final nextDate = _normalizeDate(value);
    if (_selectedDate == nextDate) return;
    final previousDate = formattedSelectedDate;
    _selectedDate = nextDate;
    notifyListeners();

    await AppLogger.instance.info(
      'HomeSummary',
      'Home summary date changed',
      context: {
        'userId': _user?.id,
        'previousDate': previousDate,
        'nextDate': formattedSelectedDate,
      },
    );
    await loadSummary(reason: 'date_change');
  }

  Future<void> setSelectedScope(String value) async {
    final nextScope = _normalizeScope(value);
    if (_selectedScope == nextScope) return;
    final previousScope = _selectedScope;
    _selectedScope = nextScope;
    notifyListeners();

    await AppLogger.instance.info(
      'HomeSummary',
      'Home summary scope changed',
      context: {
        'userId': _user?.id,
        'previousScope': previousScope,
        'nextScope': _selectedScope,
        'date': formattedSelectedDate,
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
        'date': formattedSelectedDate,
        'scopeFilter': _selectedScope,
        'reason': reason,
        'cached': hadCachedSummary,
      },
    );

    try {
      final summary = await _repository.fetchSummary(
        date: formattedSelectedDate,
        scope: _selectedScope,
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
          'scopeFilter': _selectedScope,
          'available': summary.available,
          'scope': summary.scope,
          'totalRevenue': summary.totalRevenue,
          'totalOrders': summary.totalOrders,
          'totalReports': summary.totalReports,
          'reportedOrders': summary.reportedOrders,
          'unreportedOrders': summary.unreportedOrders,
          'coverageRate': summary.coverageRate,
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
          'date': formattedSelectedDate,
          'scopeFilter': _selectedScope,
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
          'date': formattedSelectedDate,
          'scopeFilter': _selectedScope,
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

  String get formattedSelectedDate => _queryDateFormat.format(_selectedDate);

  static DateTime _normalizeDate(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _normalizeScope(String value) {
    final normalized = value.trim().toUpperCase();
    if (normalized == HomeSummaryScopeFilters.all ||
        normalized == HomeSummaryScopeFilters.managed ||
        normalized == HomeSummaryScopeFilters.own) {
      return normalized;
    }
    return HomeSummaryScopeFilters.auto;
  }

  static String _defaultScopeFor(User user) {
    if (user.isSuperAdmin) return HomeSummaryScopeFilters.all;
    if (user.canUseFeature('ADMIN_SALES_REPORTS')) {
      return HomeSummaryScopeFilters.managed;
    }
    return HomeSummaryScopeFilters.own;
  }

  static String _sessionKey(User user) =>
      '${user.id ?? user.email}|${user.role ?? ''}|${user.organizationNodeId ?? ''}';
}
