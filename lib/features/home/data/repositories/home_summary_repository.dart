import 'dart:convert';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/home_summary.dart';

class HomeSummaryRepository {
  final ApiClient _apiClient;

  HomeSummaryRepository(this._apiClient);

  Future<HomeSummary> fetchSummary({
    required String date,
    String? scope,
  }) async {
    final queryParameters = <String, String>{'date': date};
    final normalizedScope = scope?.trim().toUpperCase();
    if (normalizedScope != null &&
        normalizedScope.isNotEmpty &&
        normalizedScope != 'AUTO') {
      queryParameters['scope'] = normalizedScope;
    }
    final response = await _apiClient.get(
      ApiConstants.homeSummaryEndpoint,
      queryParameters: queryParameters,
    );
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw ParseException(
        'Dữ liệu dashboard chưa đúng định dạng. Vui lòng thử lại.',
      );
    }
    return HomeSummary.fromJson(data);
  }
}
