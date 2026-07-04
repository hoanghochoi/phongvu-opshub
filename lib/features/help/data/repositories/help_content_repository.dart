import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/help_content_page.dart';

class HelpContentRepository {
  HelpContentRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<HelpContentAdminSnapshot> fetchAdminSnapshot() async {
    final response = await _apiClient.get(
      ApiConstants.adminHelpContentPagesEndpoint,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return HelpContentAdminSnapshot.fromJson(data);
  }

  Future<HelpContentPublicSnapshot> fetchPublicSnapshot() async {
    final response = await _apiClient.get(
      ApiConstants.helpContentPublicEndpoint,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return HelpContentAdminSnapshot.fromJson(data);
  }

  Future<HelpContentPage> createPage({
    required String key,
    required String title,
    required String fileName,
    required String? parentKey,
    required int sortOrder,
    required String markdown,
    required HelpPageVisibility visibility,
  }) async {
    final response = await _apiClient.post(
      ApiConstants.adminHelpContentPagesEndpoint,
      body: {
        'key': key,
        'title': title,
        'fileName': fileName,
        'parentKey': parentKey,
        'sortOrder': sortOrder,
        'markdown': markdown,
        'visibility': visibility.apiValue,
      },
    );
    return HelpContentPage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<HelpContentPage> updatePage(
    String key, {
    required String title,
    required String fileName,
    required String? parentKey,
    required int sortOrder,
    required String markdown,
    required HelpPageVisibility visibility,
  }) async {
    final response = await _apiClient.patch(
      ApiConstants.adminHelpContentPageEndpoint(key),
      body: {
        'title': title,
        'fileName': fileName,
        'parentKey': parentKey,
        'sortOrder': sortOrder,
        'markdown': markdown,
        'visibility': visibility.apiValue,
      },
    );
    return HelpContentPage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<HelpContentSeedResult> restoreFromDocs() async {
    final response = await _apiClient.post(
      ApiConstants.adminHelpContentSeedEndpoint,
      body: const {'overwriteExisting': true},
    );
    return HelpContentSeedResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<HelpContentAssetUploadResult> uploadAsset({
    String? pageKey,
    String? path,
    Uint8List? bytes,
    required String fileName,
  }) async {
    final multipartFile = await _helpAssetMultipartFile(
      path: path,
      bytes: bytes,
      fileName: fileName,
    );
    final response = await _apiClient.postMultipart(
      ApiConstants.adminHelpContentAssetsEndpoint,
      fields: {
        if (pageKey != null && pageKey.trim().isNotEmpty)
          'pageKey': pageKey.trim().toLowerCase(),
      },
      files: [multipartFile],
      timeout: ApiConstants.uploadTimeout,
    );
    return HelpContentAssetUploadResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<http.MultipartFile> _helpAssetMultipartFile({
    String? path,
    Uint8List? bytes,
    required String fileName,
  }) async {
    if (path == null && bytes == null) {
      throw ApiException('Chưa đọc được file ảnh. Vui lòng chọn ảnh khác.');
    }

    final mimeType = _imageMimeTypeFor(fileName: fileName, path: path);
    if (mimeType == null) {
      throw ApiException('Chỉ hỗ trợ ảnh JPG, PNG, WebP, HEIC hoặc HEIF.');
    }

    final mediaType = MediaType.parse(mimeType);
    final uploadFileName = _safeUploadFileName(fileName, path, mimeType);
    if (path != null) {
      return http.MultipartFile.fromPath(
        'image',
        path,
        filename: uploadFileName,
        contentType: mediaType,
      );
    }

    return http.MultipartFile.fromBytes(
      'image',
      bytes!,
      filename: uploadFileName,
      contentType: mediaType,
    );
  }

  static String? _imageMimeTypeFor({required String fileName, String? path}) {
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

  static String _safeUploadFileName(
    String fileName,
    String? path,
    String mimeType,
  ) {
    final trimmed = fileName.trim();
    if (trimmed.isNotEmpty) return trimmed;

    final pathName = _lastPathSegment(path ?? '').trim();
    if (pathName.isNotEmpty) return pathName;

    final extension = switch (mimeType) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/heic' => 'heic',
      'image/heif' => 'heif',
      _ => 'jpg',
    };
    return 'help-image.$extension';
  }

  static String _extensionFor(String value) {
    final name = _lastPathSegment(value).toLowerCase();
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == name.length - 1) return '';
    return name.substring(dotIndex + 1).split('?').first;
  }

  static String _lastPathSegment(String value) {
    final normalized = value.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? normalized : parts.last;
  }
}
