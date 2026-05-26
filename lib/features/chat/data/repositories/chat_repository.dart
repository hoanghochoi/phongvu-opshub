import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/constants/api_constants.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/sku_item.dart';

class ChatRepository {
  final ApiClient _apiClient;
  final _uuid = const Uuid();

  ChatRepository(this._apiClient);

  List<SKUItem> _parseSKUItems(String text) {
    final skuItems = <SKUItem>[];
    final blocks = text.split('\n\n');

    for (var block in blocks) {
      if (block.trim().isEmpty) continue;
      if (!block.contains('SKU:')) continue;

      final lines = block.split('\n');
      String sku = '';
      String name = '';
      String serial = '';
      String bin = '';
      String zone = '';
      String date = '';

      for (var line in lines) {
        line = line.trim();
        if (line.startsWith('SKU:')) {
          // Remove " - Đúng FIFO" or " - Chưa đúng FIFO" suffix
          sku = line
              .replaceFirst('SKU:', '')
              .replaceAll(RegExp(r'\s*-\s*(Đúng|Chưa đúng) FIFO'), '')
              .trim();
        } else if (line.startsWith('Tên:')) {
          name = line.replaceFirst('Tên:', '').trim();
        } else if (line.startsWith('Serial:')) {
          serial = line.replaceFirst('Serial:', '').trim();
        } else if (line.startsWith('Mã BIN:')) {
          bin = line.replaceFirst('Mã BIN:', '').trim();
        } else if (line.startsWith('Zone:')) {
          zone = line.replaceFirst('Zone:', '').trim();
        } else if (line.startsWith('Ngày nhập:')) {
          date = line.replaceFirst('Ngày nhập:', '').trim();
        }
      }

      if (sku.isNotEmpty && serial.isNotEmpty) {
        skuItems.add(
          SKUItem(
            id: _uuid.v4(),
            sku: sku,
            name: name,
            serial: serial,
            bin: bin,
            zone: zone,
            date: date,
          ),
        );
      }
    }

    return skuItems;
  }

  Future<Message> sendMessage(String sku, String qty, String userEmail) async {
    try {
      // Parse qty to int (default 1)
      final qtyInt = int.tryParse(qty) ?? 1;

      // Send to backend /sort/fifo-check. Backend reads the user from JWT.
      final response = await _apiClient.post(
        ApiConstants.legacyFifoCheckEndpoint,
        body: {'text': sku, 'qty': qtyInt},
      );

      if (kDebugMode) {
        debugPrint('📥 [ChatRepository] Response: ${response.statusCode}');
      }

      String responseText;
      List<SKUItem>? skuItems;
      List<SKUItem>? suggestedSkuItems;

      try {
        final dynamic jsonResponse = jsonDecode(response.body);

        if (jsonResponse is List) {
          // SKU lookup: backend returns list of inventory items
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
          skuItems = _parseSKUItems(responseText);
        } else if (jsonResponse is Map<String, dynamic>) {
          // Serial lookup: backend returns { found, is_oldest, message, item }
          if (jsonResponse.containsKey('is_oldest')) {
            final message = jsonResponse['message'] ?? '';
            final item = jsonResponse['item'] as Map<String, dynamic>?;
            final suggestedItem =
                jsonResponse['suggested_item'] as Map<String, dynamic>?;

            responseText = message;

            if (item != null) {
              // Create SKU bubble from serial check item (same style as SKU search)
              skuItems = [
                SKUItem(
                  id: _uuid.v4(),
                  sku: item['sku']?.toString() ?? '',
                  name: item['sku_name']?.toString() ?? '',
                  serial: item['serial_number']?.toString() ?? '',
                  bin: item['bin']?.toString() ?? '',
                  zone: item['zone']?.toString() ?? '',
                  date: item['import_date']?.toString() ?? '',
                ),
              ];
            } else {
              skuItems = [];
            }

            // Parse suggested item when FIFO check is wrong
            if (suggestedItem != null) {
              suggestedSkuItems = [
                SKUItem(
                  id: _uuid.v4(),
                  sku: suggestedItem['sku']?.toString() ?? '',
                  name: suggestedItem['sku_name']?.toString() ?? '',
                  serial: suggestedItem['serial_number']?.toString() ?? '',
                  bin: suggestedItem['bin']?.toString() ?? '',
                  zone: suggestedItem['zone']?.toString() ?? '',
                  date: suggestedItem['import_date']?.toString() ?? '',
                ),
              ];
            }
          } else if (jsonResponse.containsKey('found') &&
              jsonResponse['found'] == false) {
            // Serial not found
            responseText = jsonResponse['message'] ?? 'Không tìm thấy';
            skuItems = [];
          } else {
            // Fallback for other map responses
            final textParts = <String>[];
            for (var value in jsonResponse.values) {
              if (value is String) textParts.add(value);
            }
            responseText = textParts.join('\n\n');
          }
        } else {
          responseText = jsonResponse.toString();
        }
      } catch (e) {
        responseText = response.body;
      }

      // Only parse SKU items if not already set by serial check
      skuItems ??= _parseSKUItems(responseText);

      return Message(
        id: _uuid.v4(),
        content: responseText.trim(),
        isUser: false,
        timestamp: DateTime.now(),
        skuItems: skuItems,
        suggestedItems: suggestedSkuItems,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Chưa gửi được yêu cầu. Vui lòng thử lại.');
    }
  }
}
