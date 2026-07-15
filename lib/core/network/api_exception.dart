class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

class NetworkException extends ApiException {
  NetworkException([
    super.message = 'Không có kết nối. Kiểm tra mạng của bạn.',
  ]);
}

class TimeoutException extends ApiException {
  TimeoutException([super.message = 'Yêu cầu quá lâu. Vui lòng thử lại.']);
}

class ServerException extends ApiException {
  ServerException([
    super.message = 'Hệ thống đang bận. Vui lòng thử lại sau ít phút.',
    super.statusCode,
  ]);
}

class RateLimitedException extends ApiException {
  final DateTime retryAt;

  RateLimitedException({
    required this.retryAt,
    String message =
        'Hệ thống đang giới hạn tần suất. Vui lòng chờ một chút rồi thử lại.',
  }) : super(message, 429);

  Duration retryAfter(DateTime now) {
    final remaining = retryAt.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

class ParseException extends ApiException {
  ParseException([
    super.message = 'Chưa xử lý được dữ liệu. Vui lòng thử lại.',
  ]);
}
