import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:phongvu_opshub/features/bank_statement/domain/bank_statement_transaction.dart';
import 'package:phongvu_opshub/features/bank_statement/presentation/widgets/bank_statement_transaction_details.dart';

void main() {
  testWidgets('opens selectable full bank statement transaction details', (
    tester,
  ) async {
    final transaction = BankStatementTransaction.fromJson({
      'id': 'stored-transaction-1',
      'storeId': 'CP01',
      'transactionKey': 'CP01:key-1',
      'transactionNumber': 'MAP-001',
      'amount': 1250000,
      'content': 'KHACH THANH TOAN DON HANG',
      'orders': ['26062312345678', '26062387654321'],
      'orderSource': 'MANUAL',
      'orderUpdatedAt': '2026-06-23T04:00:00.000Z',
      'orderUpdatedByEmail': 'manager@example.com',
      'status': '00',
      'paidAt': '2026-06-23T03:15:30.000Z',
      'firstSeenAt': '2026-06-23T03:15:35.000Z',
      'payerName': 'NGUYEN VAN A',
      'payerAccount': '9704361234567890',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BankStatementTransactionDetailsLauncher(
            transaction: transaction,
            amountFormatter: NumberFormat.decimalPattern('vi_VN'),
            child: const Text('Tóm tắt giao dịch'),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(BankStatementTransactionDetailsLauncher));
    await tester.pumpAndSettle();

    expect(find.text('Chi tiết giao dịch sao kê'), findsOneWidget);
    expect(find.text('NGUYEN VAN A'), findsOneWidget);
    expect(find.text('9704361234567890'), findsOneWidget);
    expect(find.text('1.250.000 VND'), findsOneWidget);
    expect(find.text('10:15:30 23/06/2026'), findsOneWidget);
    expect(find.text('MAP-001'), findsOneWidget);
    expect(find.text('KHACH THANH TOAN DON HANG'), findsOneWidget);
    expect(find.text('Thành công'), findsOneWidget);
    expect(find.text('CP01'), findsOneWidget);
    expect(find.text('26062312345678, 26062387654321'), findsOneWidget);
    expect(find.text('Chỉnh sửa thủ công'), findsOneWidget);
    expect(find.text('manager@example.com'), findsOneWidget);
    expect(find.text('11:00:00 23/06/2026'), findsOneWidget);
    expect(find.text('10:15:35 23/06/2026'), findsOneWidget);

    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();

    expect(find.text('Chi tiết giao dịch sao kê'), findsNothing);
  });
}
