import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_exception.dart';
import '../constants/api_constants.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  final http.Client _client = http.Client();
  String? _authToken;

  void setAuthToken(String? token) {
    _authToken = token;
    if (kDebugMode) debugPrint('🔑 [ApiClient] Auth token set: ${token != null ? "${token.substring(0, 10)}..." : "null"}');
  }

  Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };

  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? queryParameters,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');
      final url = queryParameters != null
          ? uri.replace(queryParameters: queryParameters)
          : uri;

      final response = await _client
          .get(url, headers: _authToken != null ? {'Authorization': 'Bearer $_authToken'} : null)
          .timeout(ApiConstants.defaultTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      } else if (response.statusCode >= 500) {
        throw ServerException(
          'Lỗi server: ${response.statusCode}',
          response.statusCode,
        );
      } else {
        throw ApiException(
          'Request thất bại: ${response.statusCode}',
          response.statusCode,
        );
      }
    } on SocketException {
      throw NetworkException();
    } on ApiException {
      rethrow;
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        throw TimeoutException();
      }
      throw ApiException('Lỗi không xác định: $e');
    }
  }

  Future<http.Response> post(
    String endpoint, {
    required Map<String, dynamic> body,
    Duration? timeout,
  }) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}$endpoint');

      if (kDebugMode) {
        debugPrint('🔵 API POST: $url');
        debugPrint('🔵 Body: ${jsonEncode(body)}');
      }

      final response = await _client
          .post(
            url,
            headers: _authHeaders,
            body: jsonEncode(body),
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (kDebugMode) {
        debugPrint('✅ Response: ${response.statusCode}');
      }

      // Accept response if:
      // 1. Status code is 2xx (success)
      // 2. OR status code is 4xx but body contains valid JSON (n8n behavior)
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        // Auth errors should always throw — never treat as success
        if (kDebugMode) debugPrint('🔒 [ApiClient] Auth error ${response.statusCode}');
        throw ApiException(
          'Phiên đăng nhập hết hạn. Vui lòng đăng nhập lại.',
          response.statusCode,
        );
      } else if (response.statusCode >= 400 && response.statusCode < 500) {
        // Try to parse JSON - if successful, treat as valid response (n8n behavior)
        try {
          jsonDecode(response.body);
          if (kDebugMode) debugPrint('⚠️ [ApiClient] Status ${response.statusCode} but valid JSON, treating as success');
          return response;
        } catch (e) {
          // Not valid JSON, throw error
          throw ApiException(
            'Request thất bại: ${response.statusCode}',
            response.statusCode,
          );
        }
      } else if (response.statusCode >= 500) {
        throw ServerException(
          'Lỗi server: ${response.statusCode}',
          response.statusCode,
        );
      } else {
        throw ApiException(
          'Request thất bại: ${response.statusCode}',
          response.statusCode,
        );
      }
    } on SocketException catch (e) {
      if (kDebugMode) debugPrint('❌ SocketException: $e');
      throw NetworkException();
    } on ApiException {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Exception: ${e.runtimeType} - $e');
      if (e.toString().contains('TimeoutException')) {
        throw TimeoutException();
      }
      throw ApiException('Lỗi không xác định: $e');
    }
  }

  /// Upload files using multipart/form-data
  Future<http.Response> postMultipart(
    String endpoint, {
    required Map<String, String> fields,
    required List<http.MultipartFile> files,
    Duration? timeout,
  }) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}$endpoint');

      if (kDebugMode) {
        debugPrint('🔵 API POST MULTIPART: $url');
        debugPrint('🔵 Files count: ${files.length}');
      }

      // Create multipart request
      final request = http.MultipartRequest('POST', url);

      // Add JWT auth header
      if (_authToken != null) {
        request.headers['Authorization'] = 'Bearer $_authToken';
      }

      // Add fields
      request.fields.addAll(fields);

      // Add files
      request.files.addAll(files);

      // Send request
      final streamedResponse = await request
          .send()
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      // Convert streamed response to regular response
      final response = await http.Response.fromStream(streamedResponse);

      if (kDebugMode) {
        debugPrint('✅ Response: ${response.statusCode}');
      }

      // Accept response if:
      // 1. Status code is 2xx (success)
      // 2. OR status code is 4xx but body contains valid JSON (n8n behavior)
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      } else if (response.statusCode >= 400 && response.statusCode < 500) {
        // Try to parse JSON - if successful, treat as valid response
        try {
          jsonDecode(response.body);
          if (kDebugMode) debugPrint('⚠️ [ApiClient] Status ${response.statusCode} but valid JSON, treating as success');
          return response;
        } catch (e) {
          // Not valid JSON, throw error
          throw ApiException(
            'Request thất bại: ${response.statusCode}',
            response.statusCode,
          );
        }
      } else if (response.statusCode >= 500) {
        throw ServerException(
          'Lỗi server: ${response.statusCode}',
          response.statusCode,
        );
      } else {
        throw ApiException(
          'Request thất bại: ${response.statusCode}',
          response.statusCode,
        );
      }
    } on SocketException catch (e) {
      if (kDebugMode) debugPrint('❌ SocketException: $e');
      throw NetworkException();
    } on ApiException {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Exception: ${e.runtimeType} - $e');
      if (e.toString().contains('TimeoutException')) {
        throw TimeoutException();
      }
      throw ApiException('Lỗi không xác định: $e');
    }
  }

  void dispose() {
    _client.close();
  }
}
