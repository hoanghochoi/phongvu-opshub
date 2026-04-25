import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/constants/api_constants.dart';

class WarrantyRepository {
  final ApiClient _apiClient;

  WarrantyRepository(this._apiClient);

  /// Save warranty + upload images (multipart)
  /// POST /upload/warranty
  /// Fields: { receipt } + files: images[]
  Future<Map<String, dynamic>> saveWarranty({
    required String userEmail,
    required String receiptNumber,
    required List<File> images,
  }) async {
    try {
      final List<http.MultipartFile> multipartFiles = [];
      for (int i = 0; i < images.length; i++) {
        final file = images[i];
        final multipartFile = await http.MultipartFile.fromPath(
          'images',   // New backend uses 'images' (FilesInterceptor)
          file.path,
          filename: 'image_$i.jpg',
        );
        multipartFiles.add(multipartFile);
      }

      final response = await _apiClient.postMultipart(
        ApiConstants.saveWarrantyEndpoint,
        fields: {
          'user': userEmail,
          'receipt': receiptNumber,
        },
        files: multipartFiles,
        timeout: ApiConstants.uploadTimeout,
      );

      if (kDebugMode) debugPrint('📥 [WarrantyRepository.saveWarranty] Response: ${response.statusCode}');

      final dynamic jsonResponse = jsonDecode(response.body);
      Map<String, dynamic> responseData;

      if (jsonResponse is List && jsonResponse.isNotEmpty) {
        responseData = jsonResponse[0] as Map<String, dynamic>;
      } else if (jsonResponse is Map<String, dynamic>) {
        responseData = jsonResponse;
      } else {
        throw ApiException('Response format không hợp lệ');
      }

      return responseData;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Lỗi khi lưu biên nhận: $e');
    }
  }

  /// GET /warranties  (show all - filtered server-side by JWT user or storeId)
  Future<List<Map<String, dynamic>>> showAllWarranty(String userEmail) async {
    try {
      final response = await _apiClient.get(
        ApiConstants.showAllWarrantyEndpoint,
      );

      if (kDebugMode) debugPrint('📥 [WarrantyRepository.showAllWarranty] Response: ${response.statusCode}');

      final dynamic jsonResponse = jsonDecode(response.body);

      if (jsonResponse is List) {
        return List<Map<String, dynamic>>.from(
          jsonResponse.map((item) => item as Map<String, dynamic>),
        );
      } else if (jsonResponse is Map<String, dynamic>) {
        return [jsonResponse];
      }

      return [];
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Lỗi khi lấy danh sách biên nhận: $e');
    }
  }

  /// GET /warranties/search?receipt=xxx
  Future<List<Map<String, dynamic>>> searchWarranty({
    required String userEmail,
    required String receiptNumber,
  }) async {
    try {
      final response = await _apiClient.get(
        '${ApiConstants.searchWarrantyEndpoint}?receipt=${Uri.encodeComponent(receiptNumber)}',
      );

      if (kDebugMode) debugPrint('📥 [WarrantyRepository.searchWarranty] Response: ${response.statusCode}');

      final dynamic jsonResponse = jsonDecode(response.body);

      if (jsonResponse is List) {
        return List<Map<String, dynamic>>.from(
          jsonResponse.map((item) => item as Map<String, dynamic>),
        );
      } else if (jsonResponse is Map<String, dynamic>) {
        return [jsonResponse];
      }

      return [];
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Lỗi khi tìm kiếm biên nhận: $e');
    }
  }

  /// GET /warranties/detail?receipt=xxx
  Future<Map<String, dynamic>> getWarrantyDetails({
    required String userEmail,
    required String receiptNumber,
  }) async {
    try {
      final response = await _apiClient.get(
        '${ApiConstants.getWarrantyEndpoint}?receipt=${Uri.encodeComponent(receiptNumber)}',
      );

      if (kDebugMode) debugPrint('📥 [WarrantyRepository.getWarrantyDetails] Response: ${response.statusCode}');

      final dynamic jsonResponse = jsonDecode(response.body);

      if (jsonResponse is List && jsonResponse.isNotEmpty) {
        return jsonResponse[0] as Map<String, dynamic>;
      } else if (jsonResponse is Map<String, dynamic>) {
        return jsonResponse;
      }

      throw ApiException('Không tìm thấy biên nhận');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Lỗi khi lấy chi tiết biên nhận: $e');
    }
  }
}
