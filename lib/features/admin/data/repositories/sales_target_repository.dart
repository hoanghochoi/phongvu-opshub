import 'dart:convert';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';

class SalesTargetItem {
  const SalesTargetItem({
    required this.organizationNodeId,
    required this.storeCode,
    required this.storeName,
    required this.targetBeforeTax,
  });

  final String organizationNodeId;
  final String storeCode;
  final String storeName;
  final int? targetBeforeTax;

  factory SalesTargetItem.fromJson(Map<String, dynamic> json) {
    final rawTarget = json['targetBeforeTax'];
    return SalesTargetItem(
      organizationNodeId: json['organizationNodeId']?.toString() ?? '',
      storeCode: json['storeCode']?.toString() ?? '',
      storeName: json['storeName']?.toString() ?? '',
      targetBeforeTax: rawTarget == null
          ? null
          : rawTarget is num
          ? rawTarget.toInt()
          : int.tryParse(rawTarget.toString()),
    );
  }
}

class SalesTargetRepository {
  SalesTargetRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<SalesTargetItem>> fetchTargets(String month) async {
    final response = await _apiClient.get(
      ApiConstants.adminSalesTargetsEndpoint,
      queryParameters: {'month': month},
    );
    final body = jsonDecode(response.body);
    final items = body is Map<String, dynamic> ? body['items'] : null;
    if (items is! List) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(SalesTargetItem.fromJson)
        .where((item) => item.organizationNodeId.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<SalesTargetItem>> saveTargets(
    String month,
    Map<String, int?> targets,
  ) async {
    final response = await _apiClient.put(
      ApiConstants.adminSalesTargetsBatchEndpoint,
      body: {
        'month': month,
        'targets': [
          for (final entry in targets.entries)
            {'organizationNodeId': entry.key, 'targetBeforeTax': entry.value},
        ],
      },
    );
    final body = jsonDecode(response.body);
    final items = body is Map<String, dynamic> ? body['items'] : null;
    if (items is! List) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(SalesTargetItem.fromJson)
        .toList(growable: false);
  }
}
