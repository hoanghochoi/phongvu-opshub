import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/navigation/app_shell.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phongvu_opshub/app/widgets/app_feature_grid.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/store_branch.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/home/data/repositories/home_summary_repository.dart';
import 'package:phongvu_opshub/features/home/domain/home_summary.dart';
import 'package:phongvu_opshub/features/home/presentation/providers/home_summary_provider.dart';
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

  testWidgets('Home landing keeps welcome strip and hides workspace grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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

    final welcomeStrip = find.byKey(const Key('home-welcome-strip'));
    expect(welcomeStrip, findsOneWidget);
    expect(tester.getSize(welcomeStrip).height, lessThan(90));
    expect(find.text('Trang chủ vận hành'), findsOneWidget);
    expect(find.text('2 showroom: CP75, CP62'), findsOneWidget);
    expect(find.byType(AppFeatureTile), findsNothing);
    expect(find.text('Không gian làm việc'), findsNothing);
  });

  testWidgets(
    'Windows Home shows compact speaker status and toggles from header',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
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
        canUsePaymentSpeaker: true,
        speakerSelectionNotice: null,
      );
      final summaryProvider = HomeSummaryProvider(
        _FakeHomeSummaryRepository(summary: _homeSummary()),
      );
      addTearDown(paymentProvider.dispose);
      addTearDown(summaryProvider.dispose);
      summaryProvider.syncAuth(user, isInitialized: true);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<PaymentMonitorProvider>.value(
              value: paymentProvider,
            ),
            ChangeNotifierProvider<HomeSummaryProvider>.value(
              value: summaryProvider,
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Loa đang bật'), findsOneWidget);
      expect(find.text('Đọc loa tiền vào'), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.byKey(const Key('payment-speaker-warning')), findsNothing);

      await tester.tap(find.byKey(const Key('home-speaker-status-toggle')));
      await tester.pumpAndSettle();

      expect(paymentProvider.speakerToggleCalls, 1);
      expect(paymentProvider.lastSpeakerValue, isFalse);
      expect(find.text('Loa đang tắt'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('Android Home keeps speaker quick toggle hidden', (tester) async {
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

    expect(find.byKey(const Key('home-welcome-strip')), findsOneWidget);
    expect(find.text('Đọc loa tiền vào'), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byType(AppFeatureTile), findsNothing);
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
    expect(find.text('Showroom CP01'), findsOneWidget);
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

class _FakeHomeSummaryRepository extends HomeSummaryRepository {
  final HomeSummary summary;

  _FakeHomeSummaryRepository({required this.summary}) : super(ApiClient());

  @override
  Future<HomeSummary> fetchSummary({
    String? date,
    String? startDate,
    String? endDate,
    String? scope,
    String? organizationNodeId,
  }) async {
    return summary;
  }

  @override
  Future<List<HomeSummaryScopeOptionDto>> fetchScopeOptions() async {
    return const [];
  }
}

HomeSummary _homeSummary() {
  return HomeSummary(
    date: '2026-07-04',
    available: true,
    scope: 'OWN',
    scopeLabel: 'Phạm vi cá nhân',
    scopeDetail: 'CP75',
    coverageLabel: 'Tỉ lệ báo cáo',
    totalRevenue: 1000000,
    totalOrders: 1,
    totalReports: 1,
    reportedOrders: 1,
    unreportedOrders: 0,
    coverageRate: 100,
    refreshedAt: DateTime.parse('2026-07-04T03:15:00.000Z'),
  );
}

class _FakeHomePaymentMonitorProvider extends PaymentMonitorProvider {
  final bool _isActive;
  bool _isSpeakerEnabled;
  final bool _canUsePaymentSpeaker;
  final String? _speakerSelectionNotice;
  int speakerToggleCalls = 0;
  bool? lastSpeakerValue;

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

  @override
  Future<void> setSpeakerEnabled(bool value) async {
    speakerToggleCalls += 1;
    lastSpeakerValue = value;
    _isSpeakerEnabled = value;
    notifyListeners();
  }
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
