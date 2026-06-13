import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../core/network/api_exception.dart';

Map<String, String> buildFeedbackMultipartFields({
  required String functionName,
  required String description,
}) {
  return {'function': functionName.trim(), 'description': description.trim()};
}

Future<http.MultipartFile> buildFeedbackImageMultipartFile({
  required File image,
  required int index,
}) async {
  final fileName = _lastPathSegment(image.path);
  final mimeType = feedbackImageMimeTypeFor(
    fileName: fileName,
    path: image.path,
  );
  if (mimeType == null) {
    throw ApiException('Chỉ hỗ trợ ảnh JPG, PNG, WebP, HEIC hoặc HEIF.');
  }

  return http.MultipartFile.fromPath(
    'images',
    image.path,
    filename: safeFeedbackImageFileName(
      index: index,
      fileName: fileName,
      mimeType: mimeType,
    ),
    contentType: MediaType.parse(mimeType),
  );
}

String? feedbackImageMimeTypeFor({required String fileName, String? path}) {
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

String safeFeedbackImageFileName({
  required int index,
  required String fileName,
  required String mimeType,
}) {
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
  return 'feedback_$index.$extension';
}

String _extensionFor(String value) {
  final name = _lastPathSegment(value).toLowerCase();
  final dotIndex = name.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == name.length - 1) return '';
  return name.substring(dotIndex + 1).split('?').first;
}

String _lastPathSegment(String value) {
  final normalized = value.replaceAll('\\', '/');
  final segments = normalized.split('/').where((part) => part.isNotEmpty);
  return segments.isEmpty ? '' : segments.last;
}
