import 'dart:convert';
import 'dart:typed_data';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../domain/sales_report.dart';

class SalesReportRepository {
  final ApiClient _apiClient;

  SalesReportRepository(this._apiClient);

  Future<List<SalesReportCategoryGroup>> fetchCategories({
    bool admin = false,
  }) async {
    final response = await _apiClient.get(
      admin
          ? ApiConstants.salesReportsAdminCategoriesEndpoint
          : ApiConstants.salesReportsCategoriesEndpoint,
    );
    final data = jsonDecode(response.body);
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map(
          (item) => SalesReportCategoryGroup.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  Future<SalesReportOrderCheck> checkOrder(
    String orderCode, {
    String? followUpCaseId,
  }) async {
    final response = await _apiClient.post(
      followUpCaseId == null
          ? ApiConstants.salesReportsCheckOrderEndpoint
          : ApiConstants.salesReportFollowUpCaseCheckOrderEndpoint(
              followUpCaseId,
            ),
      body: {'orderCode': orderCode.trim()},
      timeout: const Duration(seconds: 45),
    );
    return SalesReportOrderCheck.fromJson(jsonDecode(response.body));
  }

  Future<SalesReportOrderCockpit> fetchOrders(
    SalesReportOrdersQuery query,
  ) async {
    final response = await _apiClient.get(
      ApiConstants.salesReportsOrdersEndpoint,
      queryParameters: query.toQueryParameters(),
    );
    return SalesReportOrderCockpit.fromJson(jsonDecode(response.body));
  }

  Future<Map<String, dynamic>> create(
    SalesReportInput input, {
    String? followUpCaseId,
  }) async {
    final response = await _apiClient.post(
      followUpCaseId == null
          ? ApiConstants.salesReportsEndpoint
          : ApiConstants.salesReportFollowUpCaseEntriesEndpoint(followUpCaseId),
      body: followUpCaseId == null
          ? input.toJson()
          : {'outcome': 'PURCHASED', 'purchasedReport': input.toJson()},
      timeout: const Duration(seconds: 60),
    );
    final data = jsonDecode(response.body);
    return data is Map<String, dynamic> ? data : {};
  }

  Future<SalesReportFollowUpPage> fetchFollowUpCases({
    String status = 'OPEN',
    String? search,
    int page = 0,
    int limit = 20,
  }) async {
    final response = await _apiClient.get(
      ApiConstants.salesReportFollowUpCasesEndpoint,
      queryParameters: {
        'status': status,
        if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
        'page': '$page',
        'limit': '$limit',
      },
    );
    return SalesReportFollowUpPage.fromJson(jsonDecode(response.body));
  }

  Future<SalesReportFollowUpCase> fetchFollowUpCase(String id) async {
    final response = await _apiClient.get(
      ApiConstants.salesReportFollowUpCaseEndpoint(id),
    );
    return SalesReportFollowUpCase.fromJson(jsonDecode(response.body));
  }

  Future<SalesReportFollowUpCase> createFollowUpEntry(
    String id, {
    required String outcome,
    String? reason,
    String? otherReason,
  }) async {
    final response = await _apiClient.post(
      ApiConstants.salesReportFollowUpCaseEntriesEndpoint(id),
      body: {
        'outcome': outcome,
        if ((reason ?? '').trim().isNotEmpty)
          'notPurchasedReason': reason!.trim(),
        if ((otherReason ?? '').trim().isNotEmpty)
          'notPurchasedOtherReason': otherReason!.trim(),
      },
    );
    return SalesReportFollowUpCase.fromJson(jsonDecode(response.body));
  }

  Future<SalesReportFollowUpCase> assignFollowUpCase(
    String id,
    String userId,
  ) async {
    final response = await _apiClient.patch(
      ApiConstants.salesReportFollowUpCaseAssigneeEndpoint(id),
      body: {'userId': userId},
    );
    return SalesReportFollowUpCase.fromJson(jsonDecode(response.body));
  }

  Future<SalesReportFollowUpCase> reopenFollowUpCase(String id) async {
    final response = await _apiClient.post(
      ApiConstants.salesReportFollowUpCaseReopenEndpoint(id),
      body: const {},
    );
    return SalesReportFollowUpCase.fromJson(jsonDecode(response.body));
  }

  Future<Map<String, dynamic>> fetchList(SalesReportQuery query) async {
    final response = await _apiClient.get(
      ApiConstants.salesReportsEndpoint,
      queryParameters: query.toQueryParameters(),
    );
    final data = jsonDecode(response.body);
    return data is Map<String, dynamic> ? data : {};
  }

  Future<Uint8List> exportXlsx(SalesReportQuery query) async {
    final bytes = await _apiClient.getBytes(
      ApiConstants.salesReportsExportEndpoint,
      queryParameters: query.toQueryParameters(),
      timeout: const Duration(seconds: 60),
    );
    return Uint8List.fromList(bytes);
  }
}
