import 'dart:convert';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/home_summary.dart';

class HomeSummaryRepository {
  final ApiClient _apiClient;

  HomeSummaryRepository(this._apiClient);

  Future<HomeSummary> fetchSummary({required String date}) async {
    final response = await _apiClient.get(
      ApiConstants.homeSummaryEndpoint,
      queryParameters: {'date': date},
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
