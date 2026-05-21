class ApiConstants {
  ApiConstants._();

  // ──────────────────────────────────────────────────────────
  // Base URL — override at build/run time with:
  // flutter run --dart-define=API_BASE_URL=http://localhost:3000
  // ──────────────────────────────────────────────────────────
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://opshub.hoanghochoi.com/api',
  );

  static const String appVersionEndpoint = '/app-version';

  // Auth endpoints
  static const String loginEndpoint = '/auth/login';
  static const String registerEndpoint = '/auth/register';
  static const String verificationCodeEndpoint = '/auth/verification-code';
  static const String getUserEndpoint = '/auth/get-user';
  static const String storesEndpoint = '/stores';
  static const String profileEndpoint = '/users/me';
  static const String selectStoreEndpoint = '/users/me/select-store';
  static const String avatarEndpoint = '/users/me/avatar';
  static const String adminUsersEndpoint = '/admin/users';
  static const String adminRolesEndpoint = '/admin/roles';
  static const String adminStoresEndpoint = '/admin/stores';
  static const String adminMapVietinTransactionsEndpoint =
      '/admin/map-vietin/transactions/search';
  static const String adminMapVietinStoredTransactionsEndpoint =
      '/admin/map-vietin/transactions';

  // FIFO endpoints
  static const String fifoCheckEndpoint = '/sort/fifo-check';

  // Sort endpoint
  static const String sortEndpoint = '/sort';
  static const String sortCompletionReportEndpoint = '/sort/completion-report';

  // Feedback endpoint
  static const String feedbackEndpoint = '/feedback';

  // VietQR endpoint
  static const String vietQrEndpoint = '/vietqr';
  static String vietQrConfirmEndpoint(String id) =>
      '$vietQrEndpoint/$id/confirm';

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
