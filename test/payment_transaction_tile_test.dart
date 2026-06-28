import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
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
          onSaveOrders: (rawInput) async {
            savedInput = rawInput;
          },
          onRequestTransfer: (_) async => true,
          onApproveTransfer: (_) async {},
          onRejectTransfer: (_, {note}) async {},
          onLoadHistory: () async => const <BankStatementOrderHistoryEntry>[],
        ),
      ),
    );

    expect(find.text('Đơn hàng'), findsOneWidget);
    expect(find.text('26052112345678'), findsOneWidget);
    expect(find.text('Đã cập nhật mã đơn hàng.'), findsOneWidget);

    await tester.tap(find.byTooltip('Sửa mã đơn'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      '26052287654321\n26052311111111',
    );
    await tester.tap(find.byTooltip('Lưu mã đơn'));
    await tester.pumpAndSettle();

    expect(savedInput, '26052287654321\n26052311111111');
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
          onSaveOrders: (_) async {},
          onRequestTransfer: (_) async => true,
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
          onSaveOrders: (_) async {},
          onRequestTransfer: (_) async => true,
          onApproveTransfer: (_) async {},
          onRejectTransfer: (_, {note}) async {},
          onLoadHistory: () async => const <BankStatementOrderHistoryEntry>[],
        ),
      ),
    );

    expect(find.text(reason), findsOneWidget);
    expect(find.byTooltip(reason), findsWidgets);
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
