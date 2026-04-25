import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/constants/api_constants.dart';
import '../models/sort_request.dart';

class SortRepository {
  final ApiClient _apiClient;

  SortRepository(this._apiClient);

  // New backend returns a list of inventory items directly
  // Each item has: sku, sku_name, serial_number, bin, zone, import_date, count, fifo
  Future<String> sendSortRequest(String text, String user) async {
    try {
      final request = SortRequest(text: text, user: user);

      final response = await _apiClient.post(
        ApiConstants.sortEndpoint,
        body: request.toJson(),
      );

      if (kDebugMode) {
        debugPrint('📥 [SortRepository] Response: ${response.statusCode}');
      }

      String responseText;
      try {
        final dynamic jsonResponse = jsonDecode(response.body);

        if (jsonResponse is List) {
          // New backend returns: [{sku, sku_name, serial_number, bin, zone, import_date, fifo}]
          // Normalize backend response into SKU rows for the UI.
          final textParts = <String>[];
          for (final item in jsonResponse) {
            if (item is Map<String, dynamic>) {
              final lines = [
                'SKU: ${item['sku'] ?? ''}',
                'Tên: ${item['sku_name'] ?? ''}',
                'Serial: ${item['serial_number'] ?? ''}',
                'Mã BIN: ${item['bin'] ?? ''}',
                'Zone: ${item['zone'] ?? ''}',
                'Ngày nhập: ${item['import_date'] ?? ''}',
              ];
              textParts.add(lines.join('\n'));
            }
          }
          responseText = textParts.join('\n\n');
        } else if (jsonResponse is Map<String, dynamic>) {
          final textParts = <String>[];
          for (var value in jsonResponse.values) {
            if (value is String) textParts.add(value);
          }
          responseText = textParts.join('\n\n');
        } else {
          responseText = jsonResponse.toString();
        }
      } catch (e) {
        responseText = response.body;
      }

      return responseText.trim();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Gửi yêu cầu sắp xếp thất bại: $e');
    }
  }

  Future<void> sendCompletionReport({
    required String user,
    required List<Map<String, dynamic>> sortedSKUs,
  }) async {
    try {
      await _apiClient.post(
        ApiConstants.sortCompletionReportEndpoint,
        body: {
          'user': user,
          'sortedSKUs': sortedSKUs,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Gửi báo cáo sắp xếp thất bại: $e');
    }
  }
}
