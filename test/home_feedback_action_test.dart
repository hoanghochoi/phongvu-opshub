import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/navigation/app_shell.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phongvu_opshub/app/widgets/app_feature_grid.dart';
import 'package:phongvu_opshub/app/widgets/app_state_widgets.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/store_branch.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/home/presentation/screens/home_screen.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/payment_speaker.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/repositories/payment_monitor_repository.dart';
import 'package:phongvu_opshub/features/payment_monitor/domain/payment_delivery_metrics.dart';
import 'package:phongvu_opshub/features/payment_monitor/domain/payment_notification.dart';
import 'package:phongvu_opshub/features/payment_monitor/presentation/providers/payment_delivery_metrics_provider.dart';
import 'package:phongvu_opshub/features/payment_monitor/presentation/providers/payment_monitor_provider.dart';
import 'package:phongvu_opshub/features/payment_monitor/presentation/widgets/payment_delivery_metrics_chip.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets('Góp ý is always the last visible Home action', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PhongVu OpsHub',
      packageName: 'com.example.phongvu_opshub',
      version: '1.1.1',
      buildNumber: '2',
      buildSignature: '',
    );
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'user-1',
        email: 'staff@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-store-cp01',
        featureAccess: {
          'FIFO': true,
          'WARRANTY': true,
          'VIETQR': true,
          'BANK_STATEMENTS': true,
          'FEEDBACK': true,
        },
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const MaterialApp(
          home: AppShell(location: '/home', child: HomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final titles = tester
        .widgetList<AppFeatureTile>(find.byType(AppFeatureTile))
        .map((tile) => tile.action.title)
        .toList(growable: false);

    expect(
      titles,
      containsAll(<String>['FIFO', 'BH / SC', 'VietQR', 'Sao kê']),
    );
    expect(titles.last, 'Góp ý');
    expect(titles.where((title) => title == 'Góp ý'), hasLength(1));
  });

  testWidgets('Home shows Báo cáo for admin sales report node feature', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PhongVu OpsHub',
      packageName: 'com.example.phongvu_opshub',
      version: '1.1.1',
      buildNumber: '2',
      buildSignature: '',
    );
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'lead-1',
        email: 'lead@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-area-hcm',
        featureAccess: {'ADMIN_SALES_REPORTS': true},
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const MaterialApp(
          home: AppShell(location: '/home', child: HomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final titles = tester
        .widgetList<AppFeatureTile>(find.byType(AppFeatureTile))
        .map((tile) => tile.action.title)
        .toList(growable: false);

    expect(titles, contains('Báo cáo'));
    expect(titles, isNot(contains('Quản trị')));
  });

  testWidgets('Home uses shared empty state when no workspace is available', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PhongVu OpsHub',
      packageName: 'com.example.phongvu_opshub',
      version: '1.1.1',
      buildNumber: '2',
      buildSignature: '',
    );
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'staff-empty',
        email: 'staff.empty@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-store-cp01',
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const MaterialApp(
          home: AppShell(location: '/home', child: HomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-empty-state')), findsOneWidget);
    expect(find.byType(AppStatePanel), findsOneWidget);
    expect(find.byType(AppFeatureTile), findsNothing);
    expect(find.text('Trang chủ vận hành'), findsOneWidget);
    expect(find.text('Chưa có chức năng khả dụng'), findsOneWidget);
    expect(
      find.text('Vui lòng liên hệ quản lý để kiểm tra phân quyền truy cập.'),
      findsOneWidget,
    );
  });

  testWidgets('Home header shows all assigned SR codes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PhongVu OpsHub',
      packageName: 'com.example.phongvu_opshub',
      version: '1.1.1',
      buildNumber: '2',
      buildSignature: '',
    );
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'user-1',
        email: 'staff@phongvu.vn',
        name: 'Staging',
        role: 'USER',
        organizationNodeId: 'org-store-cp75',
        assignedStores: [
          StoreBranch(id: 'store-75', storeId: 'CP75', storeName: 'CP75'),
          StoreBranch(id: 'store-62', storeId: 'CP62', storeName: 'CP62'),
        ],
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 SR: CP75, CP62'), findsOneWidget);
  });

  testWidgets('Windows Home shows speaker paused for multiple assigned SRs', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PhongVu OpsHub',
      packageName: 'com.example.phongvu_opshub',
      version: '1.1.1',
      buildNumber: '2',
      buildSignature: '',
    );
    const user = User(
      id: 'user-1',
      email: 'staff@phongvu.vn',
      name: 'Staging',
      role: 'USER',
      organizationNodeId: 'org-store-cp75',
      assignedStores: [
        StoreBranch(id: 'store-75', storeId: 'CP75', storeName: 'CP75'),
        StoreBranch(id: 'store-62', storeId: 'CP62', storeName: 'CP62'),
      ],
      featureAccess: {'PAYMENT_MONITOR': true, 'PAYMENT_SPEAKER': true},
    );
    final authProvider = _FakeAuthProvider(user);
    final paymentProvider = _FakeHomePaymentMonitorProvider(
      isActive: true,
      isSpeakerEnabled: true,
      canUsePaymentSpeaker: false,
      speakerSelectionNotice:
          'Loa chỉ đọc khi chọn đúng 1 SR. Bạn đang xem 2 SR nên danh sách vẫn cập nhật, còn loa tạm dừng.',
    );
    addTearDown(paymentProvider.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<PaymentMonitorProvider>.value(
            value: paymentProvider,
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Đọc loa tiền vào'), findsOneWidget);
    expect(
      find.textContaining('Loa chỉ đọc khi chọn đúng 1 SR'),
      findsOneWidget,
    );

    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.value, isFalse);
    expect(toggle.onChanged, isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android Home shows Tiền vào but hides speaker quick toggle', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PhongVu OpsHub',
      packageName: 'com.example.phongvu_opshub',
      version: '1.1.1',
      buildNumber: '2',
      buildSignature: '',
    );
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'user-1',
        email: 'staff@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-store-cp01',
        featureAccess: {'PAYMENT_MONITOR': true, 'PAYMENT_SPEAKER': true},
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final titles = tester
        .widgetList<AppFeatureTile>(find.byType(AppFeatureTile))
        .map((tile) => tile.action.title)
        .toList(growable: false);

    expect(titles, contains('Tiền vào'));
    expect(find.text('Đọc loa tiền vào'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Super Admin Home shows speaker delivery history pill', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PhongVu OpsHub',
      packageName: 'com.example.phongvu_opshub',
      version: '1.1.1',
      buildNumber: '2',
      buildSignature: '',
    );
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'super-1',
        email: 'super@phongvu.vn',
        name: 'Super Admin',
        role: 'SUPER_ADMIN',
      ),
    );
    final metricsRepository = _FakePaymentMonitorRepository(
      deliveryMetrics: _deliveryMetrics(),
      deliveryHistory: _deliveryHistory(),
    );
    final metricsProvider = PaymentDeliveryMetricsProvider(
      metricsRepository,
      refreshInterval: Duration.zero,
    );
    addTearDown(metricsProvider.dispose);
    await metricsProvider.syncAuth(authProvider.user, isInitialized: true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<PaymentDeliveryMetricsProvider>.value(
            value: metricsProvider,
          ),
        ],
        child: const MaterialApp(
          home: AppShell(location: '/home', child: HomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final metricsChip = find.byType(PaymentDeliveryMetricsChip);
    expect(metricsChip, findsOneWidget);

    await tester.tap(metricsChip);
    await tester.pumpAndSettle();

    expect(metricsRepository.deliveryHistoryFetchCount, 1);
    expect(find.text('Lịch sử đọc loa'), findsOneWidget);
    expect(find.text('SR CP01'), findsOneWidget);
  });

  testWidgets('Home support icon opens QR and group link dialog', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PhongVu OpsHub',
      packageName: 'com.example.phongvu_opshub',
      version: '1.1.1',
      buildNumber: '2',
      buildSignature: '',
    );
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'user-1',
        email: 'staff@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-store-cp01',
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const MaterialApp(
          home: AppShell(location: '/home', child: HomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Hỗ trợ'));
    await tester.pumpAndSettle();

    expect(find.text('Hỗ trợ OpsHub'), findsOneWidget);
    expect(find.textContaining('link.seatalk.io/group/open'), findsNothing);
    expect(find.text('Sao chép liên kết'), findsOneWidget);
    expect(find.text('Mở group'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'data/group_invitation.jpg',
      ),
      findsOneWidget,
    );
  });
}

class _FakeAuthProvider extends AuthProvider {
  final User currentUser;

  _FakeAuthProvider(this.currentUser) : super(AuthRepository(ApiClient()));

  @override
  User? get user => currentUser;
}

PaymentDeliveryMetrics _deliveryMetrics() {
  return PaymentDeliveryMetrics.fromJson({
    'sampledAt': '2026-06-27T02:00:00.000Z',
    'windowHours': 24,
    'current': {
      'count': 3,
      'averageMs': 7242,
      'from': '2026-06-26T02:00:00.000Z',
      'to': '2026-06-27T02:00:00.000Z',
    },
    'previous': {
      'count': 2,
      'averageMs': 8342,
      'from': '2026-06-25T02:00:00.000Z',
      'to': '2026-06-26T02:00:00.000Z',
    },
    'deltaMs': -1100,
    'deltaPercent': -13.2,
    'trend': 'down',
  });
}

PaymentDeliveryHistory _deliveryHistory() {
  return PaymentDeliveryHistory.fromJson({
    'sampledAt': '2026-06-27T02:00:00.000Z',
    'limit': 20,
    'list': [
      {
        'deliveryLogId': 'log-1',
        'notificationId': 'note-1',
        'transactionId': 'txn-1',
        'storeCode': 'CP01',
        'amount': 1250000,
        'paidAt': '2026-06-27T08:00:00.000',
        'firstSeenAt': '2026-06-27T08:00:02.003',
        'streamStartedAt': '2026-06-27T08:00:07.242',
        'playedAt': '2026-06-27T08:00:09.245',
        'status': 'PLAYED',
        'bankToStreamStartLatencyMs': 7242,
        'firstSeenToStreamStartLatencyMs': 5239,
        'playDurationMs': 2003,
        'firstSeenToPlayedMs': 7242,
      },
    ],
  });
}

class _FakePaymentMonitorRepository extends PaymentMonitorRepository {
  final PaymentDeliveryMetrics? deliveryMetrics;
  final PaymentDeliveryHistory? deliveryHistory;
  int deliveryMetricsFetchCount = 0;
  int deliveryHistoryFetchCount = 0;

  _FakePaymentMonitorRepository({this.deliveryMetrics, this.deliveryHistory})
    : super(ApiClient());

  @override
  Future<StoredPaymentTransactionsPage> fetchStoredTransactions({
    String? storeId,
    String? storeIds,
    bool allStores = false,
    String? date,
    String? startDate,
    String? endDate,
    int page = 0,
    int limit = 10,
    bool includeTotal = true,
  }) async {
    return StoredPaymentTransactionsPage(
      transactions: const [],
      page: page,
      limit: limit,
      total: 0,
      canReviewOrderTransfers: false,
    );
  }

  @override
  Future<List<PaymentNotification>> fetchReadyNotifications({
    required String clientId,
    String? storeId,
    DateTime? afterCreatedAt,
    int limit = 10,
  }) async {
    return const [];
  }

  @override
  Future<PaymentDeliveryMetrics> fetchDeliveryMetrics({
    int windowHours = 24,
  }) async {
    deliveryMetricsFetchCount += 1;
    return deliveryMetrics ?? _deliveryMetrics();
  }

  @override
  Future<PaymentDeliveryHistory> fetchDeliveryHistory({int limit = 20}) async {
    deliveryHistoryFetchCount += 1;
    return deliveryHistory ?? _deliveryHistory();
  }
}

class _FakeHomePaymentMonitorProvider extends PaymentMonitorProvider {
  final bool _isActive;
  final bool _isSpeakerEnabled;
  final bool _canUsePaymentSpeaker;
  final String? _speakerSelectionNotice;

  _FakeHomePaymentMonitorProvider({
    required bool isActive,
    required bool isSpeakerEnabled,
    required bool canUsePaymentSpeaker,
    required String? speakerSelectionNotice,
  }) : _isActive = isActive,
       _isSpeakerEnabled = isSpeakerEnabled,
       _canUsePaymentSpeaker = canUsePaymentSpeaker,
       _speakerSelectionNotice = speakerSelectionNotice,
       super(_FakePaymentMonitorRepository(), _FakePaymentSpeaker());

  @override
  bool get isActive => _isActive;

  @override
  bool get isSpeakerEnabled => _isSpeakerEnabled;

  @override
  bool get canUsePaymentSpeaker => _canUsePaymentSpeaker;

  @override
  String? get speakerSelectionNotice => _speakerSelectionNotice;
}

class _FakePaymentSpeaker extends PaymentSpeaker {
  @override
  Future<PaymentSpeakerResult> playServerAudio({
    required int amount,
    required List<int>? audioBytes,
    required String notificationId,
    required String transactionId,
    required String storeCode,
    required String clientId,
    required int attempt,
    bool playLocalCue = true,
    bool playLocalCuePrefix = false,
    Future<void> Function()? onPlaybackStarting,
  }) async {
    if (onPlaybackStarting != null) {
      await onPlaybackStarting();
    }
    return const PaymentSpeakerResult(
      backend: 'fake',
      extension: 'wav',
      durationMs: 0,
      reportedSuccess: true,
      audibleVerified: false,
    );
  }
}
