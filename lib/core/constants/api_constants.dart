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

  // Chat/FIFO check endpoint
  static const String chatWebhookEndpoint = '/sort/fifo-check';

  // Sort endpoint (mirrors n8n pva-sort)
  static const String sortWebhookEndpoint = '/sort';
  static const String sortCompletionReportEndpoint = '/sort/completion-report';

  // Feedback endpoint
  static const String feedbackEndpoint = '/feedback';

  // FIFO Log endpoints
  static const String fifoLogMyEndpoint = '/fifo-logs/my';
  static const String fifoLogAdminEndpoint = '/fifo-logs/admin';

  // Warranty endpoints (mirrors n8n bhsc-*)
  static const String saveWarrantyEndpoint = '/upload/warranty'; // multipart
  static const String showAllWarrantyEndpoint = '/warranties';
  static const String searchWarrantyEndpoint = '/warranties/search';
  static const String getWarrantyEndpoint = '/warranties/detail';

  // Timeouts
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(seconds: 60);
}
