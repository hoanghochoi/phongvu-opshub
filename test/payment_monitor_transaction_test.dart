import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/vietnamese_amount_words.dart';
import 'package:phongvu_opshub/features/payment_monitor/domain/map_payment_transaction.dart';
import 'package:phongvu_opshub/features/payment_monitor/domain/payment_notification.dart';

void main() {
  group('MapPaymentTransaction', () {
    test('accepts successful incoming MAP transaction rows', () {
      final transaction = MapPaymentTransaction.fromJson({
        'txnNo': 'MAP-001',
        'txnAmount': '1,250,000',
        'txnDate': '21/05/2026 09:15:30',
        'firstSeenAt': '2026-05-21T02:15:35.000Z',
        'txnDesc': 'Customer transfer',
        'storeId': 'CP01',
        'payerName': 'NGUYEN VAN A',
        'payerAccount': '9704361234567890',
        'status': '00',
      });

      expect(transaction.id, 'MAP-001');
      expect(transaction.storeId, 'CP01');
      expect(transaction.amount, 1250000);
      expect(transaction.content, 'Customer transfer');
      expect(transaction.status, '00');
      expect(transaction.payerName, 'NGUYEN VAN A');
      expect(transaction.payerAccount, '9704361234567890');
      expect(transaction.payerLabel, 'NGUYEN VAN A • 9704361234567890');
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

  group('vietnameseAmountWords', () {
    test('formats common payment amounts for speech', () {
      expect(vietnameseAmountWords(150000), 'một trăm năm mươi nghìn');
      expect(
        vietnameseAmountWords(1250000),
        'một triệu hai trăm năm mươi nghìn',
      );
      expect(
        vietnameseAmountWords(1005000),
        'một triệu không trăm lẻ năm nghìn',
      );
      expect(
        vietnameseAmountWords(21000005),
        'hai mươi mốt triệu không trăm lẻ năm',
      );
    });
  });

  group('PaymentNotification', () {
    test('parses scoped realtime notification payload', () {
      final notification = PaymentNotification.fromJson({
        'notificationId': 'note-1',
        'transactionId': 'txn-1',
        'storeCode': 'CP01',
        'amount': '1,250,000',
        'audioStatus': 'READY',
        'audioUrl': '/payment-notifications/note-1/audio',
        'createdAt': '2026-05-21T10:00:00.000Z',
      });

      expect(notification.isValid, isTrue);
      expect(notification.amount, 1250000);
      expect(notification.storeCode, 'CP01');
      expect(notification.audioUrl, '/payment-notifications/note-1/audio');
    });
  });
}
