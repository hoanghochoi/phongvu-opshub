class SalesReportCategoryGroup {
  final String id;
  final String catGroupName;
  final String catGroupNameVi;

  const SalesReportCategoryGroup({
    required this.id,
    required this.catGroupName,
    required this.catGroupNameVi,
  });

  factory SalesReportCategoryGroup.fromJson(Map<String, dynamic> json) {
    return SalesReportCategoryGroup(
      id: json['id']?.toString() ?? '',
      catGroupName: json['catGroupName']?.toString() ?? '',
      catGroupNameVi: json['catGroupNameVi']?.toString() ?? '',
    );
  }
}

class SalesReportOrderCheck {
  final String orderCode;
  final String? customerNeed;
  final SalesReportCategoryGroup? categoryGroup;
  final List<SalesReportCategoryGroup> categoryGroups;
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> payments;

  const SalesReportOrderCheck({
    required this.orderCode,
    required this.customerNeed,
    required this.categoryGroup,
    required this.categoryGroups,
    required this.order,
    required this.items,
    required this.payments,
  });

  factory SalesReportOrderCheck.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> cleanMap(Object? value) {
      if (value is Map) {
        return value.map((key, value) => MapEntry(key.toString(), value));
      }
      return {};
    }

    List<Map<String, dynamic>> cleanList(Object? value) {
      if (value is! List) return const [];
      return value
          .whereType<Map>()
          .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .toList();
    }

    final categoryJson = cleanMap(json['categoryGroup']);
    final categoryList = cleanList(json['categoryGroups'])
        .map(SalesReportCategoryGroup.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList();
    final legacyCategory = categoryJson.isEmpty
        ? null
        : SalesReportCategoryGroup.fromJson(categoryJson);
    return SalesReportOrderCheck(
      orderCode: json['orderCode']?.toString() ?? '',
      customerNeed: json['customerNeed']?.toString(),
      categoryGroup: legacyCategory,
      categoryGroups: categoryList.isNotEmpty
          ? categoryList
          : [if (legacyCategory != null) legacyCategory],
      order: cleanMap(json['order']),
      items: cleanList(json['items']),
      payments: cleanList(json['payments']),
    );
  }
}

class SalesReportInput {
  final String reportType;
  final String? orderCode;
  final String? customerPhone;
  final String categoryGroupId;
  final List<String> categoryGroupIds;
  final String? customerNeed;
  final String consultedSolutionAnswer;
  final String? consultedSolutionOtherReason;
  final String experiencedAnswer;
  final String? experiencedOtherReason;
  final String zaloAnswer;
  final String? zaloOtherReason;
  final String appDownloadAnswer;
  final String? appDownloadOtherReason;
  final String? notPurchasedReason;
  final String? notPurchasedOtherReason;
  final String? installmentStatus;
  final String? installmentFailureReason;
  final List<String> installmentPartnerCodes;

  const SalesReportInput({
    required this.reportType,
    required this.orderCode,
    required this.customerPhone,
    required this.categoryGroupId,
    required this.categoryGroupIds,
    required this.customerNeed,
    required this.consultedSolutionAnswer,
    required this.consultedSolutionOtherReason,
    required this.experiencedAnswer,
    required this.experiencedOtherReason,
    required this.zaloAnswer,
    required this.zaloOtherReason,
    required this.appDownloadAnswer,
    required this.appDownloadOtherReason,
    required this.notPurchasedReason,
    required this.notPurchasedOtherReason,
    required this.installmentStatus,
    required this.installmentFailureReason,
    required this.installmentPartnerCodes,
  });

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final text = value?.trim();
      return text == null || text.isEmpty ? null : text;
    }

    return {
      'reportType': reportType,
      if (clean(orderCode) != null) 'orderCode': clean(orderCode),
      if (clean(customerPhone) != null) 'customerPhone': clean(customerPhone),
      'categoryGroupId': categoryGroupId,
      'categoryGroupIds': categoryGroupIds
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      if (clean(customerNeed) != null) 'customerNeed': clean(customerNeed),
      'consultedSolutionAnswer': consultedSolutionAnswer,
      if (clean(consultedSolutionOtherReason) != null)
        'consultedSolutionOtherReason': clean(consultedSolutionOtherReason),
      'experiencedAnswer': experiencedAnswer,
      if (clean(experiencedOtherReason) != null)
        'experiencedOtherReason': clean(experiencedOtherReason),
      'zaloAnswer': zaloAnswer,
      if (clean(zaloOtherReason) != null)
        'zaloOtherReason': clean(zaloOtherReason),
      'appDownloadAnswer': appDownloadAnswer,
      if (clean(appDownloadOtherReason) != null)
        'appDownloadOtherReason': clean(appDownloadOtherReason),
      if (clean(notPurchasedReason) != null)
        'notPurchasedReason': clean(notPurchasedReason),
      if (clean(notPurchasedOtherReason) != null)
        'notPurchasedOtherReason': clean(notPurchasedOtherReason),
      if (clean(installmentStatus) != null)
        'installmentStatus': clean(installmentStatus),
      if (clean(installmentFailureReason) != null)
        'installmentFailureReason': clean(installmentFailureReason),
      if (installmentPartnerCodes.isNotEmpty)
        'installmentPartnerCodes': installmentPartnerCodes
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(),
    };
  }
}

class SalesReportQuery {
  final String reportType;
  final String? orderCode;
  final String? categoryGroupId;
  final DateTime? startDate;
  final DateTime? endDate;
  final int page;
  final int limit;

  const SalesReportQuery({
    this.reportType = 'ALL',
    this.orderCode,
    this.categoryGroupId,
    this.startDate,
    this.endDate,
    this.page = 0,
    this.limit = 20,
  });

  Map<String, String> toQueryParameters() {
    return {
      'reportType': reportType,
      if ((orderCode ?? '').trim().isNotEmpty) 'orderCode': orderCode!.trim(),
      if ((categoryGroupId ?? '').trim().isNotEmpty)
        'categoryGroupId': categoryGroupId!.trim(),
      if (startDate != null) 'startDate': _date(startDate!),
      if (endDate != null) 'endDate': _date(endDate!),
      'page': page.toString(),
      'limit': limit.toString(),
    };
  }

  static String _date(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }
}
