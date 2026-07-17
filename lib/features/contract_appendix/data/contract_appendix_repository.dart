import 'dart:convert';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../domain/contract_appendix.dart';

abstract interface class ContractAppendixDataSource {
  Future<ContractAppendixDocument> preview({
    required String orderCode,
    List<Map<String, dynamic>> overrides = const [],
  });

  Future<ContractAppendixDocument> save({
    required String orderCode,
    required String quoteVersion,
    required List<Map<String, dynamic>> overrides,
  });

  Future<ContractAppendixHistoryPage> list({
    required int page,
    required int limit,
    String? query,
  });

  Future<ContractAppendixDocument> detail(String id);
}

class ContractAppendixRepository implements ContractAppendixDataSource {
  final ApiClient _apiClient;

  ContractAppendixRepository(this._apiClient);

  @override
  Future<ContractAppendixDocument> preview({
    required String orderCode,
    List<Map<String, dynamic>> overrides = const [],
  }) async {
    final response = await _apiClient.post(
      ApiConstants.contractAppendicesPreviewEndpoint,
      body: {
        'orderCode': orderCode.trim(),
        if (overrides.isNotEmpty) 'overrides': overrides,
      },
    );
    return ContractAppendixDocument.fromJson(_decodeMap(response.body));
  }

  @override
  Future<ContractAppendixDocument> save({
    required String orderCode,
    required String quoteVersion,
    required List<Map<String, dynamic>> overrides,
  }) async {
    final response = await _apiClient.post(
      ApiConstants.contractAppendicesEndpoint,
      body: {
        'orderCode': orderCode.trim(),
        'quoteVersion': quoteVersion,
        if (overrides.isNotEmpty) 'overrides': overrides,
      },
    );
    return ContractAppendixDocument.fromJson(_decodeMap(response.body));
  }

  @override
  Future<ContractAppendixHistoryPage> list({
    required int page,
    required int limit,
    String? query,
  }) async {
    final normalizedQuery = query?.trim() ?? '';
    final response = await _apiClient.get(
      ApiConstants.contractAppendicesEndpoint,
      queryParameters: {
        'page': page.toString(),
        'limit': limit.toString(),
        if (normalizedQuery.isNotEmpty) 'query': normalizedQuery,
      },
    );
    return ContractAppendixHistoryPage.fromJson(_decodeMap(response.body));
  }

  @override
  Future<ContractAppendixDocument> detail(String id) async {
    final response = await _apiClient.get(
      ApiConstants.contractAppendixEndpoint(id),
    );
    return ContractAppendixDocument.fromJson(_decodeMap(response.body));
  }

  Map<String, dynamic> _decodeMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('Contract appendix response must be a map');
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
}
