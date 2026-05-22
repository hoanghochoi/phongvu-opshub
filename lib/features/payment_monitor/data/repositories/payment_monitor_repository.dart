import 'dart:convert';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/map_payment_transaction.dart';
import '../../domain/payment_notification.dart';

class StoredPaymentTransactionsPage {
  final List<MapPaymentTransaction> transactions;
  final int page;
  final int limit;
  final int total;

  const StoredPaymentTransactionsPage({
    required this.transactions,
    required this.page,
    required this.limit,
    required this.total,
  });
}

class PaymentMonitorRepository {
  final ApiClient _apiClient;

  PaymentMonitorRepository(this._apiClient);

  Future<StoredPaymentTransactionsPage> fetchStoredTransactions({
    String? storeId,
    String? date,
    int page = 0,
    int limit = 10,
  }) async {
    final response = await _apiClient.get(
      ApiConstants.adminMapVietinStoredTransactionsEndpoint,
      queryParameters: {
        if (storeId != null && storeId.trim().isNotEmpty)
          'storeId': storeId.trim().toUpperCase(),
        if (date != null && date.trim().isNotEmpty) 'date': date.trim(),
        'page': page.toString(),
        'limit': limit.toString(),
      },
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = data['list'] is List ? data['list'] as List : const [];
    final transactions = rows
        .whereType<Map>()
        .map(
          (row) => MapPaymentTransaction.fromJson(
            row.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((transaction) => transaction.isValidIncoming)
        .toList();
    return StoredPaymentTransactionsPage(
      transactions: transactions,
      page: int.tryParse(data['page']?.toString() ?? '') ?? page,
      limit: int.tryParse(data['limit']?.toString() ?? '') ?? limit,
      total:
          int.tryParse(data['total']?.toString() ?? '') ?? transactions.length,
    );
  }

  Future<List<int>> downloadNotificationAudio(String notificationId) {
    return _apiClient.getBytes(
      ApiConstants.paymentNotificationAudioEndpoint(notificationId),
    );
  }

  Future<List<PaymentNotification>> fetchReadyNotifications({
    required String clientId,
    String? storeId,
    DateTime? afterCreatedAt,
    int limit = 10,
  }) async {
    final response = await _apiClient.get(
      ApiConstants.paymentNotificationsReadyEndpoint,
      queryParameters: {
        'clientId': clientId,
        if (storeId != null && storeId.trim().isNotEmpty)
          'storeCode': storeId.trim().toUpperCase(),
        if (afterCreatedAt != null)
          'afterCreatedAt': afterCreatedAt.toUtc().toIso8601String(),
        'limit': limit.toString(),
      },
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = data['list'] is List ? data['list'] as List : const [];
    return rows
        .whereType<Map>()
        .map(
          (row) => PaymentNotification.fromJson(
            row.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((notification) => notification.isValid)
        .toList();
  }

  Future<void> acknowledgeNotification({
    required String notificationId,
    required String clientId,
    required String event,
    String? error,
  }) async {
    await _apiClient.post(
      ApiConstants.paymentNotificationAckEndpoint(notificationId),
      body: {
        'clientId': clientId,
        'event': event,
        if (error != null && error.trim().isNotEmpty) 'error': error.trim(),
      },
    );
  }
}
