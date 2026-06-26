import 'dart:convert';
import 'dart:typed_data';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../auth/domain/entities/store_branch.dart';
import '../domain/offset_adjustment.dart';

class OffsetAdjustmentPage {
  final List<OffsetAdjustment> items;
  final int page;
  final int limit;
  final int total;
  final bool canReview;

  const OffsetAdjustmentPage({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    required this.canReview,
  });
}

class OffsetAdjustmentQuery {
  final bool allStores;
  final List<String> storeIds;
  final String type;
  final String status;
  final String? order;
  final String? amount;
  final DateTime? startDate;
  final DateTime? endDate;
  final int page;
  final int limit;

  const OffsetAdjustmentQuery({
    required this.allStores,
    required this.storeIds,
    required this.type,
    required this.status,
    required this.order,
    required this.amount,
    required this.startDate,
    required this.endDate,
    required this.page,
    required this.limit,
  });

  Map<String, String> toQueryParameters() {
    return {
      if (allStores) 'allStores': 'true',
      if (storeIds.isNotEmpty) 'storeIds': storeIds.join(','),
      'type': type,
      'status': status,
      if ((order ?? '').trim().isNotEmpty) 'order': order!.trim(),
      if ((amount ?? '').trim().isNotEmpty)
        'amount': amount!.replaceAll(RegExp(r'[^0-9]'), ''),
      if (startDate != null) 'startDate': _formatDate(startDate!),
      if (endDate != null) 'endDate': _formatDate(endDate!),
      'page': page.toString(),
      'limit': limit.toString(),
    };
  }

  static String _formatDate(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }
}

class OffsetAdjustmentRepository {
  final ApiClient _apiClient;

  OffsetAdjustmentRepository(this._apiClient);

  Future<List<StoreBranch>> fetchStores() async {
    final response = await _apiClient.get(ApiConstants.storesEndpoint);
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .whereType<Map>()
        .map(
          (item) => StoreBranch.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();
  }

  Future<OffsetAdjustmentPage> fetchList(OffsetAdjustmentQuery query) async {
    final response = await _apiClient.get(
      ApiConstants.offsetAdjustmentsEndpoint,
      queryParameters: query.toQueryParameters(),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = data['list'] is List ? data['list'] as List : const [];
    final items = rows
        .whereType<Map>()
        .map(
          (row) => OffsetAdjustment.fromJson(
            row.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();
    return OffsetAdjustmentPage(
      items: items,
      page: int.tryParse(data['page']?.toString() ?? '') ?? query.page,
      limit: int.tryParse(data['limit']?.toString() ?? '') ?? query.limit,
      total: int.tryParse(data['total']?.toString() ?? '') ?? items.length,
      canReview: data['canReview'] == true,
    );
  }

  Future<Uint8List> exportCsv(OffsetAdjustmentQuery query) async {
    final bytes = await _apiClient.getBytes(
      ApiConstants.offsetAdjustmentsExportEndpoint,
      queryParameters: query.toQueryParameters(),
      timeout: const Duration(seconds: 60),
    );
    return Uint8List.fromList(bytes);
  }

  Future<OffsetAdjustment> create(OffsetAdjustmentInput input) async {
    final response = await _apiClient.post(
      ApiConstants.offsetAdjustmentsEndpoint,
      body: input.toJson(),
    );
    return OffsetAdjustment.fromJson(jsonDecode(response.body));
  }

  Future<OffsetAdjustment> detail(String id) async {
    final response = await _apiClient.get(
      ApiConstants.offsetAdjustmentEndpoint(id),
    );
    return OffsetAdjustment.fromJson(jsonDecode(response.body));
  }

  Future<OffsetAdjustment> resubmit(
    String id,
    OffsetAdjustmentInput input,
  ) async {
    final response = await _apiClient.patch(
      ApiConstants.offsetAdjustmentResubmitEndpoint(id),
      body: input.toJson(includeType: false),
    );
    return OffsetAdjustment.fromJson(jsonDecode(response.body));
  }

  Future<OffsetAdjustment> complete(String id, {String? ctCode}) async {
    final response = await _apiClient.post(
      ApiConstants.offsetAdjustmentCompleteEndpoint(id),
      body: {if ((ctCode ?? '').trim().isNotEmpty) 'ctCode': ctCode!.trim()},
    );
    return OffsetAdjustment.fromJson(jsonDecode(response.body));
  }

  Future<OffsetAdjustment> reject(String id, String reason) async {
    final response = await _apiClient.post(
      ApiConstants.offsetAdjustmentRejectEndpoint(id),
      body: {'reason': reason.trim()},
    );
    return OffsetAdjustment.fromJson(jsonDecode(response.body));
  }
}
