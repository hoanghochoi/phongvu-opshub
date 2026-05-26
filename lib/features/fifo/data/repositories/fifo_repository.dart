import 'dart:convert';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/fifo_check_result.dart';
import '../../domain/entities/fifo_inventory_item.dart';

class FifoRepository {
  final ApiClient _apiClient;

  FifoRepository(this._apiClient);

  Future<FifoCheckResult> check({
    required String text,
    required bool includeExported,
  }) async {
    try {
      final response = await _apiClient.post(
        ApiConstants.fifoCheckEndpoint,
        body: {'text': text, 'includeExported': includeExported},
      );
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) {
        throw ApiException('Phản hồi FIFO không hợp lệ');
      }
      return FifoCheckResult.fromJson(json);
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException('Chưa kiểm tra được FIFO. Vui lòng thử lại.');
    }
  }

  Future<FifoInventoryItem> setExported({
    required String inventoryId,
    required bool exported,
  }) async {
    try {
      final response = await _apiClient.post(
        ApiConstants.fifoExportEndpoint,
        body: {'inventoryId': inventoryId, 'exported': exported},
      );
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic> ||
          json['item'] is! Map<String, dynamic>) {
        throw ApiException('Phản hồi xuất kho không hợp lệ');
      }
      return FifoInventoryItem.fromJson(json['item'] as Map<String, dynamic>);
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException(
        'Chưa cập nhật được trạng thái xuất kho. Vui lòng thử lại.',
      );
    }
  }
}
