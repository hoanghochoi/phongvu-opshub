import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/constants/api_constants.dart';
import '../../domain/entities/message.dart';
import '../models/n8n_request.dart';

class ChatRepository {
  final ApiClient _apiClient;
  final _uuid = const Uuid();

  ChatRepository(this._apiClient);

  Future<Message> sendMessage(String sku, String qty, String userEmail) async {
    try {
      final request = N8nRequest(
        userEmail: userEmail,
        sku: sku,
        qty: qty,
        timestamp: DateTime.now().toIso8601String(),
      );

      final response = await _apiClient.post(
        ApiConstants.chatWebhookEndpoint,
        body: request.toJson(),
      );

      print('📥 [ChatRepository] Response body: ${response.body}');

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
              // Bỏ qua keys như sku_0, sku_1, chỉ lấy values
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

      // Tạo bot message với response từ n8n
      return Message(
        id: _uuid.v4(),
        content: responseText.trim(),
        isUser: false,
        timestamp: DateTime.now(),
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Gửi tin nhắn thất bại: $e');
    }
  }
}
