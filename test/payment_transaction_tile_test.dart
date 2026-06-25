import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:phongvu_opshub/features/payment_monitor/domain/map_payment_transaction.dart';
import 'package:phongvu_opshub/features/payment_monitor/presentation/widgets/payment_transaction_tile.dart';

void main() {
  testWidgets('shows payer summary and opens full transaction details', (
    tester,
  ) async {
    final transaction = MapPaymentTransaction.fromJson({
      'id': 'stored-transaction-1',
      'storeId': 'CP01',
      'transactionNumber': 'MAP-001',
      'amount': 1250000,
      'content': 'KHACH THANH TOAN DON HANG',
      'orders': ['26062312345678'],
      'status': '00',
      'paidAt': '2026-06-23T03:15:30.000Z',
      'firstSeenAt': '2026-06-23T03:15:35.000Z',
      'payerName': 'NGUYEN VAN A',
      'payerAccount': '9704361234567890',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentTransactionTile(
            transaction: transaction,
            amountFormatter: NumberFormat.decimalPattern('vi_VN'),
          ),
        ),
      ),
    );

    expect(
      find.text('Người chuyển: NGUYEN VAN A • 9704361234567890'),
      findsOneWidget,
    );

    await tester.tap(find.byType(PaymentTransactionTile));
    await tester.pumpAndSettle();

    expect(find.text('Chi tiết giao dịch'), findsOneWidget);
    expect(find.text('NGUYEN VAN A'), findsOneWidget);
    expect(find.text('9704361234567890'), findsOneWidget);
    expect(find.text('1.250.000 VND'), findsWidgets);
    expect(find.text('10:15:30 23/06/2026'), findsOneWidget);
    expect(find.text('MAP-001'), findsOneWidget);
    expect(find.text('KHACH THANH TOAN DON HANG'), findsWidgets);
    expect(find.text('Thành công (00)'), findsOneWidget);
    expect(find.text('CP01'), findsOneWidget);
    expect(find.text('10:15:35 23/06/2026'), findsOneWidget);

    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();

    expect(find.text('Chi tiết giao dịch'), findsNothing);
  });
}
