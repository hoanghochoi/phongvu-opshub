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

  static Uri get publicBaseUri {
    final base = Uri.parse(baseUrl);
    return base.replace(path: '', queryParameters: null, fragment: null);
  }

  static Uri get helpPageUri => publicBaseUri.replace(path: '/help');

  static const String appVersionEndpoint = '/app-version';

  // Auth endpoints
  static const String loginEndpoint = '/auth/login';
  static const String registerEndpoint = '/auth/register';
  static const String verificationCodeEndpoint = '/auth/verification-code';
  static const String forgotPasswordEndpoint = '/auth/forgot-password';
  static const String forgotPasswordVerifyCodeEndpoint =
      '/auth/forgot-password/verify-code';
  static const String resetPasswordEndpoint = '/auth/reset-password';
  static const String changePasswordEndpoint = '/auth/change-password';
  static const String logoutEndpoint = '/auth/logout';
  static const String getUserEndpoint = '/auth/get-user';
  static const String storesEndpoint = '/stores';
  static const String profileEndpoint = '/users/me';
  static const String avatarEndpoint = '/users/me/avatar';
  static const String adminUsersEndpoint = '/admin/users';
  static const String adminUsersImportEndpoint = '/admin/users/import';
  static const String adminUserScopeTreeEndpoint = '/admin/users/scope-tree';
  static String adminUserEndpoint(String id) => '/admin/users/$id';
  static String adminUserResetPasswordEndpoint(String id) =>
      '/admin/users/$id/reset-password';
  static const String adminRolesEndpoint = '/admin/roles';
  static const String adminDepartmentsEndpoint = '/admin/departments';
  static const String adminJobRolesEndpoint = '/admin/job-roles';
  static const String adminOrgTreeEndpoint = '/admin/org-tree';
  static const String adminOrgTreeNodesEndpoint = '/admin/org-tree/nodes';
  static const String featuresMeEndpoint = '/features/me';
  static const String adminFeaturesEndpoint = '/admin/features';
  static const String adminFeaturesTreeEndpoint = '/admin/features/tree';
  static const String adminFeatureNodeAssignmentsEndpoint =
      '/admin/features/node-assignments';
  static const String adminFeatureNodeAssignmentsBatchEndpoint =
      '/admin/features/node-assignments/batch';
  static const String adminFeatureRulesEndpoint = '/admin/features/rules';
  static const String adminFeatureRulesBatchEndpoint =
      '/admin/features/rules/batch';
  static const String policiesMeEndpoint = '/policies/me';
  static const String adminPoliciesEndpoint = '/admin/policies';
  static const String adminPolicyRulesEndpoint = '/admin/policies/rules';
  static const String adminPolicyRulesBatchEndpoint =
      '/admin/policies/rules/batch';
  static const String adminPolicyScopeTreeEndpoint =
      '/admin/policies/scope-tree';
  static const String adminSettingsEndpoint = '/admin/settings';
  static const String adminMapVietinTransactionsEndpoint =
      '/admin/map-vietin/transactions/search';
  static const String adminMapVietinStoredTransactionsEndpoint =
      '/admin/map-vietin/transactions';
  static const String adminMapVietinStatementsEndpoint =
      '/admin/map-vietin/statements';
  static const String adminMapVietinStatementsExportEndpoint =
      '/admin/map-vietin/statements/export';
  static String adminMapVietinStatementOrdersEndpoint(String id) =>
      '/admin/map-vietin/statements/$id/orders';
  static String adminMapVietinStatementOrderTransferRequestsEndpoint(
    String id,
  ) => '/admin/map-vietin/statements/$id/order-transfer-requests';
  static const String adminMapVietinStatementOrderTransferRequestsListEndpoint =
      '/admin/map-vietin/statement-order-transfer-requests';
  static String adminMapVietinStatementOrderTransferApproveEndpoint(
    String id,
  ) => '/admin/map-vietin/statement-order-transfer-requests/$id/approve';
  static String adminMapVietinStatementOrderTransferRejectEndpoint(String id) =>
      '/admin/map-vietin/statement-order-transfer-requests/$id/reject';
  static String adminMapVietinStatementOrderHistoryEndpoint(String id) =>
      '/admin/map-vietin/statements/$id/order-history';
  static const String offsetAdjustmentsEndpoint = '/offset-adjustments';
  static const String offsetAdjustmentsExportEndpoint =
      '/offset-adjustments/export';
  static String offsetAdjustmentEndpoint(String id) =>
      '/offset-adjustments/$id';
  static String offsetAdjustmentResubmitEndpoint(String id) =>
      '/offset-adjustments/$id/resubmit';
  static String offsetAdjustmentCompleteEndpoint(String id) =>
      '/offset-adjustments/$id/complete';
  static String offsetAdjustmentRejectEndpoint(String id) =>
      '/offset-adjustments/$id/reject';
  static String paymentNotificationAudioEndpoint(String id) =>
      '/payment-notifications/$id/audio';
  static String paymentNotificationAckEndpoint(String id) =>
      '/payment-notifications/$id/ack';
  static const String paymentNotificationDeliveryMetricsEndpoint =
      '/payment-notifications/delivery-metrics';
  static const String paymentNotificationsReadyEndpoint =
      '/payment-notifications/ready';
  static const String notificationsReadEndpoint = '/notifications/read';
  static const String appLogsEndpoint = '/app-logs';
  static String realtimeWsUrl({String? storeId, String? accessToken}) {
    final base = Uri.parse(baseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final query = {
      if (storeId != null && storeId.trim().isNotEmpty)
        'store_id': storeId.trim().toUpperCase(),
      if (accessToken != null && accessToken.trim().isNotEmpty)
        'access_token': accessToken.trim(),
    };
    return base
        .replace(
          scheme: scheme,
          path: '/ws',
          queryParameters: query.isEmpty ? null : query,
        )
        .toString();
  }

  static String get appUpdateRealtimeWsUrl {
    final base = Uri.parse(baseUrl);
    return base
        .replace(
          scheme: base.scheme == 'https' ? 'wss' : 'ws',
          path: '/ws/app-updates',
          queryParameters: null,
        )
        .toString();
  }

  // FIFO endpoints
  static const String fifoCheckEndpoint = '/fifo/check';
  static const String fifoExportEndpoint = '/fifo/export';
  static const String fifoInventoryImportEndpoint = '/fifo/inventory/import';
  static const String legacyFifoCheckEndpoint = '/sort/fifo-check';

  // Sort endpoint
  static const String sortEndpoint = '/sort';
  static const String sortCompletionReportEndpoint = '/sort/completion-report';

  // Feedback endpoint
  static const String feedbackEndpoint = '/feedback';
  static const String adminFeedbackEndpoint = '/feedback/admin';

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
