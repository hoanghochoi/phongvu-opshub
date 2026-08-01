import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../domain/support_chat_models.dart';

class SupportChatImageDraft {
  final Uint8List bytes;
  final String contentType;

  const SupportChatImageDraft({required this.bytes, required this.contentType});
}

abstract interface class SupportChatDataSource {
  Future<SupportChatThread> getMine({String? beforeSequence, int limit = 50});
  Future<SupportChatThread> sendMyText({
    required String clientMessageId,
    required String text,
  });
  Future<SupportChatThread> sendMyImages({
    required String clientMessageId,
    required List<SupportChatImageDraft> images,
  });
  Future<void> markMineRead(String lastReadSequence);
  Future<SupportChatAdminPage> listAdmin({
    required String bucket,
    String? query,
    String? cursor,
    int limit = 50,
  });
  Future<SupportChatThread> getAdminConversation(
    String conversationId, {
    String? beforeSequence,
  });
  Future<SupportChatThread> mutateAdmin(
    String conversationId,
    String action, {
    Map<String, dynamic> body = const {},
  });
  Future<SupportChatThread> sendAdminText({
    required String conversationId,
    required String clientMessageId,
    required String text,
  });
  Future<SupportChatThread> sendAdminImages({
    required String conversationId,
    required String clientMessageId,
    required List<SupportChatImageDraft> images,
  });
  Future<void> markAdminRead(String conversationId, String lastReadSequence);
  Future<Uint8List> loadPrivateImage(String url);
}

class SupportChatRepository implements SupportChatDataSource {
  final ApiClient _apiClient;

  SupportChatRepository(this._apiClient);

  @override
  Future<SupportChatThread> getMine({
    String? beforeSequence,
    int limit = 50,
  }) async {
    final response = await _apiClient.get(
      '/support-chat/me',
      queryParameters: {
        'limit': '$limit',
        if (beforeSequence?.isNotEmpty == true)
          'beforeSequence': beforeSequence!,
      },
    );
    return SupportChatThread.fromJson(_jsonObject(response.body));
  }

  @override
  Future<SupportChatThread> sendMyText({
    required String clientMessageId,
    required String text,
  }) async {
    await _apiClient.post(
      '/support-chat/me/messages',
      body: {'clientMessageId': clientMessageId, 'text': text},
      allowRateLimitCooldownBypass: true,
    );
    return getMine();
  }

  @override
  Future<SupportChatThread> sendMyImages({
    required String clientMessageId,
    required List<SupportChatImageDraft> images,
  }) async {
    await _apiClient.postMultipart(
      '/support-chat/me/image-messages',
      fields: {'clientMessageId': clientMessageId},
      files: _multipartImages(images),
      allowRateLimitCooldownBypass: true,
    );
    return getMine();
  }

  @override
  Future<void> markMineRead(String lastReadSequence) async {
    await _apiClient.post(
      '/support-chat/me/read',
      body: {'lastReadSequence': lastReadSequence},
    );
  }

  @override
  Future<SupportChatAdminPage> listAdmin({
    required String bucket,
    String? query,
    String? cursor,
    int limit = 50,
  }) async {
    final response = await _apiClient.get(
      '/support-chat/admin/conversations',
      queryParameters: {
        'bucket': bucket,
        'limit': '$limit',
        if (query?.trim().isNotEmpty == true) 'query': query!.trim(),
        if (cursor?.isNotEmpty == true) 'cursor': cursor!,
      },
    );
    return SupportChatAdminPage.fromJson(_jsonObject(response.body));
  }

  @override
  Future<SupportChatThread> getAdminConversation(
    String conversationId, {
    String? beforeSequence,
  }) async {
    final response = await _apiClient.get(
      '/support-chat/admin/conversations/$conversationId',
      queryParameters: {
        if (beforeSequence?.isNotEmpty == true)
          'beforeSequence': beforeSequence!,
      },
    );
    return SupportChatThread.fromJson(_jsonObject(response.body));
  }

  @override
  Future<SupportChatThread> mutateAdmin(
    String conversationId,
    String action, {
    Map<String, dynamic> body = const {},
  }) async {
    await _apiClient.post(
      '/support-chat/admin/conversations/$conversationId/$action',
      body: body,
      allowRateLimitCooldownBypass: true,
    );
    return getAdminConversation(conversationId);
  }

  @override
  Future<SupportChatThread> sendAdminText({
    required String conversationId,
    required String clientMessageId,
    required String text,
  }) async {
    await _apiClient.post(
      '/support-chat/admin/conversations/$conversationId/messages',
      body: {'clientMessageId': clientMessageId, 'text': text},
      allowRateLimitCooldownBypass: true,
    );
    return getAdminConversation(conversationId);
  }

  @override
  Future<SupportChatThread> sendAdminImages({
    required String conversationId,
    required String clientMessageId,
    required List<SupportChatImageDraft> images,
  }) async {
    await _apiClient.postMultipart(
      '/support-chat/admin/conversations/$conversationId/image-messages',
      fields: {'clientMessageId': clientMessageId},
      files: _multipartImages(images),
      allowRateLimitCooldownBypass: true,
    );
    return getAdminConversation(conversationId);
  }

  @override
  Future<void> markAdminRead(
    String conversationId,
    String lastReadSequence,
  ) async {
    await _apiClient.post(
      '/support-chat/admin/conversations/$conversationId/read',
      body: {'lastReadSequence': lastReadSequence},
    );
  }

  @override
  Future<Uint8List> loadPrivateImage(String url) async {
    final endpoint = _endpointForMediaUrl(url);
    return Uint8List.fromList(await _apiClient.getBytes(endpoint));
  }

  List<http.MultipartFile> _multipartImages(
    List<SupportChatImageDraft> images,
  ) => buildSupportChatMultipartImages(images);

  String _endpointForMediaUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) {
      return value.startsWith('/') ? value : '/$value';
    }
    final base = Uri.parse(ApiConstants.baseUrl);
    var path = uri.path;
    final basePath = base.path.replaceFirst(RegExp(r'/+$'), '');
    if (basePath.isNotEmpty && path.startsWith('$basePath/')) {
      path = path.substring(basePath.length);
    }
    return uri.hasQuery ? '$path?${uri.query}' : path;
  }

  Map<String, dynamic> _jsonObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('Support Chat response is not an object');
    }
    return Map<String, dynamic>.from(decoded);
  }
}

List<http.MultipartFile> buildSupportChatMultipartImages(
  List<SupportChatImageDraft> images,
) {
  return [
    for (var index = 0; index < images.length; index++)
      http.MultipartFile.fromBytes(
        'images',
        images[index].bytes,
        filename:
            'support-image-${index + 1}.${_supportImageExtension(images[index].contentType)}',
        contentType: MediaType.parse(images[index].contentType),
      ),
  ];
}

String _supportImageExtension(String contentType) => switch (contentType) {
  'image/png' => 'png',
  'image/webp' => 'webp',
  'image/heic' => 'heic',
  'image/heif' => 'heif',
  _ => 'jpg',
};
