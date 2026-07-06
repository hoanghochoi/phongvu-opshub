import 'dart:math' as math;

class HomeSummary {
  final String date;
  final String startDate;
  final String endDate;
  final bool available;
  final String scope;
  final String scopeLabel;
  final String scopeDetail;
  final String coverageLabel;
  final int totalRevenue;
  final int totalOrders;
  final int totalReports;
  final int reportedOrders;
  final int notPurchasedReports;
  final int unreportedOrders;
  final double coverageRate;
  final double conversionRate;
  final bool salesAvailable;
  final bool financeAvailable;
  final int totalTransferredAmount;
  final int totalStatements;
  final int totalStatementsWithOrder;
  final int totalStatementsWithoutOrder;
  final double statementOrderRate;
  final HomeSalesProgress salesProgress;
  final DateTime? refreshedAt;
  final String? unavailableMessage;

  const HomeSummary({
    required this.date,
    String? startDate,
    String? endDate,
    required this.available,
    required this.scope,
    required this.scopeLabel,
    required this.scopeDetail,
    required this.coverageLabel,
    required this.totalRevenue,
    required this.totalOrders,
    required this.totalReports,
    required this.reportedOrders,
    this.notPurchasedReports = 0,
    required this.unreportedOrders,
    required this.coverageRate,
    this.conversionRate = 0,
    this.salesAvailable = true,
    this.financeAvailable = false,
    this.totalTransferredAmount = 0,
    this.totalStatements = 0,
    this.totalStatementsWithOrder = 0,
    this.totalStatementsWithoutOrder = 0,
    this.statementOrderRate = 0,
    this.salesProgress = const HomeSalesProgress.notApplicable(),
    required this.refreshedAt,
    this.unavailableMessage,
  }) : startDate = startDate ?? date,
       endDate = endDate ?? date;

  factory HomeSummary.fromJson(Map<String, dynamic> json) {
    final date = _stringOf(json['date']);
    return HomeSummary(
      date: date,
      startDate: _stringOf(json['startDate']).isEmpty
          ? date
          : _stringOf(json['startDate']),
      endDate: _stringOf(json['endDate']).isEmpty
          ? date
          : _stringOf(json['endDate']),
      available: json['available'] == true,
      scope: _stringOf(json['scope']),
      scopeLabel: _stringOf(json['scopeLabel']),
      scopeDetail: _stringOf(json['scopeDetail']),
      coverageLabel: _stringOf(json['coverageLabel']),
      totalRevenue: _intOf(json['totalRevenue']),
      totalOrders: _intOf(json['totalOrders']),
      totalReports: _intOf(json['totalReports']),
      reportedOrders: _intOf(json['reportedOrders']),
      notPurchasedReports: _intOf(json['notPurchasedReports']),
      unreportedOrders: _intOf(json['unreportedOrders']),
      coverageRate: _coverageOf(json['coverageRate']),
      conversionRate: _coverageOf(json['conversionRate']),
      salesAvailable: json.containsKey('salesAvailable')
          ? json['salesAvailable'] == true
          : true,
      financeAvailable: json['financeAvailable'] == true,
      totalTransferredAmount: _intOf(json['totalTransferredAmount']),
      totalStatements: _intOf(json['totalStatements']),
      totalStatementsWithOrder: _intOf(json['totalStatementsWithOrder']),
      totalStatementsWithoutOrder: _intOf(json['totalStatementsWithoutOrder']),
      statementOrderRate: _coverageOf(json['statementOrderRate']),
      salesProgress: HomeSalesProgress.fromJson(json['salesProgress']),
      refreshedAt: _dateTimeOf(json['refreshedAt']),
      unavailableMessage: _nullableStringOf(json['unavailableMessage']),
    );
  }

  bool get isUnavailable =>
      !available || scope.trim().toUpperCase() == 'UNAVAILABLE';

  bool get hasMetrics =>
      totalRevenue > 0 ||
      totalOrders > 0 ||
      totalReports > 0 ||
      reportedOrders > 0 ||
      notPurchasedReports > 0 ||
      unreportedOrders > 0 ||
      totalTransferredAmount > 0 ||
      totalStatements > 0 ||
      totalStatementsWithOrder > 0 ||
      totalStatementsWithoutOrder > 0 ||
      salesProgress.isApplicable;

  String get resolvedScopeLabel {
    final value = scopeLabel.trim();
    return value.isEmpty ? 'Theo quyền hiện tại' : value;
  }

  String get resolvedScopeDetail {
    final value = scopeDetail.trim();
    if (value.isNotEmpty) return value;
    return 'Số liệu đang được lọc theo phạm vi bạn được phân quyền.';
  }

  String get resolvedCoverageLabel {
    final value = coverageLabel.trim();
    return value.isEmpty ? 'Tỉ lệ báo cáo' : value;
  }

  String get resolvedUnavailableMessage {
    final value = unavailableMessage?.trim();
    if (value != null && value.isNotEmpty) return value;
    return 'Tài khoản hiện tại chưa có phạm vi dữ liệu để hiển thị dashboard.';
  }

  static double _coverageOf(Object? value) {
    if (value is num) {
      return value.toDouble().clamp(0, 100);
    }
    final parsed = double.tryParse(value?.toString() ?? '');
    return math.max(0, math.min(parsed ?? 0, 100));
  }

  static int _intOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _stringOf(Object? value) => value?.toString().trim() ?? '';

  static String? _nullableStringOf(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static DateTime? _dateTimeOf(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }
}

class HomeSalesProgress {
  const HomeSalesProgress({
    required this.status,
    required this.scope,
    required this.missingStoreCodes,
    required this.range,
    required this.day,
    required this.week,
    required this.month,
  });

  const HomeSalesProgress.notApplicable()
    : status = 'NOT_APPLICABLE',
      scope = null,
      missingStoreCodes = const [],
      range = const HomeSalesProgressPeriod.empty(),
      day = const HomeSalesProgressPeriod.empty(),
      week = const HomeSalesProgressPeriod.empty(),
      month = const HomeSalesProgressPeriod.empty();

  final String status;
  final String? scope;
  final List<String> missingStoreCodes;
  final HomeSalesProgressPeriod range;
  final HomeSalesProgressPeriod day;
  final HomeSalesProgressPeriod week;
  final HomeSalesProgressPeriod month;

  bool get isApplicable => status != 'NOT_APPLICABLE';
  bool get hasTarget => status == 'AVAILABLE';

  factory HomeSalesProgress.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return const HomeSalesProgress.notApplicable();
    }
    return HomeSalesProgress(
      status: value['status']?.toString() ?? 'NOT_APPLICABLE',
      scope: value['scope']?.toString(),
      missingStoreCodes: (value['missingStoreCodes'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      range: HomeSalesProgressPeriod.fromJson(value['range'] ?? value['day']),
      day: HomeSalesProgressPeriod.fromJson(value['day']),
      week: HomeSalesProgressPeriod.fromJson(value['week']),
      month: HomeSalesProgressPeriod.fromJson(value['month']),
    );
  }
}

class HomeSalesProgressPeriod {
  const HomeSalesProgressPeriod({
    required this.actual,
    required this.target,
    required this.percentage,
  });

  const HomeSalesProgressPeriod.empty()
    : actual = 0,
      target = null,
      percentage = null;

  final int actual;
  final int? target;
  final double? percentage;

  factory HomeSalesProgressPeriod.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return const HomeSalesProgressPeriod.empty();
    }
    final targetValue = value['target'];
    final percentageValue = value['percentage'];
    return HomeSalesProgressPeriod(
      actual: HomeSummary._intOf(value['actual']),
      target: targetValue == null ? null : HomeSummary._intOf(targetValue),
      percentage: percentageValue == null
          ? null
          : (percentageValue is num
                ? percentageValue.toDouble()
                : double.tryParse(percentageValue.toString())),
    );
  }
}
