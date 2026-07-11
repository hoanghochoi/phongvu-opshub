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
  final int averageOrderValue;
  final int completedRevenue;
  final int pendingRevenue;
  final int businessCustomerRevenue;
  final int personalCustomerRevenue;
  final int examScorePromotionCount;
  final int studentPromotionCount;
  final int installmentNeedCount;
  final int successfulInstallmentCount;
  final int extendedInsuranceQuantity;
  final int laptopQuantity;
  final int pcQuantity;
  final int assembledPcQuantity;
  final int appleQuantity;
  final int monitorQuantity;
  final int printerQuantity;
  final int accessoriesQuantity;
  final double coverageRate;
  final double conversionRate;
  final double consultedSolutionRate;
  final double experiencedRate;
  final double zaloRate;
  final double appDownloadRate;
  final bool salesAvailable;
  final bool financeAvailable;
  final int totalTransferredAmount;
  final int totalStatements;
  final int totalStatementsWithOrder;
  final int totalStatementsWithoutOrder;
  final double statementOrderRate;
  final HomeSalesProgress salesProgress;
  final HomeSalesProgress personalSalesProgress;
  final HomeSalesProgress scopeSalesProgress;
  final List<HomeSalesProgressAssignee> salesProgressAssignees;
  final String? selectedSalesProgressUserId;
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
    this.averageOrderValue = 0,
    this.completedRevenue = 0,
    this.pendingRevenue = 0,
    this.businessCustomerRevenue = 0,
    this.personalCustomerRevenue = 0,
    this.examScorePromotionCount = 0,
    this.studentPromotionCount = 0,
    this.installmentNeedCount = 0,
    this.successfulInstallmentCount = 0,
    this.extendedInsuranceQuantity = 0,
    this.laptopQuantity = 0,
    this.pcQuantity = 0,
    this.assembledPcQuantity = 0,
    this.appleQuantity = 0,
    this.monitorQuantity = 0,
    this.printerQuantity = 0,
    this.accessoriesQuantity = 0,
    required this.coverageRate,
    this.conversionRate = 0,
    this.consultedSolutionRate = 0,
    this.experiencedRate = 0,
    this.zaloRate = 0,
    this.appDownloadRate = 0,
    this.salesAvailable = true,
    this.financeAvailable = false,
    this.totalTransferredAmount = 0,
    this.totalStatements = 0,
    this.totalStatementsWithOrder = 0,
    this.totalStatementsWithoutOrder = 0,
    this.statementOrderRate = 0,
    this.salesProgress = const HomeSalesProgress.notApplicable(),
    HomeSalesProgress? personalSalesProgress,
    this.scopeSalesProgress = const HomeSalesProgress.notApplicable(),
    this.salesProgressAssignees = const [],
    this.selectedSalesProgressUserId,
    required this.refreshedAt,
    this.unavailableMessage,
  }) : startDate = startDate ?? date,
       endDate = endDate ?? date,
       personalSalesProgress = personalSalesProgress ?? salesProgress;

  factory HomeSummary.fromJson(Map<String, dynamic> json) {
    final date = _stringOf(json['date']);
    final personalSalesProgress = HomeSalesProgress.fromJson(
      json['personalSalesProgress'] ?? json['salesProgress'],
    );
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
      averageOrderValue: _intOf(json['averageOrderValue']),
      completedRevenue: _intOf(json['completedRevenue']),
      pendingRevenue: _intOf(json['pendingRevenue']),
      businessCustomerRevenue: _intOf(json['businessCustomerRevenue']),
      personalCustomerRevenue: _intOf(json['personalCustomerRevenue']),
      examScorePromotionCount: _intOf(json['examScorePromotionCount']),
      studentPromotionCount: _intOf(json['studentPromotionCount']),
      installmentNeedCount: _intOf(json['installmentNeedCount']),
      successfulInstallmentCount: _intOf(json['successfulInstallmentCount']),
      extendedInsuranceQuantity: _intOf(json['extendedInsuranceQuantity']),
      laptopQuantity: _intOf(json['laptopQuantity']),
      pcQuantity: _intOf(json['pcQuantity']),
      assembledPcQuantity: _intOf(json['assembledPcQuantity']),
      appleQuantity: _intOf(json['appleQuantity']),
      monitorQuantity: _intOf(json['monitorQuantity']),
      printerQuantity: _intOf(json['printerQuantity']),
      accessoriesQuantity: _intOf(json['accessoriesQuantity']),
      coverageRate: _coverageOf(json['coverageRate']),
      conversionRate: _coverageOf(json['conversionRate']),
      consultedSolutionRate: _coverageOf(json['consultedSolutionRate']),
      experiencedRate: _coverageOf(json['experiencedRate']),
      zaloRate: _coverageOf(json['zaloRate']),
      appDownloadRate: _coverageOf(json['appDownloadRate']),
      salesAvailable: json.containsKey('salesAvailable')
          ? json['salesAvailable'] == true
          : true,
      financeAvailable: json['financeAvailable'] == true,
      totalTransferredAmount: _intOf(json['totalTransferredAmount']),
      totalStatements: _intOf(json['totalStatements']),
      totalStatementsWithOrder: _intOf(json['totalStatementsWithOrder']),
      totalStatementsWithoutOrder: _intOf(json['totalStatementsWithoutOrder']),
      statementOrderRate: _coverageOf(json['statementOrderRate']),
      salesProgress: personalSalesProgress,
      personalSalesProgress: personalSalesProgress,
      scopeSalesProgress: HomeSalesProgress.fromJson(
        json['scopeSalesProgress'],
      ),
      salesProgressAssignees:
          (json['salesProgressAssignees'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(HomeSalesProgressAssignee.fromJson)
              .where((option) => option.userId.isNotEmpty)
              .toList(growable: false),
      selectedSalesProgressUserId: _nullableStringOf(
        json['selectedSalesProgressUserId'],
      ),
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
      averageOrderValue > 0 ||
      completedRevenue > 0 ||
      pendingRevenue > 0 ||
      businessCustomerRevenue > 0 ||
      personalCustomerRevenue > 0 ||
      examScorePromotionCount > 0 ||
      studentPromotionCount > 0 ||
      installmentNeedCount > 0 ||
      successfulInstallmentCount > 0 ||
      extendedInsuranceQuantity > 0 ||
      laptopQuantity > 0 ||
      pcQuantity > 0 ||
      assembledPcQuantity > 0 ||
      appleQuantity > 0 ||
      monitorQuantity > 0 ||
      printerQuantity > 0 ||
      accessoriesQuantity > 0 ||
      totalTransferredAmount > 0 ||
      totalStatements > 0 ||
      totalStatementsWithOrder > 0 ||
      totalStatementsWithoutOrder > 0 ||
      personalSalesProgress.isApplicable ||
      scopeSalesProgress.isApplicable;

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

class HomeSalesProgressAssignee {
  const HomeSalesProgressAssignee({
    required this.userId,
    required this.label,
    this.email,
    this.storeCodes = const [],
    this.isSelected = false,
    this.isCurrentUser = false,
  });

  final String userId;
  final String label;
  final String? email;
  final List<String> storeCodes;
  final bool isSelected;
  final bool isCurrentUser;

  factory HomeSalesProgressAssignee.fromJson(Map<String, dynamic> json) {
    return HomeSalesProgressAssignee(
      userId: HomeSummary._stringOf(json['userId']),
      label: HomeSummary._stringOf(json['label']),
      email: HomeSummary._nullableStringOf(json['email']),
      storeCodes: (json['storeCodes'] as List? ?? const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      isSelected: json['isSelected'] == true,
      isCurrentUser: json['isCurrentUser'] == true,
    );
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

class HomeSalesBehaviorDetails {
  const HomeSalesBehaviorDetails({
    required this.startDate,
    required this.endDate,
    required this.scope,
    required this.scopeLabel,
    required this.selectedSalesProgressUserId,
    required this.limit,
    required this.notPurchasedTotal,
    required this.unreportedTotal,
    required this.installmentNeedTotal,
    required this.notPurchasedReports,
    required this.unreportedOrders,
    required this.installmentNeedReports,
  });

  final String startDate;
  final String endDate;
  final String scope;
  final String scopeLabel;
  final String? selectedSalesProgressUserId;
  final int limit;
  final int notPurchasedTotal;
  final int unreportedTotal;
  final int installmentNeedTotal;
  final List<HomeNotPurchasedReportDetail> notPurchasedReports;
  final List<HomeUnreportedOrderDetail> unreportedOrders;
  final List<HomeInstallmentNeedDetail> installmentNeedReports;

  factory HomeSalesBehaviorDetails.fromJson(Map<String, dynamic> json) {
    return HomeSalesBehaviorDetails(
      startDate: HomeSummary._stringOf(json['startDate']),
      endDate: HomeSummary._stringOf(json['endDate']),
      scope: HomeSummary._stringOf(json['scope']),
      scopeLabel: HomeSummary._stringOf(json['scopeLabel']),
      selectedSalesProgressUserId: HomeSummary._nullableStringOf(
        json['selectedSalesProgressUserId'],
      ),
      limit: HomeSummary._intOf(json['limit']),
      notPurchasedTotal: HomeSummary._intOf(json['notPurchasedTotal']),
      unreportedTotal: HomeSummary._intOf(json['unreportedTotal']),
      installmentNeedTotal: HomeSummary._intOf(json['installmentNeedTotal']),
      notPurchasedReports: (json['notPurchasedReports'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(HomeNotPurchasedReportDetail.fromJson)
          .toList(growable: false),
      unreportedOrders: (json['unreportedOrders'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(HomeUnreportedOrderDetail.fromJson)
          .where((item) => item.orderCode.isNotEmpty)
          .toList(growable: false),
      installmentNeedReports:
          (json['installmentNeedReports'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(HomeInstallmentNeedDetail.fromJson)
              .toList(growable: false),
    );
  }
}

class HomeNotPurchasedReportDetail {
  const HomeNotPurchasedReportDetail({
    required this.id,
    required this.submittedAt,
    required this.storeCode,
    required this.salesName,
    required this.customerName,
    required this.customerTypeLabel,
    required this.categoryName,
    required this.notPurchasedReasonLabel,
  });

  final String id;
  final DateTime? submittedAt;
  final String? storeCode;
  final String? salesName;
  final String? customerName;
  final String? customerTypeLabel;
  final String? categoryName;
  final String? notPurchasedReasonLabel;

  factory HomeNotPurchasedReportDetail.fromJson(Map<String, dynamic> json) {
    return HomeNotPurchasedReportDetail(
      id: HomeSummary._stringOf(json['id']),
      submittedAt: HomeSummary._dateTimeOf(json['submittedAt']),
      storeCode: HomeSummary._nullableStringOf(json['storeCode']),
      salesName: HomeSummary._nullableStringOf(json['salesName']),
      customerName: HomeSummary._nullableStringOf(json['customerName']),
      customerTypeLabel: HomeSummary._nullableStringOf(
        json['customerTypeLabel'],
      ),
      categoryName: HomeSummary._nullableStringOf(json['categoryName']),
      notPurchasedReasonLabel: HomeSummary._nullableStringOf(
        json['notPurchasedReasonLabel'],
      ),
    );
  }
}

class HomeUnreportedOrderDetail {
  const HomeUnreportedOrderDetail({
    required this.orderCode,
    required this.soldAt,
    required this.storeCode,
    required this.salesName,
  });

  final String orderCode;
  final DateTime? soldAt;
  final String? storeCode;
  final String? salesName;

  factory HomeUnreportedOrderDetail.fromJson(Map<String, dynamic> json) {
    return HomeUnreportedOrderDetail(
      orderCode: HomeSummary._stringOf(json['orderCode']),
      soldAt: HomeSummary._dateTimeOf(json['soldAt']),
      storeCode: HomeSummary._nullableStringOf(json['storeCode']),
      salesName: HomeSummary._nullableStringOf(json['salesName']),
    );
  }
}

class HomeInstallmentNeedDetail {
  const HomeInstallmentNeedDetail({
    required this.id,
    required this.submittedAt,
    required this.storeCode,
    required this.salesName,
    required this.orderCode,
    required this.installmentPartnerLabels,
    required this.successful,
    required this.note,
  });

  final String id;
  final DateTime? submittedAt;
  final String? storeCode;
  final String? salesName;
  final String? orderCode;
  final List<String> installmentPartnerLabels;
  final bool successful;
  final String? note;

  factory HomeInstallmentNeedDetail.fromJson(Map<String, dynamic> json) {
    return HomeInstallmentNeedDetail(
      id: HomeSummary._stringOf(json['id']),
      submittedAt: HomeSummary._dateTimeOf(json['submittedAt']),
      storeCode: HomeSummary._nullableStringOf(json['storeCode']),
      salesName: HomeSummary._nullableStringOf(json['salesName']),
      orderCode: HomeSummary._nullableStringOf(json['orderCode']),
      installmentPartnerLabels:
          (json['installmentPartnerLabels'] as List? ?? const [])
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false),
      successful: json['successful'] == true || json['successful'] == 'true',
      note: HomeSummary._nullableStringOf(json['note']),
    );
  }
}
