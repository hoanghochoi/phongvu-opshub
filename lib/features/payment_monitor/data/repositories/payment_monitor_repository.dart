import 'dart:convert';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/map_payment_transaction.dart';

class PaymentMonitorRepository {
  final ApiClient _apiClient;

  PaymentMonitorRepository(this._apiClient);

  Future<List<MapPaymentTransaction>> fetchStoredTransactions({
    String? storeId,
    int limit = 50,
  }) async {
    final response = await _apiClient.get(
      ApiConstants.adminMapVietinStoredTransactionsEndpoint,
      queryParameters: {
        if (storeId != null && storeId.trim().isNotEmpty)
          'storeId': storeId.trim().toUpperCase(),
        'limit': limit.toString(),
      },
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = data['list'] is List ? data['list'] as List : const [];
    return rows
        .whereType<Map>()
        .map(
          (row) => MapPaymentTransaction.fromJson(
            row.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((transaction) => transaction.isValidIncoming)
        .toList();
  }
}
