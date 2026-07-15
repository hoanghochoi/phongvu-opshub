import 'dart:convert';

import '../constants/api_constants.dart';
import '../logging/app_logger.dart';
import 'api_client.dart';
import 'api_exception.dart';

class RealtimeTicketClient {
  RealtimeTicketClient({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  static final RealtimeTicketClient instance = RealtimeTicketClient();

  final ApiClient _apiClient;

  /// Issues a one-time ticket for the shared authenticated v2 gateway. The
  /// legacy `/ws` URI remains available only for the measured migration window.
  Future<Uri> issueV2ConnectionUri({String? storeCode}) async {
    final uri = await issueConnectionUri(storeCode: storeCode);
    return uri.replace(path: '/ws/v2');
  }

  Future<Uri> issueConnectionUri({String? storeCode}) async {
    final startedAt = DateTime.now();
    final normalizedStoreCode = storeCode?.trim().toUpperCase();
    await AppLogger.instance.info(
      'RealtimeAuth',
      'Realtime ticket request started',
      context: {'hasStoreScope': normalizedStoreCode?.isNotEmpty == true},
    );
    try {
      final response = await _apiClient.post(
        ApiConstants.realtimeTicketEndpoint,
        body: {
          if (normalizedStoreCode?.isNotEmpty == true)
            'storeCode': normalizedStoreCode,
        },
      );
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'Realtime ticket response is not an object',
        );
      }
      final ticket = decoded['ticket']?.toString().trim() ?? '';
      final audience = decoded['audience']?.toString().trim() ?? '';
      final expiresAt = DateTime.tryParse(
        decoded['expiresAt']?.toString() ?? '',
      );
      if (ticket.length < 40 ||
          audience != 'opshub-realtime' ||
          expiresAt == null ||
          !expiresAt.isAfter(DateTime.now().toUtc())) {
        throw const FormatException('Realtime ticket response is invalid');
      }
      await AppLogger.instance.info(
        'RealtimeAuth',
        'Realtime ticket request succeeded',
        context: {
          'hasStoreScope': normalizedStoreCode?.isNotEmpty == true,
          'expiresInSeconds': expiresAt
              .difference(DateTime.now().toUtc())
              .inSeconds,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return ApiConstants.realtimeWsUri(
        storeId: normalizedStoreCode,
        ticket: ticket,
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'RealtimeAuth',
        'Realtime ticket request failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'hasStoreScope': normalizedStoreCode?.isNotEmpty == true,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (error is ApiException) rethrow;
      throw ApiException(
        'Chưa kết nối được dữ liệu thời gian thực. Vui lòng thử lại.',
      );
    }
  }
}
