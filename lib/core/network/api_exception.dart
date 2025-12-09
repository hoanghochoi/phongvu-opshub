class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

class NetworkException extends ApiException {
  NetworkException([super.message = 'Không có kết nối. Kiểm tra mạng của bạn.']);
}

class TimeoutException extends ApiException {
  TimeoutException([super.message = 'Yêu cầu quá lâu. Vui lòng thử lại.']);
}

class ServerException extends ApiException {
  ServerException([super.message = 'Lỗi server. Vui lòng thử lại sau.', super.statusCode]);
}

class ParseException extends ApiException {
  ParseException([super.message = 'Lỗi xử lý dữ liệu.']);
}
