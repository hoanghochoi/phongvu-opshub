import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/payment_monitor/domain/map_payment_transaction.dart';

void main() {
  group('MapPaymentTransaction', () {
    test('accepts successful incoming MAP transaction rows', () {
      final transaction = MapPaymentTransaction.fromJson({
        'txnNo': 'MAP-001',
        'txnAmount': '1,250,000',
        'txnDate': '21/05/2026 09:15:30',
        'firstSeenAt': '2026-05-21T02:15:35.000Z',
        'txnDesc': 'Customer transfer',
        'status': '00',
      });

      expect(transaction.id, 'MAP-001');
      expect(transaction.amount, 1250000);
      expect(transaction.content, 'Customer transfer');
      expect(transaction.firstSeenAt, DateTime.utc(2026, 5, 21, 2, 15, 35));
      expect(transaction.isValidIncoming, isTrue);
    });

    test('rejects non-successful or empty-amount rows', () {
      final pending = MapPaymentTransaction.fromJson({
        'txnNo': 'MAP-002',
        'txnAmount': '500000',
        'txnDate': '21/05/2026 09:16:30',
        'status': 'PENDING',
      });
      final emptyAmount = MapPaymentTransaction.fromJson({
        'txnNo': 'MAP-003',
        'txnDate': '21/05/2026 09:17:30',
        'status': '00',
      });

      expect(pending.isValidIncoming, isFalse);
      expect(emptyAmount.isValidIncoming, isFalse);
    });
  });
}
