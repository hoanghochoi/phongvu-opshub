import 'dart:convert';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/constants/api_constants.dart';
import '../models/sort_request.dart';

class SortRepository {
  final ApiClient _apiClient;

  SortRepository(this._apiClient);

  Future<String> sendSortRequest(String text, String user) async {
    try {
      final request = SortRequest(
        text: text,
        user: user,
      );

      final response = await _apiClient.post(
        ApiConstants.sortWebhookEndpoint,
        body: request.toJson(),
      );

      print('📥 [SortRepository] Response body: ${response.body}');

      // Parse response từ n8n
      String responseText;
      try {
        // Thử parse JSON nếu response là JSON array/object
        final dynamic jsonResponse = jsonDecode(response.body);

        if (jsonResponse is List) {
          // Nếu là array, extract text từ mỗi item
          final textParts = <String>[];
          for (var item in jsonResponse) {
            if (item is Map<String, dynamic>) {
              for (var value in item.values) {
                if (value is String) {
                  textParts.add(value);
                }
              }
            } else if (item is String) {
              textParts.add(item);
            }
          }
          responseText = textParts.join('\n\n');
        } else if (jsonResponse is Map<String, dynamic>) {
          // Nếu là object, extract text từ values
          final textParts = <String>[];
          for (var value in jsonResponse.values) {
            if (value is String) {
              textParts.add(value);
            }
          }
          responseText = textParts.join('\n\n');
        } else {
          // Nếu không phải array/object, dùng toString
          responseText = jsonResponse.toString();
        }
      } catch (e) {
        // Nếu không parse được JSON, dùng plain text
        responseText = response.body;
      }

      return responseText.trim();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Gửi yêu cầu sắp xếp thất bại: $e');
    }
  }
}
