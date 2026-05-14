class ApiConstants {
  ApiConstants._();

  // ──────────────────────────────────────────────────────────
  // Base URL — override at build/run time with:
  // flutter run --dart-define=API_BASE_URL=http://localhost:3000
  // ──────────────────────────────────────────────────────────
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.8.100:3000',
  );

  // Auth endpoints
  static const String googleLoginEndpoint = '/auth/google-login';
  static const String getUserEndpoint = '/auth/get-user';
  static const String storesEndpoint = '/stores';
  static const String profileEndpoint = '/users/me';
  static const String selectStoreEndpoint = '/users/me/select-store';
  static const String avatarEndpoint = '/users/me/avatar';
  static const String adminUsersEndpoint = '/admin/users';

  // FIFO endpoints
  static const String fifoCheckEndpoint = '/sort/fifo-check';

  // Sort endpoint
  static const String sortEndpoint = '/sort';
  static const String sortCompletionReportEndpoint = '/sort/completion-report';

  // Feedback endpoint
  static const String feedbackEndpoint = '/feedback';

  // VietQR endpoint
  static const String vietQrEndpoint = '/vietqr';

  // FIFO Log endpoints
  static const String fifoLogMyEndpoint = '/fifo-logs/my';
  static const String fifoLogAdminEndpoint = '/fifo-logs/admin';

  // Warranty endpoints
  static const String saveWarrantyEndpoint = '/upload/warranty'; // multipart
  static const String showAllWarrantyEndpoint = '/warranties';
  static const String searchWarrantyEndpoint = '/warranties/search';
  static const String getWarrantyEndpoint = '/warranties/detail';

  // Timeouts
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(seconds: 60);
}
