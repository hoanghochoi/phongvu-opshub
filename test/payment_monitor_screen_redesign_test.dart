import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/legacy_widget_finders.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/store_branch.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/payment_speaker.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/repositories/payment_monitor_repository.dart';
import 'package:phongvu_opshub/features/payment_monitor/domain/map_payment_transaction.dart';
import 'package:phongvu_opshub/features/payment_monitor/domain/payment_notification.dart';
import 'package:phongvu_opshub/features/payment_monitor/presentation/providers/payment_monitor_provider.dart';
import 'package:phongvu_opshub/features/payment_monitor/presentation/screens/payment_monitor_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets('renders content-only payment monitor workspace', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = _WidgetPaymentMonitorRepository();
    final provider = PaymentMonitorProvider(
      repository,
      _FakePaymentSpeaker(),
      null,
      const Duration(milliseconds: 1),
      null,
      const Duration(minutes: 5),
    );
    addTearDown(provider.dispose);

    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_paymentUser, isInitialized: true);
      await _waitUntil(() => repository.fetchCount > 0 && !provider.isLoading);
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
            value: _FakeAuthProvider(_paymentUser),
          ),
          ChangeNotifierProvider<PaymentMonitorProvider>.value(value: provider),
        ],
        child: const MaterialApp(home: PaymentMonitorScreen()),
      ),
    );
    await tester.pump();

    final header = find.byKey(const Key('payment-monitor-header'));
    expect(header, findsOneWidget);
    expect(tester.getSize(header).height, lessThan(120));
    expect(find.byType(Scaffold), findsNothing);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.text('Theo dõi tiền vào'), findsOneWidget);
    expect(find.text('Giao dịch tiền vào'), findsOneWidget);
    expect(find.text('Chỉ xem danh sách'), findsOneWidget);
    expect(find.text('1 showroom'), findsOneWidget);
    expect(find.textContaining('1.250.000'), findsWidgets);
    expect(repository.requestedStoreIds.last, 'CP01');
  });
}

const _paymentUser = User(
  id: 'payment-user-1',
  email: 'payment@example.com',
  role: 'USER',
  storeId: 'CP01',
  storeName: 'Showroom 1',
  assignedStores: [
    StoreBranch(id: 'store-1', storeId: 'CP01', storeName: 'Showroom 1'),
  ],
  featureAccess: {'PAYMENT_MONITOR': true, 'PAYMENT_SPEAKER': true},
);

class _FakeAuthProvider extends AuthProvider {
  final User currentUser;

  _FakeAuthProvider(this.currentUser) : super(AuthRepository(ApiClient()));

  @override
  User? get user => currentUser;

  @override
  bool get isInitialized => true;

  @override
  bool get isAuthenticated => true;
}

class _WidgetPaymentMonitorRepository extends PaymentMonitorRepository {
  int fetchCount = 0;
  final List<String?> requestedStoreIds = [];

  _WidgetPaymentMonitorRepository() : super(ApiClient());

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
    fetchCount += 1;
    requestedStoreIds.add(storeIds ?? storeId);
    return StoredPaymentTransactionsPage(
      transactions: [_paymentTransaction],
      page: page,
      limit: limit,
      total: 1,
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
}

class _FakePaymentSpeaker extends PaymentSpeaker {}

final _paymentTransaction = MapPaymentTransaction.fromJson({
  'transactionNumber': 'PM-001',
  'transactionReference': 'MAP-001',
  'amount': 1250000,
  'storeId': 'CP01',
  'status': '00',
  'transactionDescription': 'Customer transfer',
  'paidAt': '2026-07-02T09:00:00.000Z',
  'orders': ['2607020001'],
  'canEditOrders': true,
  'canRequestOrderTransfer': true,
});

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Điều kiện kiểm thử không hoàn tất kịp thời');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
