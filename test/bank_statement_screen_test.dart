import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/store_branch.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/bank_statement/data/bank_statement_repository.dart';
import 'package:phongvu_opshub/features/bank_statement/domain/bank_statement_transaction.dart';
import 'package:phongvu_opshub/features/bank_statement/presentation/providers/bank_statement_provider.dart';
import 'package:phongvu_opshub/features/bank_statement/presentation/screens/bank_statement_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows ACC bell, pending transfer state, and offset tag', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = _WidgetBankStatementRepository();
    final provider = BankStatementProvider(repository);
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

    expect(find.byTooltip('1 yêu cầu cập nhật mã đơn'), findsOneWidget);
    expect(find.text('Chờ ACC xác nhận'), findsOneWidget);
    expect(find.text('Đã cấn trừ'), findsOneWidget);
    expect(find.byTooltip('Giao dịch đang chờ ACC xác nhận'), findsWidgets);

    expect(provider.pendingOrderTransferTotal, 1);

    await tester.tap(find.byTooltip('1 yêu cầu cập nhật mã đơn'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Yêu cầu cập nhật mã đơn'), findsOneWidget);
    expect(find.text('26062512345678 → 26062587654321'), findsOneWidget);
    expect(find.text('Người gửi: staff@example.com'), findsOneWidget);
  });
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
          reviewedAt: null,
          createdAt: null,
          transactionNumber: 'MAP-PENDING',
          amount: 1250000,
          content: 'Customer transfer',
          paidAt: null,
          firstSeenAt: null,
        ),
      ],
      page: page,
      limit: limit,
      total: 1,
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

final _pendingTransaction = _transaction(
  id: 'tx-pending',
  orders: const ['26062512345678'],
  hasPendingOrderTransferRequest: true,
  orderTransferRequestId: 'request-1',
  orderTransferRequestedOrders: const ['26062587654321'],
  orderTransferStatus: 'PENDING',
  canEditOrders: false,
  orderEditBlockedReason: 'Giao dịch đang chờ ACC xác nhận',
  canRequestOrderTransfer: false,
  orderTransferRequestBlockedReason: 'Giao dịch đang chờ ACC xác nhận',
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
  String? orderSource,
  bool canEditOrders = true,
  String? orderEditBlockedReason,
  bool canRequestOrderTransfer = true,
  String? orderTransferRequestBlockedReason,
  bool hasPendingOrderTransferRequest = false,
  String? orderTransferRequestId,
  List<String> orderTransferRequestedOrders = const [],
  String? orderTransferStatus,
  bool isOrderOffsetConfirmed = false,
}) {
  return BankStatementTransaction(
    id: id,
    storeId: 'CP01',
    transactionKey: 'key-$id',
    transactionNumber: 'MAP-$id',
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
    orderTransferStatus: orderTransferStatus,
    isOrderOffsetConfirmed: isOrderOffsetConfirmed,
  );
}
