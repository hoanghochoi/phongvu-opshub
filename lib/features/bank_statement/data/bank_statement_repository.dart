import 'dart:convert';
import 'dart:typed_data';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../auth/domain/entities/store_branch.dart';
import '../domain/bank_statement_transaction.dart';

class BankStatementPage {
  final List<BankStatementTransaction> transactions;
  final int page;
  final int limit;
  final int total;

  const BankStatementPage({
    required this.transactions,
    required this.page,
    required this.limit,
    required this.total,
  });
}

class BankStatementQuery {
  final bool allStores;
  final List<String> storeIds;
  final String? order;
  final String? amount;
  final String? content;
  final String orderStatus;
  final DateTime? startDate;
  final DateTime? endDate;
  final int page;
  final int limit;

  const BankStatementQuery({
    required this.allStores,
    required this.storeIds,
    required this.order,
    required this.amount,
    required this.content,
    required this.orderStatus,
    required this.startDate,
    required this.endDate,
    required this.page,
    required this.limit,
  });

  Map<String, String> toQueryParameters() {
    return {
      if (allStores) 'allStores': 'true',
      if (storeIds.isNotEmpty) 'storeIds': storeIds.join(','),
      if ((order ?? '').trim().isNotEmpty) 'order': order!.trim(),
      if ((amount ?? '').trim().isNotEmpty) 'amount': amount!.trim(),
      if ((content ?? '').trim().isNotEmpty) 'content': content!.trim(),
      'orderStatus': orderStatus,
      if (startDate != null) 'startDate': _formatDate(startDate!),
      if (endDate != null) 'endDate': _formatDate(endDate!),
      'page': page.toString(),
      'limit': limit.toString(),
    };
  }

  Map<String, dynamic> toExportBody({List<String> transactionIds = const []}) {
    return {
      ...toQueryParameters(),
      if (transactionIds.isNotEmpty) 'transactionIds': transactionIds,
    };
  }

  static String _formatDate(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }
}

class BankStatementRepository {
  final ApiClient _apiClient;

  BankStatementRepository(this._apiClient);

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

  Future<BankStatementPage> fetchStatements(BankStatementQuery query) async {
    final response = await _apiClient.get(
      ApiConstants.adminMapVietinStatementsEndpoint,
      queryParameters: query.toQueryParameters(),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = data['list'] is List ? data['list'] as List : const [];
    final transactions = rows
        .whereType<Map>()
        .map(
          (row) => BankStatementTransaction.fromJson(
            row.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();
    return BankStatementPage(
      transactions: transactions,
      page: int.tryParse(data['page']?.toString() ?? '') ?? query.page,
      limit: int.tryParse(data['limit']?.toString() ?? '') ?? query.limit,
      total:
          int.tryParse(data['total']?.toString() ?? '') ?? transactions.length,
    );
  }

  Future<BankStatementTransaction> updateOrders(
    String transactionId,
    List<String> orders,
  ) async {
    final response = await _apiClient.patch(
      ApiConstants.adminMapVietinStatementOrdersEndpoint(transactionId),
      body: {'orders': orders},
    );
    return BankStatementTransaction.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<BankStatementOrderHistoryEntry>> fetchOrderHistory(
    String transactionId,
  ) async {
    final response = await _apiClient.get(
      ApiConstants.adminMapVietinStatementOrderHistoryEndpoint(transactionId),
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

  Future<Uint8List> exportCsv(
    BankStatementQuery query, {
    List<String> transactionIds = const [],
  }) async {
    final response = await _apiClient.post(
      ApiConstants.adminMapVietinStatementsExportEndpoint,
      body: query.toExportBody(transactionIds: transactionIds),
      timeout: const Duration(seconds: 60),
    );
    return Uint8List.fromList(response.bodyBytes);
  }
}
