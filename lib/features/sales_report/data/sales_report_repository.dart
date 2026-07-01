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

  Future<SalesReportOrderCheck> checkOrder(String orderCode) async {
    final response = await _apiClient.post(
      ApiConstants.salesReportsCheckOrderEndpoint,
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

  Future<Map<String, dynamic>> create(SalesReportInput input) async {
    final response = await _apiClient.post(
      ApiConstants.salesReportsEndpoint,
      body: input.toJson(),
      timeout: const Duration(seconds: 60),
    );
    final data = jsonDecode(response.body);
    return data is Map<String, dynamic> ? data : {};
  }

  Future<Map<String, dynamic>> fetchList(SalesReportQuery query) async {
    final response = await _apiClient.get(
      ApiConstants.salesReportsEndpoint,
      queryParameters: query.toQueryParameters(),
    );
    final data = jsonDecode(response.body);
    return data is Map<String, dynamic> ? data : {};
  }

  Future<Uint8List> exportCsv(SalesReportQuery query) async {
    final bytes = await _apiClient.getBytes(
      ApiConstants.salesReportsExportEndpoint,
      queryParameters: query.toQueryParameters(),
      timeout: const Duration(seconds: 60),
    );
    return Uint8List.fromList(bytes);
  }
}
