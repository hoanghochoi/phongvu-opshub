import 'dart:convert';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/home_summary.dart';

class HomeSummaryScopeOptionDto {
  const HomeSummaryScopeOptionDto({
    required this.value,
    required this.label,
    required this.scope,
    this.organizationNodeId,
    this.organizationNodeType,
    this.storeCount,
    this.isDefault = false,
  });

  final String value;
  final String label;
  final String scope;
  final String? organizationNodeId;
  final String? organizationNodeType;
  final int? storeCount;
  final bool isDefault;

  factory HomeSummaryScopeOptionDto.fromJson(Map<String, dynamic> json) {
    return HomeSummaryScopeOptionDto(
      value: json['value']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      scope: json['scope']?.toString() ?? '',
      organizationNodeId: json['organizationNodeId']?.toString(),
      organizationNodeType: json['organizationNodeType']?.toString(),
      storeCount: json['storeCount'] is num
          ? (json['storeCount'] as num).toInt()
          : int.tryParse(json['storeCount']?.toString() ?? ''),
      isDefault: json['isDefault'] == true || json['isDefault'] == 'true',
    );
  }
}

class HomeSummaryRepository {
  final ApiClient _apiClient;

  HomeSummaryRepository(this._apiClient);

  Future<HomeSummary> fetchSummary({
    String? date,
    String? startDate,
    String? endDate,
    String? scope,
    String? organizationNodeId,
    String? salesProgressUserId,
  }) async {
    final queryParameters = _buildSummaryQueryParameters(
      date: date,
      startDate: startDate,
      endDate: endDate,
      scope: scope,
      organizationNodeId: organizationNodeId,
      salesProgressUserId: salesProgressUserId,
    );
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

  Future<HomeSalesBehaviorDetails> fetchSalesBehaviorDetails({
    String? date,
    String? startDate,
    String? endDate,
    String? scope,
    String? organizationNodeId,
    String? salesProgressUserId,
    int? limit,
  }) async {
    final queryParameters = _buildSummaryQueryParameters(
      date: date,
      startDate: startDate,
      endDate: endDate,
      scope: scope,
      organizationNodeId: organizationNodeId,
      salesProgressUserId: salesProgressUserId,
    );
    if (limit != null && limit > 0) {
      queryParameters['limit'] = limit.toString();
    }
    final response = await _apiClient.get(
      ApiConstants.homeSummaryDetailsEndpoint,
      queryParameters: queryParameters,
    );
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw ParseException(
        'Dữ liệu chi tiết báo cáo chưa đúng định dạng. Vui lòng thử lại.',
      );
    }
    return HomeSalesBehaviorDetails.fromJson(data);
  }

  Future<List<HomeSummaryScopeOptionDto>> fetchScopeOptions() async {
    final response = await _apiClient.get(
      ApiConstants.homeSummaryScopeOptionsEndpoint,
    );
    final data = jsonDecode(response.body);
    if (data is! List) {
      throw ParseException(
        'Dữ liệu phạm vi dashboard chưa đúng định dạng. Vui lòng thử lại.',
      );
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(HomeSummaryScopeOptionDto.fromJson)
        .where((option) => option.value.isNotEmpty && option.label.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, String> _buildSummaryQueryParameters({
    String? date,
    String? startDate,
    String? endDate,
    String? scope,
    String? organizationNodeId,
    String? salesProgressUserId,
  }) {
    final queryParameters = <String, String>{};
    final normalizedDate = date?.trim();
    if (normalizedDate != null && normalizedDate.isNotEmpty) {
      queryParameters['date'] = normalizedDate;
    }
    final normalizedStartDate = startDate?.trim();
    if (normalizedStartDate != null && normalizedStartDate.isNotEmpty) {
      queryParameters['startDate'] = normalizedStartDate;
    }
    final normalizedEndDate = endDate?.trim();
    if (normalizedEndDate != null && normalizedEndDate.isNotEmpty) {
      queryParameters['endDate'] = normalizedEndDate;
    }
    final normalizedScope = scope?.trim().toUpperCase();
    if (normalizedScope != null &&
        normalizedScope.isNotEmpty &&
        normalizedScope != 'AUTO') {
      queryParameters['scope'] = normalizedScope;
    }
    final normalizedNodeId = organizationNodeId?.trim();
    if (normalizedNodeId != null && normalizedNodeId.isNotEmpty) {
      queryParameters['organizationNodeId'] = normalizedNodeId;
    }
    final normalizedSalesProgressUserId = salesProgressUserId?.trim();
    if (normalizedSalesProgressUserId != null &&
        normalizedSalesProgressUserId.isNotEmpty) {
      queryParameters['salesProgressUserId'] = normalizedSalesProgressUserId;
    }
    return queryParameters;
  }
}
