import 'dart:convert';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../bank_statement/domain/bank_statement_transaction.dart';
import '../../domain/map_payment_transaction.dart';
import '../../domain/payment_delivery_metrics.dart';
import '../../domain/payment_notification.dart';

class StoredPaymentTransactionsPage {
  final List<MapPaymentTransaction> transactions;
  final int page;
  final int limit;
  final int? total;
  final bool canReviewOrderTransfers;

  const StoredPaymentTransactionsPage({
    required this.transactions,
    required this.page,
    required this.limit,
    required this.total,
    required this.canReviewOrderTransfers,
  });
}

class PaymentMonitorRepository {
  final ApiClient _apiClient;

  PaymentMonitorRepository(this._apiClient);

  Future<StoredPaymentTransactionsPage> fetchStoredTransactions({
    String? storeId,
    String? storeIds,
    bool allStores = false,
    String? date,
    String? startDate,
    String? endDate,
    int page = 0,
    int limit = 10,
    bool includeTotal = true,
    bool allowRateLimitCooldownBypass = false,
  }) async {
    final response = await _apiClient.get(
      ApiConstants.adminMapVietinStoredTransactionsEndpoint,
      allowRateLimitCooldownBypass: allowRateLimitCooldownBypass,
      queryParameters: {
        if (storeId != null && storeId.trim().isNotEmpty)
          'storeId': storeId.trim().toUpperCase(),
        if (storeIds != null && storeIds.trim().isNotEmpty)
          'storeIds': storeIds.trim().toUpperCase(),
        if (allStores) 'allStores': 'true',
        if (date != null && date.trim().isNotEmpty) 'date': date.trim(),
        if (startDate != null && startDate.trim().isNotEmpty)
          'startDate': startDate.trim(),
        if (endDate != null && endDate.trim().isNotEmpty)
          'endDate': endDate.trim(),
        'page': page.toString(),
        'limit': limit.toString(),
        if (!includeTotal) 'includeTotal': 'false',
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
      total: data.containsKey('total')
          ? int.tryParse(data['total']?.toString() ?? '') ?? transactions.length
          : null,
      canReviewOrderTransfers: data['canReviewOrderTransfers'] == true,
    );
  }

  Future<MapPaymentTransaction> updateOrders(
    String transactionId,
    List<String> orders, {
    String? transactionKey,
    bool allowRateLimitCooldownBypass = false,
  }) async {
    final cleanTransactionKey = transactionKey?.trim() ?? '';
    final response = await _apiClient.patch(
      ApiConstants.adminMapVietinStatementOrdersEndpoint(transactionId),
      allowRateLimitCooldownBypass: allowRateLimitCooldownBypass,
      body: {
        'orders': orders,
        if (cleanTransactionKey.isNotEmpty)
          'transactionKey': cleanTransactionKey,
      },
    );
    return MapPaymentTransaction.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> createOrderTransferRequest(
    String transactionId,
    List<String> orders, {
    String? transactionKey,
    bool allowRateLimitCooldownBypass = false,
  }) async {
    final cleanTransactionKey = transactionKey?.trim() ?? '';
    await _apiClient.post(
      ApiConstants.adminMapVietinStatementOrderTransferRequestsEndpoint(
        transactionId,
      ),
      allowRateLimitCooldownBypass: allowRateLimitCooldownBypass,
      body: {
        'orders': orders,
        if (cleanTransactionKey.isNotEmpty)
          'transactionKey': cleanTransactionKey,
      },
    );
  }

  Future<MapPaymentTransaction?> approveOrderTransferRequest(
    String requestId, {
    bool allowRateLimitCooldownBypass = false,
  }) {
    return _reviewOrderTransferRequest(
      ApiConstants.adminMapVietinStatementOrderTransferApproveEndpoint(
        requestId,
      ),
      allowRateLimitCooldownBypass: allowRateLimitCooldownBypass,
    );
  }

  Future<MapPaymentTransaction?> rejectOrderTransferRequest(
    String requestId, {
    String? note,
    bool allowRateLimitCooldownBypass = false,
  }) {
    return _reviewOrderTransferRequest(
      ApiConstants.adminMapVietinStatementOrderTransferRejectEndpoint(
        requestId,
      ),
      note: note,
      allowRateLimitCooldownBypass: allowRateLimitCooldownBypass,
    );
  }

  Future<MapPaymentTransaction?> _reviewOrderTransferRequest(
    String endpoint, {
    String? note,
    bool allowRateLimitCooldownBypass = false,
  }) async {
    final cleanNote = note?.trim() ?? '';
    final response = await _apiClient.post(
      endpoint,
      allowRateLimitCooldownBypass: allowRateLimitCooldownBypass,
      body: {if (cleanNote.isNotEmpty) 'note': cleanNote},
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final transaction = data['transaction'];
    if (transaction is! Map) return null;
    return MapPaymentTransaction.fromJson(
      transaction.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  Future<List<BankStatementOrderHistoryEntry>> fetchOrderHistory(
    String transactionId, {
    bool allowRateLimitCooldownBypass = false,
  }) async {
    final response = await _apiClient.get(
      ApiConstants.adminMapVietinStatementOrderHistoryEndpoint(transactionId),
      allowRateLimitCooldownBypass: allowRateLimitCooldownBypass,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = data['list'] is List ? data['list'] as List : const [];
    return rows
        .whereType<Map>()
        .map(
          (row) => BankStatementOrderHistoryEntry.fromJson(
            row.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();
  }

  Future<List<int>> downloadNotificationAudio(
    String notificationId, {
    bool includeCue = false,
    bool rawAmount = false,
  }) {
    return _apiClient.getBytes(
      ApiConstants.paymentNotificationAudioEndpoint(notificationId),
      queryParameters: {
        if (includeCue) 'includeCue': 'true',
        if (rawAmount) 'rawAmount': 'true',
      },
    );
  }

  Future<List<int>> downloadNotificationStreamAudio(
    String notificationId, {
    bool includeCue = false,
    bool rawAmount = false,
    String? clientId,
  }) {
    return _apiClient.getBytes(
      ApiConstants.paymentNotificationStreamEndpoint(notificationId),
      queryParameters: {
        if (includeCue) 'includeCue': 'true',
        if (rawAmount) 'rawAmount': 'true',
        if (clientId != null && clientId.trim().isNotEmpty)
          'clientId': clientId.trim(),
      },
    );
  }

  Future<void> claimNotificationForLocalPlayback(
    String notificationId, {
    required String clientId,
  }) async {
    await _apiClient.post(
      ApiConstants.paymentNotificationClaimEndpoint(notificationId),
      body: {'clientId': clientId},
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

  Future<PaymentDeliveryMetrics> fetchDeliveryMetrics({
    int windowHours = 24,
  }) async {
    final response = await _apiClient.get(
      ApiConstants.paymentNotificationDeliveryMetricsEndpoint,
      queryParameters: {'windowHours': windowHours.toString()},
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return PaymentDeliveryMetrics.fromJson(data);
  }

  Future<PaymentDeliveryHistory> fetchDeliveryHistory({int limit = 20}) async {
    final response = await _apiClient.get(
      ApiConstants.paymentNotificationDeliveryHistoryEndpoint,
      queryParameters: {'limit': limit.toString()},
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return PaymentDeliveryHistory.fromJson(data);
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
