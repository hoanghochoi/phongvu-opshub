import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phongvu_opshub/app/navigation/app_shell.dart';
import 'helpers/legacy_widget_finders.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/store_branch.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/bank_statement/data/bank_statement_repository.dart';
import 'package:phongvu_opshub/features/bank_statement/domain/bank_statement_transaction.dart';
import 'package:phongvu_opshub/features/bank_statement/presentation/providers/bank_statement_provider.dart';
import 'package:phongvu_opshub/features/bank_statement/presentation/screens/bank_statement_screen.dart';
import 'package:phongvu_opshub/features/notifications/data/app_notification_read_store.dart';
import 'package:phongvu_opshub/features/notifications/presentation/providers/app_notifications_provider.dart';
import 'package:phongvu_opshub/features/offset_adjustment/data/offset_adjustment_repository.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PhongVu OpsHub',
      packageName: 'com.example.phongvu_opshub',
      version: '1.1.1',
      buildNumber: '2',
      buildSignature: '',
    );
  });

  testWidgets('renders content-only statement workspace', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = _WidgetBankStatementRepository();
    final provider = BankStatementProvider(
      repository,
      notificationReadStore: _FakeNotificationReadStore(),
    );
    final appNotificationsProvider = AppNotificationsProvider(
      repository,
      offsetAdjustmentRepository: _FakeOffsetAdjustmentRepository(),
      notificationReadStore: _FakeNotificationReadStore(),
    );
    await provider.initialize(_accUser);
    provider.setOrder('26062512345678');
    await provider.search();
    await appNotificationsProvider.syncAuth(_accUser, isInitialized: true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
            value: _FakeAuthProvider(_accUser),
          ),
          ChangeNotifierProvider<BankStatementProvider>.value(value: provider),
          ChangeNotifierProvider<AppNotificationsProvider>.value(
            value: appNotificationsProvider,
          ),
        ],
        child: const MaterialApp(home: BankStatementScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bank-statement-header')), findsOneWidget);
    expect(find.byKey(const Key('bank-statement-toolbar')), findsOneWidget);
    expect(find.byType(Scaffold), findsNothing);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.text('Sao kê'), findsOneWidget);
    expect(find.textContaining('Tra cứu giao dịch VietinBank'), findsOneWidget);
    expect(find.text('Chờ Kế toán xác nhận'), findsOneWidget);
    expect(find.text('Đã cấn trừ'), findsOneWidget);
    expect(find.byTooltip('Giao dịch đang chờ Kế toán xác nhận'), findsWidgets);

    expect(provider.pendingOrderTransferTotal, 1);
    expect(appNotificationsProvider.totalCount, 1);

    appNotificationsProvider.dispose();
  });

  testWidgets('shows accounting bell through AppShell', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = _WidgetBankStatementRepository();
    final provider = BankStatementProvider(
      repository,
      notificationReadStore: _FakeNotificationReadStore(),
    );
    final appNotificationsProvider = AppNotificationsProvider(
      repository,
      offsetAdjustmentRepository: _FakeOffsetAdjustmentRepository(),
      notificationReadStore: _FakeNotificationReadStore(),
    );
    await provider.initialize(_accUser);
    provider.setOrder('26062512345678');
    await provider.search();
    await appNotificationsProvider.syncAuth(_accUser, isInitialized: true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
            value: _FakeAuthProvider(_accUser),
          ),
          ChangeNotifierProvider<BankStatementProvider>.value(value: provider),
          ChangeNotifierProvider<AppNotificationsProvider>.value(
            value: appNotificationsProvider,
          ),
        ],
        child: const MaterialApp(
          home: AppShell(
            location: '/bank-statement',
            child: BankStatementScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('1 thông báo mới'), findsOneWidget);

    await tester.tap(find.byTooltip('1 thông báo mới'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byTooltip('Thông báo'), findsOneWidget);
    expect(find.byTooltip('1 thông báo mới'), findsNothing);
    expect(find.text('Thông báo'), findsOneWidget);
    expect(find.text('Yêu cầu phê duyệt đổi mã đơn'), findsOneWidget);
    expect(find.text('Người gửi: staff@example.com'), findsOneWidget);

    appNotificationsProvider.dispose();
  });

  testWidgets('shows statement number in order history dialog title', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = _WidgetBankStatementRepository();
    final provider = BankStatementProvider(
      repository,
      notificationReadStore: _FakeNotificationReadStore(),
    );
    await provider.initialize(_accUser);
    provider.setOrder('26062512345678');
    await provider.search();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
            value: _FakeAuthProvider(_accUser),
          ),
          ChangeNotifierProvider<BankStatementProvider>.value(value: provider),
        ],
        child: const MaterialApp(home: BankStatementScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Lịch sử chỉnh sửa').first);
    await tester.pumpAndSettle();

    expect(find.text('Lịch sử sao kê 00020300000000004567'), findsOneWidget);
    expect(find.text('Chưa có chỉnh sửa thủ công.'), findsOneWidget);
  });
}

class _FakeNotificationReadStore extends AppNotificationReadStore {
  final Map<String, Set<String>> _seenIdsByKey = {};

  @override
  Future<Set<String>> loadSeenIds({
    required String userKey,
    required String source,
  }) async {
    return Set<String>.of(_seenIdsByKey[_key(userKey, source)] ?? const {});
  }

  @override
  Future<void> saveSeenIds({
    required String userKey,
    required String source,
    required Set<String> ids,
  }) async {
    _seenIdsByKey[_key(userKey, source)] = Set<String>.of(ids);
  }

  @override
  Future<void> markRead({
    required String source,
    required Set<String> ids,
  }) async {}

  String _key(String userKey, String source) => '$userKey::$source';
}

const _accUser = User(
  id: 'acc-1',
  email: 'acc@example.com',
  role: 'USER',
  storeId: 'CP01',
  workScopeType: 'STORE',
  departmentCode: 'ACC',
  featureAccess: {'BANK_STATEMENTS': true},
);

class _FakeAuthProvider extends AuthProvider {
  final User currentUser;

  _FakeAuthProvider(this.currentUser) : super(AuthRepository(ApiClient()));

  @override
  User? get user => currentUser;
}

class _WidgetBankStatementRepository extends BankStatementRepository {
  _WidgetBankStatementRepository() : super(ApiClient());

  @override
  Future<List<StoreBranch>> fetchStores() async {
    return const [
      StoreBranch(id: 'store-1', storeId: 'CP01', storeName: 'Showroom 1'),
    ];
  }

  @override
  Future<BankStatementPage> fetchStatements(BankStatementQuery query) async {
    final rows = [_pendingTransaction, _offsetTransaction];
    return BankStatementPage(
      transactions: rows,
      page: query.page,
      limit: query.limit,
      total: rows.length,
    );
  }

  @override
  Future<BankStatementOrderTransferRequestPage> fetchOrderTransferRequests({
    String status = 'PENDING',
    bool allStores = false,
    List<String> storeIds = const [],
    int page = 0,
    int limit = 50,
  }) async {
    return BankStatementOrderTransferRequestPage(
      requests: const [
        BankStatementOrderTransferRequest(
          id: 'request-1',
          transactionId: 'tx-pending',
          storeCode: 'CP01',
          oldOrders: ['26062512345678'],
          requestedOrders: ['26062587654321'],
          status: 'PENDING',
          requestedByEmail: 'staff@example.com',
          reviewedByEmail: null,
          reviewNote: null,
          reviewedAt: null,
          createdAt: null,
          transactionNumber: 'MAP-PENDING',
          transactionReference: null,
          amount: 1250000,
          content: 'Customer transfer',
          paidAt: null,
          firstSeenAt: null,
          notificationReadAt: null,
        ),
      ],
      page: page,
      limit: limit,
      total: 1,
      canReview: true,
    );
  }

  @override
  Future<BankStatementTransaction> updateOrders(
    String transactionId,
    List<String> orders,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<List<BankStatementOrderHistoryEntry>> fetchOrderHistory(
    String transactionId,
  ) async {
    return const [];
  }

  @override
  Future<Uint8List> exportCsv(
    BankStatementQuery query, {
    List<String> transactionIds = const [],
  }) async {
    return Uint8List(0);
  }
}

class _FakeOffsetAdjustmentRepository extends OffsetAdjustmentRepository {
  _FakeOffsetAdjustmentRepository() : super(ApiClient());

  @override
  Future<OffsetAdjustmentPage> fetchList(OffsetAdjustmentQuery query) async {
    return OffsetAdjustmentPage(
      items: const [],
      page: query.page,
      limit: query.limit,
      total: 0,
      canReview: false,
    );
  }
}

final _pendingTransaction = _transaction(
  id: 'tx-pending',
  orders: const ['26062512345678'],
  transactionReference: '00020300000000004567',
  hasPendingOrderTransferRequest: true,
  orderTransferRequestId: 'request-1',
  orderTransferRequestedOrders: const ['26062587654321'],
  orderTransferRequestedByEmail: 'staff@example.com',
  orderTransferRequestedAt: DateTime.utc(2026, 6, 25, 3),
  orderTransferStatus: 'PENDING',
  canEditOrders: false,
  orderEditBlockedReason: 'Giao dịch đang chờ Kế toán xác nhận',
  canRequestOrderTransfer: false,
  orderTransferRequestBlockedReason: 'Giao dịch đang chờ Kế toán xác nhận',
);

final _offsetTransaction = _transaction(
  id: 'tx-offset',
  orders: const ['26062599999999'],
  orderSource: 'OFFSET',
  isOrderOffsetConfirmed: true,
);

BankStatementTransaction _transaction({
  required String id,
  required List<String> orders,
  String? transactionReference,
  String? orderSource,
  bool canEditOrders = true,
  String? orderEditBlockedReason,
  bool canRequestOrderTransfer = true,
  String? orderTransferRequestBlockedReason,
  bool hasPendingOrderTransferRequest = false,
  String? orderTransferRequestId,
  List<String> orderTransferRequestedOrders = const [],
  String? orderTransferRequestedByEmail,
  DateTime? orderTransferRequestedAt,
  String? orderTransferReviewNote,
  String? orderTransferStatus,
  bool isOrderOffsetConfirmed = false,
}) {
  return BankStatementTransaction(
    id: id,
    storeId: 'CP01',
    transactionKey: 'key-$id',
    transactionNumber: 'MAP-$id',
    transactionReference: transactionReference,
    amount: 1250000,
    content: 'Customer transfer',
    orders: orders,
    orderSource: orderSource ?? (orders.isEmpty ? null : 'AUTO'),
    orderUpdatedAt: null,
    orderUpdatedByEmail: null,
    status: '00',
    paidAt: DateTime.utc(2026, 6, 25, 2),
    firstSeenAt: DateTime.utc(2026, 6, 25, 2, 0, 5),
    payerName: null,
    payerAccount: null,
    canEditOrders: canEditOrders,
    orderEditBlockedReason: orderEditBlockedReason,
    canRequestOrderTransfer: canRequestOrderTransfer,
    orderTransferRequestBlockedReason: orderTransferRequestBlockedReason,
    hasPendingOrderTransferRequest: hasPendingOrderTransferRequest,
    orderTransferRequestId: orderTransferRequestId,
    orderTransferRequestedOrders: orderTransferRequestedOrders,
    orderTransferRequestedByEmail: orderTransferRequestedByEmail,
    orderTransferRequestedAt: orderTransferRequestedAt,
    orderTransferReviewNote: orderTransferReviewNote,
    orderTransferStatus: orderTransferStatus,
    isOrderOffsetConfirmed: isOrderOffsetConfirmed,
  );
}
