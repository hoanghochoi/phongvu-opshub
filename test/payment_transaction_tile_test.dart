import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:phongvu_opshub/features/bank_statement/domain/bank_statement_transaction.dart';
import 'package:phongvu_opshub/features/payment_monitor/domain/map_payment_transaction.dart';
import 'package:phongvu_opshub/features/payment_monitor/presentation/providers/payment_monitor_provider.dart';
import 'package:phongvu_opshub/features/payment_monitor/presentation/widgets/payment_transaction_tile.dart';

void main() {
  testWidgets('Payment transaction tile edits orders inline', (tester) async {
    String? savedInput;
    await tester.pumpWidget(
      _wrap(
        PaymentTransactionTile(
          transaction: _transaction(
            orders: const ['26052112345678'],
            canEditOrders: true,
          ),
          amountFormatter: NumberFormat.decimalPattern('vi_VN'),
          rowMessage: const PaymentMonitorRowMessage(
            text: 'Đã cập nhật mã đơn hàng.',
            success: true,
          ),
          canReviewTransfer: false,
          busy: false,
          onSaveOrders: (rawInput) async {
            savedInput = rawInput;
            return true;
          },
          onToggleTracking: () async => true,
          onApproveTransfer: (_) async {},
          onRejectTransfer: (_, {note}) async {},
          onLoadHistory: () async => const <BankStatementOrderHistoryEntry>[],
        ),
      ),
    );

    expect(find.text('Đơn hàng'), findsOneWidget);
    expect(find.text('26052112345678'), findsOneWidget);
    expect(find.text('Đã cập nhật mã đơn hàng.'), findsOneWidget);

    await tester.tap(find.byTooltip('Cập nhật mã đơn'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      '26052287654321\n26052311111111',
    );
    await tester.tap(find.byTooltip('Lưu mã đơn'));
    await tester.pumpAndSettle();

    expect(savedInput, '26052287654321\n26052311111111');
  });

  testWidgets('Payment transaction tile keeps order card compact when wide', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrap(
        PaymentTransactionTile(
          transaction: _transaction(
            orders: const ['26052112345678'],
            canEditOrders: true,
          ),
          amountFormatter: NumberFormat.decimalPattern('vi_VN'),
          rowMessage: null,
          canReviewTransfer: false,
          busy: false,
          onSaveOrders: (_) async => true,
          onToggleTracking: () async => true,
          onApproveTransfer: (_) async {},
          onRejectTransfer: (_, {note}) async {},
          onLoadHistory: () async => const <BankStatementOrderHistoryEntry>[],
        ),
      ),
    );

    final orderEditor = find.byKey(
      const ValueKey('payment-transaction-order-editor'),
    );
    expect(orderEditor, findsOneWidget);
    expect(tester.getSize(orderEditor).width, moreOrLessEquals(260));
    expect(
      tester.getTopLeft(orderEditor).dx,
      greaterThan(tester.getTopLeft(find.textContaining('1.250.000')).dx),
    );
  });

  testWidgets('Payment transaction tile shows pending review controls', (
    tester,
  ) async {
    var approvedRequestId = '';
    await tester.pumpWidget(
      _wrap(
        PaymentTransactionTile(
          transaction: _transaction(
            orders: const ['26052112345678'],
            pendingRequestId: 'request-1',
            requestedOrders: const ['26052287654321'],
          ),
          amountFormatter: NumberFormat.decimalPattern('vi_VN'),
          rowMessage: null,
          canReviewTransfer: true,
          busy: false,
          onSaveOrders: (_) async => true,
          onToggleTracking: () async => true,
          onApproveTransfer: (requestId) async {
            approvedRequestId = requestId;
          },
          onRejectTransfer: (_, {note}) async {},
          onLoadHistory: () async => const <BankStatementOrderHistoryEntry>[],
        ),
      ),
    );

    expect(find.text('Chờ Kế toán xác nhận'), findsOneWidget);
    expect(find.text('26052287654321'), findsOneWidget);

    await tester.tap(find.byTooltip('Phê duyệt cập nhật mã đơn'));
    await tester.pumpAndSettle();

    expect(find.text('Xác nhận cập nhật mã đơn'), findsOneWidget);
    expect(find.text('Đơn đề nghị'), findsOneWidget);

    await tester.tap(find.text('Duyệt'));
    await tester.pumpAndSettle();

    expect(approvedRequestId, 'request-1');
  });

  testWidgets('Payment transaction tile shows statement permission blocker', (
    tester,
  ) async {
    const reason = 'Bạn cần quyền Sao kê để cập nhật mã đơn hàng.';
    await tester.pumpWidget(
      _wrap(
        PaymentTransactionTile(
          transaction: _transaction(
            canEditOrders: false,
            canRequestOrderTransfer: false,
            orderEditBlockedReason: reason,
            orderTransferRequestBlockedReason: reason,
          ),
          amountFormatter: NumberFormat.decimalPattern('vi_VN'),
          rowMessage: null,
          canReviewTransfer: false,
          busy: false,
          onSaveOrders: (_) async => true,
          onToggleTracking: () async => true,
          onApproveTransfer: (_) async {},
          onRejectTransfer: (_, {note}) async {},
          onLoadHistory: () async => const <BankStatementOrderHistoryEntry>[],
        ),
      ),
    );

    expect(find.text(reason), findsOneWidget);
    expect(find.byTooltip(reason), findsWidgets);
  });

  testWidgets(
    'Payment transaction tile exposes one current order update action',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          PaymentTransactionTile(
            transaction: _transaction(
              orders: const ['26052112345678'],
              canEditOrders: true,
              canRequestOrderTransfer: true,
            ),
            amountFormatter: NumberFormat.decimalPattern('vi_VN'),
            rowMessage: null,
            canReviewTransfer: false,
            busy: false,
            onSaveOrders: (_) async => true,
            onToggleTracking: () async => true,
            onApproveTransfer: (_) async {},
            onRejectTransfer: (_, {note}) async {},
            onLoadHistory: () async => const <BankStatementOrderHistoryEntry>[],
          ),
        ),
      );

      expect(find.byTooltip('Cập nhật mã đơn'), findsOneWidget);
      expect(find.byIcon(PhosphorIconsRegular.arrowsLeftRight), findsNothing);
    },
  );

  testWidgets(
    'Payment transaction tile keeps editor open when ERP save fails',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          PaymentTransactionTile(
            transaction: _transaction(
              orders: const ['26052112345678'],
              canEditOrders: true,
            ),
            amountFormatter: NumberFormat.decimalPattern('vi_VN'),
            rowMessage: null,
            canReviewTransfer: false,
            busy: false,
            onSaveOrders: (_) async => false,
            onToggleTracking: () async => true,
            onApproveTransfer: (_) async {},
            onRejectTransfer: (_, {note}) async {},
            onLoadHistory: () async => const <BankStatementOrderHistoryEntry>[],
          ),
        ),
      );

      await tester.tap(find.byTooltip('Cập nhật mã đơn'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '26052287654321');
      await tester.tap(find.byTooltip('Lưu mã đơn'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip('Lưu mã đơn'), findsOneWidget);
    },
  );

  testWidgets('Payment transaction tile shows ERP busy state', (tester) async {
    await tester.pumpWidget(
      _wrap(
        PaymentTransactionTile(
          transaction: _transaction(
            orders: const ['26052112345678'],
            canEditOrders: true,
          ),
          amountFormatter: NumberFormat.decimalPattern('vi_VN'),
          rowMessage: null,
          canReviewTransfer: false,
          busy: true,
          onSaveOrders: (_) async => true,
          onToggleTracking: () async => true,
          onApproveTransfer: (_) async {},
          onRejectTransfer: (_, {note}) async {},
          onLoadHistory: () async => const <BankStatementOrderHistoryEntry>[],
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byTooltip('Đang kiểm tra trạng thái đơn hàng'), findsOneWidget);
    final action = tester.widget<IconButton>(
      find.ancestor(
        of: find.byType(CircularProgressIndicator),
        matching: find.byType(IconButton),
      ),
    );
    expect(action.onPressed, isNull);
  });

  testWidgets(
    'Payment transaction tile toggles tracking and keeps status visible',
    (tester) async {
      var toggleCount = 0;
      await tester.pumpWidget(
        _wrap(
          PaymentTransactionTile(
            transaction: _transaction(
              orders: const ['26052112345678'],
              canEditOrders: true,
              canManageOrderTracking: true,
            ),
            amountFormatter: NumberFormat.decimalPattern('vi_VN'),
            rowMessage: null,
            canReviewTransfer: false,
            busy: false,
            onSaveOrders: (_) async => true,
            onToggleTracking: () async {
              toggleCount += 1;
              return true;
            },
            onApproveTransfer: (_) async {},
            onRejectTransfer: (_, {note}) async {},
            onLoadHistory: () async => const <BankStatementOrderHistoryEntry>[],
          ),
        ),
      );

      expect(find.text('Đang theo dõi'), findsOneWidget);
      await tester.tap(find.byTooltip('Bỏ theo dõi giao dịch'));
      await tester.pump();
      expect(toggleCount, 1);
    },
  );

  testWidgets('Payment transaction tile blocks order edits when unfollowed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        PaymentTransactionTile(
          transaction: _transaction(
            orders: const ['26052112345678'],
            canEditOrders: true,
            canManageOrderTracking: true,
            orderTrackingStatus: 'UNFOLLOWED',
          ),
          amountFormatter: NumberFormat.decimalPattern('vi_VN'),
          rowMessage: null,
          canReviewTransfer: false,
          busy: false,
          onSaveOrders: (_) async => true,
          onToggleTracking: () async => true,
          onApproveTransfer: (_) async {},
          onRejectTransfer: (_, {note}) async {},
          onLoadHistory: () async => const <BankStatementOrderHistoryEntry>[],
        ),
      ),
    );

    final updateButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(
          'Giao dịch đang Bỏ theo dõi. Vui lòng Theo dõi lại trước khi cập nhật mã đơn.',
        ),
        matching: find.byType(IconButton),
      ),
    );
    expect(find.text('Đã bỏ theo dõi'), findsOneWidget);
    expect(updateButton.onPressed, isNull);
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: ListView(children: [child])),
  );
}

MapPaymentTransaction _transaction({
  List<String> orders = const [],
  bool canEditOrders = false,
  bool canRequestOrderTransfer = false,
  bool canManageOrderTracking = false,
  String orderTrackingStatus = 'FOLLOWING',
  String? orderEditBlockedReason,
  String? orderTransferRequestBlockedReason,
  String? pendingRequestId,
  List<String> requestedOrders = const [],
}) {
  return MapPaymentTransaction.fromJson({
    'transactionNumber': 'txn-1',
    'transactionReference': '00020300000000004567',
    'amount': 1250000,
    'storeId': 'CP01',
    'status': '00',
    'orders': orders,
    'canEditOrders': canEditOrders,
    'canRequestOrderTransfer': canRequestOrderTransfer,
    'canManageOrderTracking': canManageOrderTracking,
    'orderTrackingStatus': orderTrackingStatus,
    if (orderEditBlockedReason != null)
      'orderEditBlockedReason': orderEditBlockedReason,
    if (orderTransferRequestBlockedReason != null)
      'orderTransferRequestBlockedReason': orderTransferRequestBlockedReason,
    if (pendingRequestId != null) ...{
      'orderTransferRequestId': pendingRequestId,
      'orderTransferStatus': 'PENDING',
      'orderTransferRequestedOrders': requestedOrders,
      'orderTransferRequestedByEmail': 'requester@example.com',
    },
  });
}
