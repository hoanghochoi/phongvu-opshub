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
  final String? customerName;
  final String? customerNeed;
  final String? customerType;
  final String? customerTypeLabel;
  final SalesReportCategoryGroup? categoryGroup;
  final List<SalesReportCategoryGroup> categoryGroups;
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> payments;
  final List<String> paymentMethods;

  const SalesReportOrderCheck({
    required this.orderCode,
    required this.customerName,
    required this.customerNeed,
    required this.customerType,
    required this.customerTypeLabel,
    required this.categoryGroup,
    required this.categoryGroups,
    required this.order,
    required this.items,
    required this.payments,
    required this.paymentMethods,
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
      customerName: json['customerName']?.toString(),
      customerNeed: json['customerNeed']?.toString(),
      customerType: json['customerType']?.toString(),
      customerTypeLabel: json['customerTypeLabel']?.toString(),
      categoryGroup: legacyCategory,
      categoryGroups: categoryList.isNotEmpty
          ? categoryList
          : [if (legacyCategory != null) legacyCategory],
      order: cleanMap(json['order']),
      items: cleanList(json['items']),
      payments: cleanList(json['payments']),
      paymentMethods:
          (json['paymentMethods'] is List
                  ? json['paymentMethods'] as List
                  : const [])
              .map((value) => value.toString())
              .where((value) => value.trim().isNotEmpty)
              .toList(),
    );
  }
}

class SalesReportOrderCockpitItem {
  final String status;
  final String orderCode;
  final String? orderId;
  final DateTime? orderCreatedAt;
  final String? paymentStatus;
  final String? confirmationStatus;
  final String? fulfillmentStatus;
  final String? terminalName;
  final int? grandTotal;
  final String? customerName;
  final String? customerPhone;
  final String? customerType;
  final String? customerTypeLabel;
  final List<String> paymentMethods;
  final String? consultantCustomId;
  final String? consultantName;
  final String? sellerName;
  final String? storeCode;
  final String? storeName;
  final DateTime? fetchedAt;
  final DateTime? reportedAt;
  final Map<String, dynamic>? report;

  const SalesReportOrderCockpitItem({
    required this.status,
    required this.orderCode,
    required this.orderId,
    required this.orderCreatedAt,
    required this.paymentStatus,
    required this.confirmationStatus,
    required this.fulfillmentStatus,
    required this.terminalName,
    required this.grandTotal,
    required this.customerName,
    required this.customerPhone,
    required this.customerType,
    required this.customerTypeLabel,
    required this.paymentMethods,
    required this.consultantCustomId,
    required this.consultantName,
    required this.sellerName,
    required this.storeCode,
    required this.storeName,
    required this.fetchedAt,
    required this.reportedAt,
    required this.report,
  });

  bool get isReported => status == 'REPORTED';

  factory SalesReportOrderCockpitItem.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? value) {
      final text = value?.toString();
      if (text == null || text.isEmpty) return null;
      return DateTime.tryParse(text);
    }

    Map<String, dynamic>? cleanMap(Object? value) {
      if (value is! Map) return null;
      return value.map((key, value) => MapEntry(key.toString(), value));
    }

    int? parseInt(Object? value) {
      if (value == null || value == '') return null;
      return int.tryParse(value.toString().replaceAll(',', ''));
    }

    return SalesReportOrderCockpitItem(
      status: json['status']?.toString() ?? 'UNREPORTED',
      orderCode: json['orderCode']?.toString() ?? '',
      orderId: json['orderId']?.toString(),
      orderCreatedAt: parseDate(json['orderCreatedAt']),
      paymentStatus: json['paymentStatus']?.toString(),
      confirmationStatus: json['confirmationStatus']?.toString(),
      fulfillmentStatus: json['fulfillmentStatus']?.toString(),
      terminalName: json['terminalName']?.toString(),
      grandTotal: parseInt(json['grandTotal']),
      customerName: json['customerName']?.toString(),
      customerPhone: json['customerPhone']?.toString(),
      customerType: json['customerType']?.toString(),
      customerTypeLabel: json['customerTypeLabel']?.toString(),
      paymentMethods:
          (json['paymentMethods'] is List
                  ? json['paymentMethods'] as List
                  : const [])
              .map((value) => value.toString())
              .where((value) => value.trim().isNotEmpty)
              .toList(),
      consultantCustomId: json['consultantCustomId']?.toString(),
      consultantName: json['consultantName']?.toString(),
      sellerName: json['sellerName']?.toString(),
      storeCode: json['storeCode']?.toString(),
      storeName: json['storeName']?.toString(),
      fetchedAt: parseDate(json['fetchedAt']),
      reportedAt: parseDate(json['reportedAt']),
      report: cleanMap(json['report']),
    );
  }
}

class SalesReportOrderCockpit {
  /// Ngày cuối của khoảng lọc, giữ lại để tương thích response cũ.
  final String date;
  final String startDate;
  final String endDate;
  final DateTime? refreshedAt;
  final bool syncSucceeded;
  final String? syncError;
  final int syncCount;
  final String scope;
  final String? selectedStoreCode;
  final String? selectedUserEmail;
  final List<SalesReportFilterOption> storeOptions;
  final List<SalesReportFilterOption> userOptions;
  final int limit;
  final int reportedPage;
  final int reportedTotal;
  final int unreportedPage;
  final int unreportedTotal;
  final List<SalesReportOrderCockpitItem> reportedOrders;
  final List<SalesReportOrderCockpitItem> unreportedOrders;

  const SalesReportOrderCockpit({
    required this.date,
    required this.startDate,
    required this.endDate,
    required this.refreshedAt,
    required this.syncSucceeded,
    required this.syncError,
    required this.syncCount,
    required this.scope,
    required this.selectedStoreCode,
    required this.selectedUserEmail,
    required this.storeOptions,
    required this.userOptions,
    required this.limit,
    required this.reportedPage,
    required this.reportedTotal,
    required this.unreportedPage,
    required this.unreportedTotal,
    required this.reportedOrders,
    required this.unreportedOrders,
  });

  factory SalesReportOrderCockpit.fromJson(Map<String, dynamic> json) {
    List<SalesReportOrderCockpitItem> itemList(Object? value) {
      if (value is! List) return const [];
      return value
          .whereType<Map>()
          .map(
            (item) => SalesReportOrderCockpitItem.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .where((item) => item.orderCode.isNotEmpty)
          .toList();
    }

    int parseInt(Object? value, int fallback) {
      return int.tryParse(value?.toString() ?? '') ?? fallback;
    }

    final reportedOrders = itemList(json['reportedOrders']);
    final unreportedOrders = itemList(json['unreportedOrders']);
    final legacyDate = json['date']?.toString() ?? '';
    return SalesReportOrderCockpit(
      date: legacyDate,
      startDate: json['startDate']?.toString() ?? legacyDate,
      endDate: json['endDate']?.toString() ?? legacyDate,
      refreshedAt: DateTime.tryParse(json['refreshedAt']?.toString() ?? ''),
      syncSucceeded: json['syncSucceeded'] == true,
      syncError: json['syncError']?.toString(),
      syncCount: parseInt(json['syncCount'], 0),
      scope: json['scope']?.toString() ?? 'OWN',
      selectedStoreCode: json['selectedStoreCode']?.toString(),
      selectedUserEmail: json['selectedUserEmail']?.toString(),
      storeOptions: SalesReportFilterOption.listFromJson(json['storeOptions']),
      userOptions: SalesReportFilterOption.listFromJson(json['userOptions']),
      limit: parseInt(json['limit'], 20),
      reportedPage: parseInt(json['reportedPage'], 0),
      reportedTotal: parseInt(json['reportedTotal'], reportedOrders.length),
      unreportedPage: parseInt(json['unreportedPage'], 0),
      unreportedTotal: parseInt(
        json['unreportedTotal'],
        unreportedOrders.length,
      ),
      reportedOrders: reportedOrders,
      unreportedOrders: unreportedOrders,
    );
  }
}

class SalesReportFilterOption {
  final String value;
  final String label;

  const SalesReportFilterOption({required this.value, required this.label});

  static List<SalesReportFilterOption> listFromJson(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) {
          final value = item['value']?.toString().trim() ?? '';
          final label = item['label']?.toString().trim() ?? value;
          return SalesReportFilterOption(value: value, label: label);
        })
        .where((item) => item.value.isNotEmpty)
        .toList(growable: false);
  }
}

class SalesReportInput {
  final String reportType;
  final String? orderCode;
  final String? customerName;
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
  final String? customerType;
  final bool customerIsStudent;
  final List<String> promotionCodes;
  final bool installmentNeed;
  final bool? installmentApproved;
  final int? installmentLoanAmount;
  final String? installmentNoInstallmentReason;
  final String? installmentStatus;
  final String? installmentFailureReason;
  final List<String> installmentPartnerCodes;

  const SalesReportInput({
    required this.reportType,
    required this.orderCode,
    required this.customerName,
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
    required this.customerType,
    required this.customerIsStudent,
    required this.promotionCodes,
    required this.installmentNeed,
    required this.installmentApproved,
    required this.installmentLoanAmount,
    required this.installmentNoInstallmentReason,
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
      if (clean(customerName) != null) 'customerName': clean(customerName),
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
      if (clean(customerType) != null) 'customerType': clean(customerType),
      'customerIsStudent': customerIsStudent,
      if (promotionCodes.isNotEmpty)
        'promotionCodes': promotionCodes
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(),
      'installmentNeed': installmentNeed,
      if (installmentApproved != null)
        'installmentApproved': installmentApproved,
      if (installmentLoanAmount != null)
        'installmentLoanAmount': installmentLoanAmount,
      if (clean(installmentNoInstallmentReason) != null)
        'installmentNoInstallmentReason': clean(installmentNoInstallmentReason),
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
  final String? exportType;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? reporter;
  final List<String> storeIds;
  final int page;
  final int limit;

  const SalesReportQuery({
    this.reportType = 'ALL',
    this.orderCode,
    this.categoryGroupId,
    this.exportType,
    this.startDate,
    this.endDate,
    this.reporter,
    this.storeIds = const [],
    this.page = 0,
    this.limit = 20,
  });

  Map<String, String> toQueryParameters() {
    return {
      'reportType': reportType,
      if ((orderCode ?? '').trim().isNotEmpty) 'orderCode': orderCode!.trim(),
      if ((categoryGroupId ?? '').trim().isNotEmpty)
        'categoryGroupId': categoryGroupId!.trim(),
      if ((exportType ?? '').trim().isNotEmpty)
        'exportType': exportType!.trim(),
      if (startDate != null) 'startDate': _date(startDate!),
      if (endDate != null) 'endDate': _date(endDate!),
      if ((reporter ?? '').trim().isNotEmpty) 'reporter': reporter!.trim(),
      if (storeIds.isNotEmpty) 'storeIds': storeIds.join(','),
      'page': page.toString(),
      'limit': limit.toString(),
    };
  }

  static String _date(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }
}

class SalesReportOrdersQuery {
  final DateTime? startDate;
  final DateTime? endDate;
  final String? storeCode;
  final String? userEmail;
  final int reportedPage;
  final int unreportedPage;
  final int limit;

  const SalesReportOrdersQuery({
    this.startDate,
    this.endDate,
    this.storeCode,
    this.userEmail,
    this.reportedPage = 0,
    this.unreportedPage = 0,
    this.limit = 20,
  });

  Map<String, String> toQueryParameters() {
    return {
      if (startDate != null) 'startDate': SalesReportQuery._date(startDate!),
      if (endDate != null) 'endDate': SalesReportQuery._date(endDate!),
      if ((storeCode ?? '').trim().isNotEmpty) 'storeCode': storeCode!.trim(),
      if ((userEmail ?? '').trim().isNotEmpty) 'userEmail': userEmail!.trim(),
      'reportedPage': reportedPage.toString(),
      'unreportedPage': unreportedPage.toString(),
      'limit': limit.toString(),
    };
  }
}
