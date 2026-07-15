import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_exception.dart';
import '../constants/api_constants.dart';

typedef AuthFailureHandler =
    Future<void> Function(ApiException exception, String failedAuthToken);
typedef ApiRateLimitObserver = void Function(ApiRateLimitEvent event);

class ConditionalGetResponse {
  final int statusCode;
  final String body;
  final Map<String, String> headers;

  const ConditionalGetResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  bool get isNotModified => statusCode == HttpStatus.notModified;

  String? get etag => headers['etag'];
}

class ApiRateLimitEvent {
  final String action;
  final String method;
  final String endpoint;
  final int attempt;
  final DateTime? retryAt;
  final String source;

  const ApiRateLimitEvent({
    required this.action,
    required this.method,
    required this.endpoint,
    required this.attempt,
    required this.retryAt,
    required this.source,
  });
}

class _EndpointRateLimitState {
  final int attempt;
  final DateTime retryAt;
  bool cooldownBypassConsumed;
  DateTime? lastDeferredEventAt;

  _EndpointRateLimitState({
    required this.attempt,
    required this.retryAt,
    this.cooldownBypassConsumed = false,
  });
}

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal() : _client = http.Client(), _now = DateTime.now;

  @visibleForTesting
  ApiClient.test(this._client, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final http.Client _client;
  final DateTime Function() _now;
  String? _authToken;
  AuthFailureHandler? _authFailureHandler;
  ApiRateLimitObserver? _rateLimitObserver;
  String? _handlingAuthFailureToken;
  final Map<String, _EndpointRateLimitState> _rateLimits = {};

  static const _rateLimitFallbackBase = Duration(seconds: 5);
  static const _rateLimitFallbackMax = Duration(minutes: 2);
  static const _deferredEventInterval = Duration(seconds: 15);

  void setAuthToken(String? token) {
    final changed = _authToken != token;
    _authToken = token;
    if (changed) _rateLimits.clear();
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

  void setRateLimitObserver(ApiRateLimitObserver? observer) {
    _rateLimitObserver = observer;
  }

  Map<String, String> _authHeadersFor(String? authToken) => {
    'Content-Type': 'application/json',
    if (authToken != null) 'Authorization': 'Bearer $authToken',
  };

  String _messageForStatus(int statusCode) {
    if (statusCode == 401) {
      return 'Phiên làm việc đã hết hạn. Vui lòng đăng nhập lại.';
    }
    if (statusCode == 403) return 'Bạn không có quyền thực hiện thao tác này.';
    if (statusCode == 404) return 'Không tìm thấy dữ liệu phù hợp.';
    if (statusCode == 429) {
      return 'Hệ thống đang giới hạn tần suất. Vui lòng chờ một chút rồi thử lại.';
    }
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

  Future<void> _notifyAuthFailure(
    ApiException exception,
    String? requestAuthToken,
  ) async {
    final handler = _authFailureHandler;
    if (handler == null ||
        requestAuthToken == null ||
        _authToken != requestAuthToken ||
        _handlingAuthFailureToken == requestAuthToken) {
      return;
    }
    _handlingAuthFailureToken = requestAuthToken;
    try {
      await handler(exception, requestAuthToken);
    } finally {
      if (_handlingAuthFailureToken == requestAuthToken) {
        _handlingAuthFailureToken = null;
      }
    }
  }

  Future<Never> _throwForResponse(
    http.Response response, {
    required String method,
    required String endpoint,
    required String? requestAuthToken,
  }) async {
    if (response.statusCode == 429) {
      final state = _registerRateLimit(method, endpoint, response.headers);
      throw RateLimitedException(
        retryAt: state.retryAt,
        message: _messageFromBody(response.body) ?? _messageForStatus(429),
      );
    }
    final exception = _exceptionForResponse(response.statusCode, response.body);
    if (response.statusCode == 401) {
      if (kDebugMode) {
        debugPrint('🔒 [ApiClient] Auth error ${response.statusCode}');
      }
      await _notifyAuthFailure(exception, requestAuthToken);
    }
    throw exception;
  }

  String _rateLimitKey(String method, String endpoint) =>
      '${method.toUpperCase()} ${endpoint.split('?').first}';

  void _ensureRequestAllowed(
    String method,
    String endpoint, {
    required bool allowRateLimitCooldownBypass,
  }) {
    final key = _rateLimitKey(method, endpoint);
    final state = _rateLimits[key];
    if (state == null) return;
    final now = _now();
    if (!now.isBefore(state.retryAt)) {
      _rateLimits.remove(key);
      _emitRateLimitEvent(
        action: 'expired',
        method: method,
        endpoint: endpoint,
        state: state,
        source: 'client_cooldown',
      );
      return;
    }

    if (allowRateLimitCooldownBypass && !state.cooldownBypassConsumed) {
      state.cooldownBypassConsumed = true;
      _emitRateLimitEvent(
        action: 'bypassed',
        method: method,
        endpoint: endpoint,
        state: state,
        source: 'user_initiated',
      );
      return;
    }

    final lastDeferredAt = state.lastDeferredEventAt;
    if (lastDeferredAt == null ||
        now.difference(lastDeferredAt) >= _deferredEventInterval) {
      state.lastDeferredEventAt = now;
      _emitRateLimitEvent(
        action: 'deferred',
        method: method,
        endpoint: endpoint,
        state: state,
        source: 'client_cooldown',
      );
    }
    throw RateLimitedException(retryAt: state.retryAt);
  }

  _EndpointRateLimitState _registerRateLimit(
    String method,
    String endpoint,
    Map<String, String> headers,
  ) {
    final key = _rateLimitKey(method, endpoint);
    final previous = _rateLimits[key];
    final attempt = (previous?.attempt ?? 0) + 1;
    final exponent = (attempt - 1).clamp(0, 10);
    final fallbackMilliseconds =
        _rateLimitFallbackBase.inMilliseconds * (1 << exponent);
    final fallback = Duration(
      milliseconds: fallbackMilliseconds.clamp(
        _rateLimitFallbackBase.inMilliseconds,
        _rateLimitFallbackMax.inMilliseconds,
      ),
    );
    final serverDelay = _retryAfterFromHeaders(headers);
    // Retry-After is authoritative for each new 429 response. The exponential
    // fallback is only used when the server omits a usable value.
    final effectiveDelay = serverDelay ?? fallback;
    final state = _EndpointRateLimitState(
      attempt: attempt,
      retryAt: _now().add(effectiveDelay),
      cooldownBypassConsumed: previous?.cooldownBypassConsumed ?? false,
    );
    _rateLimits[key] = state;
    _emitRateLimitEvent(
      action: 'activated',
      method: method,
      endpoint: endpoint,
      state: state,
      source: serverDelay == null ? 'client_fallback' : 'server_retry_after',
    );
    return state;
  }

  Duration? _retryAfterFromHeaders(Map<String, String> headers) {
    final standard = headers['retry-after']?.trim();
    if (standard != null && standard.isNotEmpty) {
      final seconds = int.tryParse(standard);
      if (seconds != null && seconds >= 0) {
        return Duration(seconds: seconds);
      }
      DateTime? retryAt;
      try {
        retryAt = HttpDate.parse(standard).toUtc();
      } catch (_) {
        retryAt = DateTime.tryParse(standard)?.toUtc();
      }
      if (retryAt != null) {
        final delay = retryAt.difference(_now().toUtc());
        return delay.isNegative ? Duration.zero : delay;
      }
    }

    // Nest Throttler giữ các bucket có hậu tố và trả giá trị theo milliseconds.
    final suffixedDelays = headers.entries
        .where((entry) => entry.key.toLowerCase().startsWith('retry-after-'))
        .map((entry) => int.tryParse(entry.value.trim()))
        .whereType<int>()
        .where((value) => value >= 0)
        .toList();
    if (suffixedDelays.isEmpty) return null;
    return Duration(
      milliseconds: suffixedDelays.reduce((a, b) => a > b ? a : b),
    );
  }

  void _recordRequestSuccess(String method, String endpoint) {
    final state = _rateLimits.remove(_rateLimitKey(method, endpoint));
    if (state == null) return;
    _emitRateLimitEvent(
      action: 'recovered',
      method: method,
      endpoint: endpoint,
      state: state,
      source: 'http_success',
    );
  }

  void _emitRateLimitEvent({
    required String action,
    required String method,
    required String endpoint,
    required _EndpointRateLimitState state,
    required String source,
  }) {
    _rateLimitObserver?.call(
      ApiRateLimitEvent(
        action: action,
        method: method.toUpperCase(),
        endpoint: endpoint.split('?').first,
        attempt: state.attempt,
        retryAt: state.retryAt,
        source: source,
      ),
    );
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
    bool allowRateLimitCooldownBypass = false,
  }) async {
    try {
      _ensureRequestAllowed(
        'GET',
        endpoint,
        allowRateLimitCooldownBypass: allowRateLimitCooldownBypass,
      );
      final requestAuthToken = _authToken;
      final uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');
      final url = queryParameters != null
          ? uri.replace(queryParameters: queryParameters)
          : uri;

      final response = await _client
          .get(
            url,
            headers: requestAuthToken != null
                ? {'Authorization': 'Bearer $requestAuthToken'}
                : null,
          )
          .timeout(ApiConstants.defaultTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _recordRequestSuccess('GET', endpoint);
        return response;
      }
      await _throwForResponse(
        response,
        method: 'GET',
        endpoint: endpoint,
        requestAuthToken: requestAuthToken,
      );
    } on SocketException {
      throw NetworkException();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _unexpectedException(e);
    }
  }

  /// Performs a backward-compatible conditional GET. Unlike [get], a 304 is
  /// returned to the caller so it can reuse its last-known-good snapshot.
  Future<ConditionalGetResponse> getConditional(
    String endpoint, {
    Map<String, String>? queryParameters,
    String? ifNoneMatch,
    bool allowRateLimitCooldownBypass = false,
  }) async {
    try {
      _ensureRequestAllowed(
        'GET',
        endpoint,
        allowRateLimitCooldownBypass: allowRateLimitCooldownBypass,
      );
      final requestAuthToken = _authToken;
      final uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');
      final url = queryParameters != null
          ? uri.replace(queryParameters: queryParameters)
          : uri;
      final response = await _client
          .get(
            url,
            headers: {
              if (requestAuthToken != null)
                'Authorization': 'Bearer $requestAuthToken',
              if (ifNoneMatch != null && ifNoneMatch.trim().isNotEmpty)
                'If-None-Match': ifNoneMatch.trim(),
            },
          )
          .timeout(ApiConstants.defaultTimeout);

      if ((response.statusCode >= 200 && response.statusCode < 300) ||
          response.statusCode == HttpStatus.notModified) {
        _recordRequestSuccess('GET', endpoint);
        return ConditionalGetResponse(
          statusCode: response.statusCode,
          body: response.body,
          headers: response.headers,
        );
      }
      await _throwForResponse(
        response,
        method: 'GET',
        endpoint: endpoint,
        requestAuthToken: requestAuthToken,
      );
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
    bool allowRateLimitCooldownBypass = false,
  }) async {
    try {
      _ensureRequestAllowed(
        'GET',
        endpoint,
        allowRateLimitCooldownBypass: allowRateLimitCooldownBypass,
      );
      final requestAuthToken = _authToken;
      final uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');
      final url = queryParameters != null
          ? uri.replace(queryParameters: queryParameters)
          : uri;
      final response = await _client
          .get(
            url,
            headers: requestAuthToken != null
                ? {'Authorization': 'Bearer $requestAuthToken'}
                : null,
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _recordRequestSuccess('GET', endpoint);
        return response.bodyBytes;
      }
      await _throwForResponse(
        response,
        method: 'GET',
        endpoint: endpoint,
        requestAuthToken: requestAuthToken,
      );
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
    bool allowRateLimitCooldownBypass = false,
  }) async {
    try {
      _ensureRequestAllowed(
        'POST',
        endpoint,
        allowRateLimitCooldownBypass: allowRateLimitCooldownBypass,
      );
      final requestAuthToken = _authToken;
      final url = Uri.parse('${ApiConstants.baseUrl}$endpoint');

      if (kDebugMode) {
        debugPrint('🔵 API POST: $url');
      }

      final response = await _client
          .post(
            url,
            headers: _authHeadersFor(requestAuthToken),
            body: jsonEncode(body),
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (kDebugMode) {
        debugPrint('✅ Response: ${response.statusCode}');
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _recordRequestSuccess('POST', endpoint);
        return response;
      }
      await _throwForResponse(
        response,
        method: 'POST',
        endpoint: endpoint,
        requestAuthToken: requestAuthToken,
      );
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
    bool allowRateLimitCooldownBypass = false,
  }) async {
    try {
      _ensureRequestAllowed(
        'PATCH',
        endpoint,
        allowRateLimitCooldownBypass: allowRateLimitCooldownBypass,
      );
      final requestAuthToken = _authToken;
      final url = Uri.parse('${ApiConstants.baseUrl}$endpoint');
      final response = await _client
          .patch(
            url,
            headers: _authHeadersFor(requestAuthToken),
            body: jsonEncode(body),
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _recordRequestSuccess('PATCH', endpoint);
        return response;
      }
      await _throwForResponse(
        response,
        method: 'PATCH',
        endpoint: endpoint,
        requestAuthToken: requestAuthToken,
      );
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
    bool allowRateLimitCooldownBypass = false,
  }) async {
    try {
      _ensureRequestAllowed(
        'PUT',
        endpoint,
        allowRateLimitCooldownBypass: allowRateLimitCooldownBypass,
      );
      final requestAuthToken = _authToken;
      final url = Uri.parse('${ApiConstants.baseUrl}$endpoint');
      final response = await _client
          .put(
            url,
            headers: _authHeadersFor(requestAuthToken),
            body: jsonEncode(body),
          )
          .timeout(timeout ?? ApiConstants.defaultTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _recordRequestSuccess('PUT', endpoint);
        return response;
      }
      await _throwForResponse(
        response,
        method: 'PUT',
        endpoint: endpoint,
        requestAuthToken: requestAuthToken,
      );
    } on SocketException {
      throw NetworkException();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _unexpectedException(e);
    }
  }

  Future<http.Response> delete(
    String endpoint, {
    Duration? timeout,
    bool allowRateLimitCooldownBypass = false,
  }) async {
    try {
      _ensureRequestAllowed(
        'DELETE',
        endpoint,
        allowRateLimitCooldownBypass: allowRateLimitCooldownBypass,
      );
      final requestAuthToken = _authToken;
      final url = Uri.parse('${ApiConstants.baseUrl}$endpoint');
      final response = await _client
          .delete(url, headers: _authHeadersFor(requestAuthToken))
          .timeout(timeout ?? ApiConstants.defaultTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _recordRequestSuccess('DELETE', endpoint);
        return response;
      }
      await _throwForResponse(
        response,
        method: 'DELETE',
        endpoint: endpoint,
        requestAuthToken: requestAuthToken,
      );
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
    bool allowRateLimitCooldownBypass = false,
  }) async {
    try {
      _ensureRequestAllowed(
        'POST',
        endpoint,
        allowRateLimitCooldownBypass: allowRateLimitCooldownBypass,
      );
      final requestAuthToken = _authToken;
      final url = Uri.parse('${ApiConstants.baseUrl}$endpoint');

      if (kDebugMode) {
        debugPrint('🔵 API POST MULTIPART: $url');
        debugPrint('🔵 Files count: ${files.length}');
      }

      // Create multipart request
      final request = http.MultipartRequest('POST', url);

      // Add JWT auth header
      if (requestAuthToken != null) {
        request.headers['Authorization'] = 'Bearer $requestAuthToken';
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
        _recordRequestSuccess('POST', endpoint);
        return response;
      }
      await _throwForResponse(
        response,
        method: 'POST',
        endpoint: endpoint,
        requestAuthToken: requestAuthToken,
      );
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
