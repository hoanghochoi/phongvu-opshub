import 'dart:math' as math;

class HomeSummary {
  final String date;
  final bool available;
  final String scope;
  final String scopeLabel;
  final String scopeDetail;
  final String coverageLabel;
  final int totalRevenue;
  final int totalOrders;
  final int totalReports;
  final int reportedOrders;
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
  final DateTime? refreshedAt;
  final String? unavailableMessage;

  const HomeSummary({
    required this.date,
    required this.available,
    required this.scope,
    required this.scopeLabel,
    required this.scopeDetail,
    required this.coverageLabel,
    required this.totalRevenue,
    required this.totalOrders,
    required this.totalReports,
    required this.reportedOrders,
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
    required this.refreshedAt,
    this.unavailableMessage,
  });

  factory HomeSummary.fromJson(Map<String, dynamic> json) {
    return HomeSummary(
      date: _stringOf(json['date']),
      available: json['available'] == true,
      scope: _stringOf(json['scope']),
      scopeLabel: _stringOf(json['scopeLabel']),
      scopeDetail: _stringOf(json['scopeDetail']),
      coverageLabel: _stringOf(json['coverageLabel']),
      totalRevenue: _intOf(json['totalRevenue']),
      totalOrders: _intOf(json['totalOrders']),
      totalReports: _intOf(json['totalReports']),
      reportedOrders: _intOf(json['reportedOrders']),
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
      unreportedOrders > 0 ||
      totalTransferredAmount > 0 ||
      totalStatements > 0 ||
      totalStatementsWithOrder > 0 ||
      totalStatementsWithoutOrder > 0;

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
