import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/constants/api_constants.dart';

class FifoLogItem {
  final String id;
  final String type;
  final String query;
  final String? result;
  final dynamic resultJson;
  final String createdAt;
  final String? userEmail;
  final String? userName;
  final String? storeId;
  final String? storeName;

  const FifoLogItem({
    required this.id,
    required this.type,
    required this.query,
    this.result,
    this.resultJson,
    required this.createdAt,
    this.userEmail,
    this.userName,
    this.storeId,
    this.storeName,
  });

  factory FifoLogItem.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    final store = user?['store'] as Map<String, dynamic>?;

    return FifoLogItem(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      query: json['query'] ?? '',
      result: json['result'],
      resultJson: json['resultJson'],
      createdAt: json['createdAt'] ?? '',
      userEmail: user?['email'],
      userName: user?['firstName'],
      storeId: store?['storeId'],
      storeName: store?['storeName'],
    );
  }
}

class FifoLogRepository {
  final ApiClient _apiClient;

  FifoLogRepository(this._apiClient);

  /// Get user's own FIFO check logs
  Future<List<FifoLogItem>> getMyLogs({
    String type = 'FIFO_CHECK',
    int limit = 10,
  }) async {
    try {
      final response = await _apiClient.get(
        '${ApiConstants.fifoLogMyEndpoint}?type=$type&limit=$limit',
      );

      if (kDebugMode) debugPrint('📥 [FifoLogRepo] My logs response: ${response.statusCode}');

      final List<dynamic> jsonList = jsonDecode(response.body);
      return jsonList.map((j) => FifoLogItem.fromJson(j as Map<String, dynamic>)).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [FifoLogRepo] Error loading my logs: $e');
      return [];
    }
  }

  /// Admin: Get all users' FIFO logs with pagination + search + filter
  Future<Map<String, dynamic>> getAdminLogs({
    String? type,
    int page = 1,
    int limit = 20,
    String? filterUserEmail,
    String? search,
  }) async {
    try {
      final params = <String>[];
      if (type != null) params.add('type=$type');
      params.add('page=$page');
      params.add('limit=$limit');
      if (filterUserEmail != null) params.add('user=$filterUserEmail');
      if (search != null && search.isNotEmpty) params.add('search=$search');

      final queryString = params.join('&');
      final response = await _apiClient.get(
        '${ApiConstants.fifoLogAdminEndpoint}?$queryString',
      );

      if (kDebugMode) debugPrint('📥 [FifoLogRepo] Admin logs response: ${response.statusCode}');

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = (json['data'] as List<dynamic>)
          .map((j) => FifoLogItem.fromJson(j as Map<String, dynamic>))
          .toList();

      return {
        'data': data,
        'total': json['total'] ?? 0,
        'page': json['page'] ?? 1,
        'limit': json['limit'] ?? 20,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [FifoLogRepo] Error loading admin logs: $e');
      return {'data': <FifoLogItem>[], 'total': 0, 'page': 1, 'limit': 20};
    }
  }
}
