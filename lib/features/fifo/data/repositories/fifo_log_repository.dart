import 'dart:convert';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';

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

  Future<List<FifoLogItem>> getMyLogs({
    String type = 'FIFO_CHECK',
    int limit = 10,
  }) async {
    try {
      final response = await _apiClient.get(
        '${ApiConstants.fifoLogMyEndpoint}?type=$type&limit=$limit',
      );

      final List<dynamic> jsonList = jsonDecode(response.body);
      final logs = jsonList
          .map((j) => FifoLogItem.fromJson(j as Map<String, dynamic>))
          .toList();
      await AppLogger.instance.info(
        'FIFO',
        'My FIFO logs loaded',
        context: {'type': type, 'limit': limit, 'count': logs.length},
      );
      return logs;
    } catch (error) {
      await AppLogger.instance.error(
        'FIFO',
        'My FIFO logs load failed',
        error: error,
        context: {'type': type, 'limit': limit},
      );
      return [];
    }
  }

  Future<Map<String, dynamic>> getAdminLogs({
    String? type,
    int page = 1,
    int limit = 20,
    String? filterUserEmail,
    String? search,
  }) async {
    final startedAt = DateTime.now();
    await AppLogger.instance.info(
      'FIFO',
      'Admin FIFO logs load started',
      context: {
        'type': type,
        'page': page,
        'limit': limit,
        'hasUserFilter': filterUserEmail?.isNotEmpty == true,
        'hasSearch': search?.isNotEmpty == true,
      },
    );
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

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = (json['data'] as List<dynamic>)
          .map((j) => FifoLogItem.fromJson(j as Map<String, dynamic>))
          .toList();
      await AppLogger.instance.info(
        'FIFO',
        'Admin FIFO logs loaded',
        context: {
          'type': type,
          'page': page,
          'limit': limit,
          'count': data.length,
          'total': json['total'] ?? 0,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );

      return {
        'data': data,
        'total': json['total'] ?? 0,
        'page': json['page'] ?? 1,
        'limit': json['limit'] ?? 20,
      };
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'FIFO',
        'Admin FIFO logs load failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {
          'type': type,
          'page': page,
          'limit': limit,
          'hasUserFilter': filterUserEmail?.isNotEmpty == true,
          'hasSearch': search?.isNotEmpty == true,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      rethrow;
    }
  }
}
