import 'dart:convert';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../bank_statement/data/bank_statement_repository.dart';
import '../../bank_statement/domain/bank_statement_transaction.dart';
import '../../offset_adjustment/data/offset_adjustment_repository.dart';
import '../../offset_adjustment/domain/offset_adjustment.dart';

class AppNotificationsFeed {
  final int schemaVersion;
  final DateTime generatedAt;
  final bool statementOrderTransfersEnabled;
  final bool offsetAdjustmentsEnabled;
  final BankStatementOrderTransferRequestPage statementOrderTransfers;
  final OffsetAdjustmentPage offsetAdjustments;
  final SupportChatNotificationSummary? supportChat;

  const AppNotificationsFeed({
    required this.schemaVersion,
    required this.generatedAt,
    required this.statementOrderTransfersEnabled,
    required this.offsetAdjustmentsEnabled,
    required this.statementOrderTransfers,
    required this.offsetAdjustments,
    this.supportChat,
  });

  factory AppNotificationsFeed.fromJson(Map<String, dynamic> json) {
    final schemaVersion = _requiredInt(json, 'schemaVersion');
    final generatedAt = DateTime.tryParse(
      json['generatedAt']?.toString() ?? '',
    );
    final statements = _requiredMap(json, 'statementOrderTransfers');
    final offsets = _requiredMap(json, 'offsetAdjustments');
    final supportChat = json['supportChat'] is Map
        ? SupportChatNotificationSummary.fromJson(
            Map<String, dynamic>.from(json['supportChat'] as Map),
          )
        : null;
    if (schemaVersion != 1 || generatedAt == null) {
      throw const FormatException('Unsupported notification feed schema');
    }

    final statementRows = _rowsOf(
      statements,
    ).map(BankStatementOrderTransferRequest.fromJson).toList(growable: false);
    final offsetRows = _rowsOf(
      offsets,
    ).map(OffsetAdjustment.fromJson).toList(growable: false);
    return AppNotificationsFeed(
      schemaVersion: schemaVersion,
      generatedAt: generatedAt,
      statementOrderTransfersEnabled: statements['enabled'] == true,
      offsetAdjustmentsEnabled: offsets['enabled'] == true,
      statementOrderTransfers: BankStatementOrderTransferRequestPage(
        requests: statementRows,
        page: _intOf(statements['page'], fallback: 0),
        limit: _intOf(statements['limit'], fallback: 20),
        total: _intOf(statements['total'], fallback: statementRows.length),
        canReview: statements['canReview'] == true,
      ),
      offsetAdjustments: OffsetAdjustmentPage(
        items: offsetRows,
        page: _intOf(offsets['page'], fallback: 0),
        limit: _intOf(offsets['limit'], fallback: 20),
        total: _intOf(offsets['total'], fallback: offsetRows.length),
        canReview: offsets['canReview'] == true,
      ),
      supportChat: supportChat,
    );
  }

  static Map<String, dynamic> _requiredMap(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value is! Map) throw FormatException('Missing notification feed $key');
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static int _requiredInt(Map<String, dynamic> json, String key) {
    final value = int.tryParse(json[key]?.toString() ?? '');
    if (value == null) throw FormatException('Missing notification feed $key');
    return value;
  }

  static int _intOf(Object? value, {required int fallback}) {
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static Iterable<Map<String, dynamic>> _rowsOf(Map<String, dynamic> section) {
    final rows = section['list'];
    if (rows is! List) {
      throw const FormatException('Notification feed list is invalid');
    }
    return rows.whereType<Map>().map(
      (row) => row.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
}

class SupportChatNotificationSummary {
  final bool enabled;
  final int unreadCount;
  final int unassignedCount;
  final String? conversationId;
  final String? status;

  const SupportChatNotificationSummary({
    required this.enabled,
    required this.unreadCount,
    required this.unassignedCount,
    required this.conversationId,
    required this.status,
  });

  factory SupportChatNotificationSummary.fromJson(Map<String, dynamic> json) {
    return SupportChatNotificationSummary(
      enabled: json['enabled'] == true,
      unreadCount: AppNotificationsFeed._intOf(
        json['unreadCount'],
        fallback: 0,
      ),
      unassignedCount: AppNotificationsFeed._intOf(
        json['unassignedCount'],
        fallback: 0,
      ),
      conversationId: json['conversationId']?.toString(),
      status: json['status']?.toString(),
    );
  }
}

class AppNotificationsFeedRepository {
  final ApiClient _apiClient;

  AppNotificationsFeedRepository(this._apiClient);

  Future<AppNotificationsFeed> fetchFeed() async {
    final response = await _apiClient.get(
      ApiConstants.notificationsFeedEndpoint,
    );
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Notification feed is not an object');
      }
      return AppNotificationsFeed.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } on FormatException {
      throw ParseException(
        'Chưa xử lý được dữ liệu thông báo. Vui lòng thử lại.',
      );
    }
  }
}
