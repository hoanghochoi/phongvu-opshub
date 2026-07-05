import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_exception.dart';
import '../constants/api_constants.dart';

typedef AuthFailureHandler = Future<void> Function(ApiException exception);

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal() : _client = http.Client();

  @visibleForTesting
  ApiClient.test(this._client);

  final http.Client _client;
  String? _authToken;
  AuthFailureHandler? _authFailureHandler;
  bool _handlingAuthFailure = false;

  void setAuthToken(String? token) {
    _authToken = token;
    if (kDebugMode) {
      debugPrint(
        '[ApiClient] Auth token ${token == null ? "cleared" : "updated"}',
      );
    }
  }

  String? get authToken => _authToken;

  void setAuthFailureHandler(AuthFailureHandler? handler) {
    _authFailureHandler = handler;
  }

  Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };

  String _messageForStatus(int statusCode) {
    if (statusCode == 401) {
      return 'Phiên làm việc đã hết hạn. Vui lòng đăng nhập lại.';
    }
    if (statusCode == 403) return 'Bạn không có quyền thực hiện thao tác này.';
    if (statusCode == 404) return 'Không tìm thấy dữ liệu phù hợp.';
    if (statusCode >= 500) {
      return 'Hệ thống đang bận. Vui lòng thử lại sau ít phút.';
    }
    return 'Chưa thực hiện được. Vui lòng kiểm tra lại thông tin và thử lại.';
  }

  ApiException _exceptionForResponse(int statusCode, String body) {
    final message = statusCode == 401
        ? _messageForAuthFailure(body)
        : _messageFromBody(body) ?? _messageForStatus(statusCode);
    if (statusCode >= 500) return ServerException(message, statusCode);
    return ApiException(message, statusCode);
  }

  String _messageForAuthFailure(String body) {
    final message = _messageFromBody(body);
    if (message == null || message.trim().isEmpty) {
      return _messageForStatus(401);
    }
    final lower = message.trim().toLowerCase();
    if (lower == 'unauthorized' ||
        lower.contains('jwt expired') ||
        lower.contains('invalid token') ||
        lower.contains('expired')) {
      return _messageForStatus(401);
    }
    return message;
  }

  String? _messageFromBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message;
        }
        if (message is List && message.isNotEmpty) {
          return message.join('\n');
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _notifyAuthFailure(ApiException exception) async {
    final handler = _authFailureHandler;
    if (handler == null || _authToken == null || _handlingAuthFailure) return;
    _handlingAuthFailure = true;
    try {
      await handler(exception);
    } finally {
      _handlingAuthFailure = false;
    }
  }

  Future<Never> _throwForResponse(http.Response response) async {
    final exception = _exceptionForResponse(response.statusCode, response.body);
    if (response.statusCode == 401) {
      if (kDebugMode) {
        debugPrint('🔒 [ApiClient] Auth error ${response.statusCode}');
      }
      await _notifyAuthFailure(exception);
    }
    throw exception;
  }

  ApiException _unexpectedException(Object error) {
    if (error.toString().contains('TimeoutException')) {
      return TimeoutException();
    }
    return ApiException('Có lỗi xảy ra. Vui lòng thử lại sau ít phút.');
  }

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
          .get(
            url,
            headers: _authToken != null
                ? {'Authorization': 'Bearer $_authToken'}
                : null,
          )
          .timeout(ApiConstants.defaultTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      await _throwForResponse(response);
    } on SocketException {
      throw NetworkException();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _unexpectedException(e);
    }
  }

  Future<List<int>> getBytes(
    String endpoint, {
    Map<String, String>? queryParameters,
    Duration? timeout,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');
      final url = queryParameters != null
          ? uri.replace(queryParameters: queryParameters)
          : uri;
      final response = await _client
          .get(
            url,
            headers: _authToken != null
                ? {'Authorization': 'Bearer $_authToken'}
                : null,
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
      await _throwForResponse(response);
    } on SocketException {
      throw NetworkException();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _unexpectedException(e);
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
      }

      final response = await _client
          .post(url, headers: _authHeaders, body: jsonEncode(body))
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (kDebugMode) {
        debugPrint('✅ Response: ${response.statusCode}');
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      await _throwForResponse(response);
    } on SocketException catch (e) {
      if (kDebugMode) debugPrint('❌ SocketException: $e');
      throw NetworkException();
    } on ApiException {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Exception: ${e.runtimeType} - $e');
      throw _unexpectedException(e);
    }
  }

  Future<http.Response> patch(
    String endpoint, {
    required Map<String, dynamic> body,
    Duration? timeout,
  }) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}$endpoint');
      final response = await _client
          .patch(url, headers: _authHeaders, body: jsonEncode(body))
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      await _throwForResponse(response);
    } on SocketException {
      throw NetworkException();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _unexpectedException(e);
    }
  }

  Future<http.Response> put(
    String endpoint, {
    required Map<String, dynamic> body,
    Duration? timeout,
  }) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}$endpoint');
      final response = await _client
          .put(url, headers: _authHeaders, body: jsonEncode(body))
          .timeout(timeout ?? ApiConstants.defaultTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      await _throwForResponse(response);
    } on SocketException {
      throw NetworkException();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _unexpectedException(e);
    }
  }

  Future<http.Response> delete(String endpoint, {Duration? timeout}) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}$endpoint');
      final response = await _client
          .delete(url, headers: _authHeaders)
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      await _throwForResponse(response);
    } on SocketException {
      throw NetworkException();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _unexpectedException(e);
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
      final streamedResponse = await request.send().timeout(
        timeout ?? ApiConstants.defaultTimeout,
      );

      // Convert streamed response to regular response
      final response = await http.Response.fromStream(streamedResponse);

      if (kDebugMode) {
        debugPrint('✅ Response: ${response.statusCode}');
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      await _throwForResponse(response);
    } on SocketException catch (e) {
      if (kDebugMode) debugPrint('❌ SocketException: $e');
      throw NetworkException();
    } on ApiException {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Exception: ${e.runtimeType} - $e');
      throw _unexpectedException(e);
    }
  }

  void dispose() {
    _client.close();
  }
}
