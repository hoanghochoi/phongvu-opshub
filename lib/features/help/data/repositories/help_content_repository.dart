import 'dart:convert';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
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
    required bool isPublished,
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
        'isPublished': isPublished,
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
    required bool isPublished,
  }) async {
    final response = await _apiClient.patch(
      ApiConstants.adminHelpContentPageEndpoint(key),
      body: {
        'title': title,
        'fileName': fileName,
        'parentKey': parentKey,
        'sortOrder': sortOrder,
        'markdown': markdown,
        'isPublished': isPublished,
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
}
