class ApiConstants {
  ApiConstants._();

  static const String baseUrl = 'https://n8n.hoanghochoi.com';

  // Auth endpoints
  static const String checkEmailEndpoint = '/webhook/pva-check-email';
  static const String registerEndpoint = '/webhook/pva-reg';
  static const String loginEndpoint = '/webhook/pva-login';
  static const String getUserEndpoint = '/webhook/pva-get-user';

  // Chat endpoint
  static const String chatWebhookEndpoint = '/webhook/pva-chat';

  // Sort endpoint
  static const String sortWebhookEndpoint = '/webhook/pva-sort';

  // Feedback endpoint
  static const String feedbackEndpoint = '/webhook/pva-feedback';

  // Warranty endpoints
  static const String saveWarrantyEndpoint = '/webhook/bhsc-save';
  static const String showAllWarrantyEndpoint = '/webhook/bhsc-show-all';
  static const String searchWarrantyEndpoint = '/webhook/bhsc-search';
  static const String getWarrantyEndpoint = '/webhook/bhsc-get';

  // Timeouts
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(seconds: 60);
}
