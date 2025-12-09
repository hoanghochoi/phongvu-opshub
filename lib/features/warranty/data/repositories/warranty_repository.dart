import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/constants/api_constants.dart';

class WarrantyRepository {
  final ApiClient _apiClient;

  WarrantyRepository(this._apiClient);

  Future<Map<String, dynamic>> saveWarranty({
    required String userEmail,
    required String receiptNumber,
    required List<File> images,
  }) async {
    try {
      // Prepare multipart files
      final List<http.MultipartFile> multipartFiles = [];
      for (int i = 0; i < images.length; i++) {
        final file = images[i];
        final multipartFile = await http.MultipartFile.fromPath(
          'image$i', // Field name: image0, image1, image2, etc.
          file.path,
          filename: 'image_$i.jpg',
        );
        multipartFiles.add(multipartFile);
      }

      // Send multipart request
      final response = await _apiClient.postMultipart(
        ApiConstants.saveWarrantyEndpoint,
        fields: {
          'user': userEmail,
          'receipt': receiptNumber,
        },
        files: multipartFiles,
        timeout: ApiConstants.uploadTimeout,
      );

      print('📥 [WarrantyRepository.saveWarranty] Response: ${response.body}');

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

  Future<List<Map<String, dynamic>>> showAllWarranty(String userEmail) async {
    try {
      final response = await _apiClient.post(
        ApiConstants.showAllWarrantyEndpoint,
        body: {'user': userEmail},
      );

      print('📥 [WarrantyRepository.showAllWarranty] Response: ${response.body}');

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

  Future<List<Map<String, dynamic>>> searchWarranty({
    required String userEmail,
    required String receiptNumber,
  }) async {
    try {
      final response = await _apiClient.post(
        ApiConstants.searchWarrantyEndpoint,
        body: {
          'user': userEmail,
          'receipt': receiptNumber,
        },
      );

      print('📥 [WarrantyRepository.searchWarranty] Response: ${response.body}');

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

  Future<Map<String, dynamic>> getWarrantyDetails({
    required String userEmail,
    required String receiptNumber,
  }) async {
    try {
      final response = await _apiClient.post(
        ApiConstants.getWarrantyEndpoint,
        body: {
          'user': userEmail,
          'receipt': receiptNumber,
        },
      );

      print('📥 [WarrantyRepository.getWarrantyDetails] Response: ${response.body}');

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
