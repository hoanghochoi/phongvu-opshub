import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart'
    show ImageRenderMethodForWeb;

import '../constants/api_constants.dart';
import 'api_client.dart';

/// Returns the authentication headers for a protected OpsHub media URL.
///
/// The token is deliberately scoped to the API origin and the `/media/`
/// endpoint below the configured API base path. Legacy `/uploads/` URLs and
/// every external origin receive no credentials.
Map<String, String> privateMediaHeaders(
  String url, {
  String apiBaseUrl = ApiConstants.baseUrl,
  String? authToken,
}) {
  if (!isProtectedPrivateMediaUrl(url, apiBaseUrl: apiBaseUrl)) {
    return const <String, String>{};
  }

  final token = (authToken ?? ApiClient().authToken)?.trim();
  if (token == null || token.isEmpty) return const <String, String>{};

  return <String, String>{'Authorization': 'Bearer $token'};
}

/// Uses the web renderer that can carry headers for protected media while
/// keeping legacy public uploads on the browser's native image path.
ImageRenderMethodForWeb privateMediaImageRenderMethodForWeb(
  String url, {
  String apiBaseUrl = ApiConstants.baseUrl,
}) {
  return isProtectedPrivateMediaUrl(url, apiBaseUrl: apiBaseUrl)
      ? ImageRenderMethodForWeb.HttpGet
      : ImageRenderMethodForWeb.HtmlImage;
}

bool isProtectedPrivateMediaUrl(
  String url, {
  String apiBaseUrl = ApiConstants.baseUrl,
}) {
  final target = Uri.tryParse(url.trim());
  final base = Uri.tryParse(apiBaseUrl.trim());
  if (target == null || base == null) return false;
  if (!_isHttpUri(target) || !_isHttpUri(base)) return false;
  if (target.userInfo.isNotEmpty || base.userInfo.isNotEmpty) return false;
  if (target.origin != base.origin) return false;

  final basePath = _normalizedBasePath(base.path);
  return target.path.startsWith('$basePath/media/');
}

bool _isHttpUri(Uri uri) {
  return uri.isAbsolute &&
      uri.host.isNotEmpty &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}

String _normalizedBasePath(String path) {
  if (path.isEmpty || path == '/') return '';
  var normalized = path.startsWith('/') ? path : '/$path';
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}
