import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/logging/app_logger.dart';

const int warrantyUploadMaxImageBytes = 10 * 1024 * 1024;
const Duration warrantyUploadMinTimeout = Duration(seconds: 60);
const Duration warrantyUploadMaxTimeout = Duration(minutes: 8);

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
    var totalBytes = 0;
    var uploadTimeout = ApiConstants.uploadTimeout;
    try {
      await AppLogger.instance.info(
        'WarrantyUpload',
        'Warranty upload started',
        context: {
          'imageCount': images.length,
          'receiptLength': receiptNumber.length,
        },
      );
      final List<http.MultipartFile> multipartFiles = [];
      for (int i = 0; i < images.length; i++) {
        final file = images[i];
        final fileSize = await _warrantyImageSize(file, index: i);
        totalBytes += fileSize;
        if (fileSize > warrantyUploadMaxImageBytes) {
          await AppLogger.instance.warn(
            'WarrantyUpload',
            'Warranty upload rejected oversized image',
            context: {
              'index': i,
              'fileSize': fileSize,
              'maxImageBytes': warrantyUploadMaxImageBytes,
            },
          );
          throw ApiException(
            'Có ảnh lớn hơn 10 MB. Vui lòng chọn lại ảnh nhỏ hơn.',
          );
        }
        final fileName = _lastPathSegment(file.path);
        final mimeType = warrantyMimeTypeFor(
          fileName: fileName,
          path: file.path,
        );
        if (mimeType == null) {
          await AppLogger.instance.warn(
            'WarrantyUpload',
            'Warranty upload rejected invalid image type',
            context: {'index': i, 'extension': _extensionFor(fileName)},
          );
          throw ApiException('Chỉ hỗ trợ ảnh JPG, PNG, WebP, HEIC hoặc HEIF.');
        }
        final multipartFile = await http.MultipartFile.fromPath(
          'images',
          file.path,
          filename: _safeUploadFileName(i, fileName, mimeType),
          contentType: MediaType.parse(mimeType),
        );
        multipartFiles.add(multipartFile);
      }
      uploadTimeout = warrantyUploadTimeoutFor(
        totalBytes: totalBytes,
        imageCount: images.length,
      );
      await AppLogger.instance.info(
        'WarrantyUpload',
        'Warranty upload request prepared',
        context: {
          'imageCount': images.length,
          'imageTotalBytes': totalBytes,
          'timeoutSeconds': uploadTimeout.inSeconds,
        },
      );

      final response = await _apiClient.postMultipart(
        ApiConstants.saveWarrantyEndpoint,
        fields: buildWarrantyMultipartFields(receiptNumber: receiptNumber),
        files: multipartFiles,
        timeout: uploadTimeout,
      );

      if (kDebugMode) {
        debugPrint(
          '📥 [WarrantyRepository.saveWarranty] Response: ${response.statusCode}',
        );
      }

      final dynamic jsonResponse = jsonDecode(response.body);
      Map<String, dynamic> responseData;

      if (jsonResponse is List && jsonResponse.isNotEmpty) {
        responseData = jsonResponse[0] as Map<String, dynamic>;
      } else if (jsonResponse is Map<String, dynamic>) {
        responseData = jsonResponse;
      } else {
        throw ApiException('Dữ liệu biên nhận chưa hợp lệ. Vui lòng thử lại.');
      }

      await AppLogger.instance.info(
        'WarrantyUpload',
        'Warranty upload succeeded',
        context: {
          'imageCount': images.length,
          'imageTotalBytes': totalBytes,
          'timeoutSeconds': uploadTimeout.inSeconds,
        },
      );
      return responseData;
    } on ApiException catch (e) {
      await AppLogger.instance.warn(
        'WarrantyUpload',
        'Warranty upload rejected',
        context: {
          'message': e.message,
          'imageCount': images.length,
          'imageTotalBytes': totalBytes,
          'timeoutSeconds': uploadTimeout.inSeconds,
        },
      );
      rethrow;
    } catch (e) {
      await AppLogger.instance.error(
        'WarrantyUpload',
        'Warranty upload failed',
        error: e,
        upload: true,
        context: {
          'imageCount': images.length,
          'imageTotalBytes': totalBytes,
          'timeoutSeconds': uploadTimeout.inSeconds,
        },
      );
      throw ApiException('Chưa lưu được biên nhận. Vui lòng thử lại.');
    }
  }

  @visibleForTesting
  static Map<String, String> buildWarrantyMultipartFields({
    required String receiptNumber,
  }) {
    return {'receipt': receiptNumber.trim()};
  }

  @visibleForTesting
  static Duration warrantyUploadTimeoutFor({
    required int totalBytes,
    required int imageCount,
  }) {
    const bytesPerSecondFloor = 512 * 1024;
    final transferSeconds = (totalBytes / bytesPerSecondFloor).ceil();
    final effectiveImageCount = math.max(imageCount, 1).toInt();
    final overheadSeconds = 30 + (effectiveImageCount * 3);
    final seconds = math
        .max(
          warrantyUploadMinTimeout.inSeconds,
          transferSeconds + overheadSeconds,
        )
        .toInt();
    return Duration(
      seconds: math.min(seconds, warrantyUploadMaxTimeout.inSeconds).toInt(),
    );
  }

  static String? warrantyMimeTypeFor({required String fileName, String? path}) {
    final extension = _extensionFor(fileName).isNotEmpty
        ? _extensionFor(fileName)
        : _extensionFor(path ?? '');
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      _ => null,
    };
  }

  static Future<int> _warrantyImageSize(File file, {required int index}) async {
    try {
      return await file.length();
    } on FileSystemException {
      await AppLogger.instance.warn(
        'WarrantyUpload',
        'Warranty upload rejected unreadable image',
        context: {'index': index},
      );
      throw ApiException(
        'Có ảnh không còn mở được. Vui lòng xóa ảnh đó rồi chọn lại.',
      );
    }
  }

  static String _safeUploadFileName(
    int index,
    String fileName,
    String mimeType,
  ) {
    final trimmed = fileName.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final extension = switch (mimeType) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/heic' => 'heic',
      'image/heif' => 'heif',
      _ => 'jpg',
    };
    return 'image_$index.$extension';
  }

  static String _extensionFor(String value) {
    final name = _lastPathSegment(value).toLowerCase();
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == name.length - 1) return '';
    return name.substring(dotIndex + 1).split('?').first;
  }

  static String _lastPathSegment(String value) {
    final normalized = value.replaceAll('\\', '/');
    final segments = normalized.split('/').where((part) => part.isNotEmpty);
    return segments.isEmpty ? '' : segments.last;
  }

  /// GET /warranties  (show all - filtered server-side by JWT user or storeId)
  Future<List<Map<String, dynamic>>> showAllWarranty(String userEmail) async {
    try {
      final response = await _apiClient.get(
        ApiConstants.showAllWarrantyEndpoint,
      );

      if (kDebugMode) {
        debugPrint(
          '📥 [WarrantyRepository.showAllWarranty] Response: ${response.statusCode}',
        );
      }

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
      throw ApiException(
        'Chưa tải được danh sách biên nhận. Vui lòng thử lại.',
      );
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

      if (kDebugMode) {
        debugPrint(
          '📥 [WarrantyRepository.searchWarranty] Response: ${response.statusCode}',
        );
      }

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
      throw ApiException('Chưa tìm được biên nhận. Vui lòng thử lại.');
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

      if (kDebugMode) {
        debugPrint(
          '📥 [WarrantyRepository.getWarrantyDetails] Response: ${response.statusCode}',
        );
      }

      final dynamic jsonResponse = jsonDecode(response.body);

      if (jsonResponse is List && jsonResponse.isNotEmpty) {
        return jsonResponse[0] as Map<String, dynamic>;
      } else if (jsonResponse is Map<String, dynamic>) {
        return jsonResponse;
      }

      throw ApiException('Không tìm thấy biên nhận.');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Chưa mở được chi tiết biên nhận. Vui lòng thử lại.');
    }
  }
}
