import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/utils/validators.dart';
import 'package:phongvu_opshub/features/vietqr/domain/entities/vietqr_transfer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Validators.parseFifoCheckInput', () {
    test('parses SKU-only input with default quantity', () {
      expect(Validators.parseFifoCheckInput('abc123'), {
        'sku': 'ABC123',
        'qty': '1',
      });
    });

    test('parses SKU and quantity input', () {
      expect(Validators.parseFifoCheckInput('abc123 10'), {
        'sku': 'ABC123',
        'qty': '10',
      });
    });

    test('rejects inputs with too many parts', () {
      expect(
        () => Validators.parseFifoCheckInput('abc123 10 extra'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Validators.isValidFifoCheckInput', () {
    test('accepts SKU, serial, and SKU quantity formats', () {
      expect(Validators.isValidFifoCheckInput('ABC123'), isTrue);
      expect(Validators.isValidFifoCheckInput('SN123ABC456'), isTrue);
      expect(Validators.isValidFifoCheckInput('ABC123 2'), isTrue);
    });

    test('rejects multi-token free text', () {
      expect(Validators.isValidFifoCheckInput('ABC123 two items'), isFalse);
    });
  });

  group('Validators.isValidWarrantyReceiptNumber', () {
    test('accepts CP receipt and ST numeric repair codes', () {
      expect(Validators.isValidWarrantyReceiptNumber('CP01-J12345678'), isTrue);
      expect(Validators.isValidWarrantyReceiptNumber('st-123456'), isTrue);
    });

    test('rejects malformed warranty receipt numbers', () {
      expect(Validators.isValidWarrantyReceiptNumber('ST-ABC123'), isFalse);
      expect(Validators.isValidWarrantyReceiptNumber('ST-12345'), isFalse);
      expect(Validators.isValidWarrantyReceiptNumber('CP1-J12345678'), isFalse);
    });
  });

  group('Assets', () {
    test('loads the ACare logo asset used by VietQR branding', () async {
      final data = await rootBundle.load('assets/icon/acare_logo.png');
      expect(data.lengthInBytes, greaterThan(1000));
    });
  });

  group('VietQrTransfer', () {
    test('parses QR brand metadata from API responses', () {
      final transfer = VietQrTransfer.fromJson({
        'id': 'payment-1',
        'qrPayload': 'payload',
        'qrBrand': {
          'key': 'acaretek',
          'title': 'ACareTek',
          'logoKey': 'acare',
          'logoAsset': 'assets/icon/acare_logo.png',
        },
      });

      expect(transfer.qrBrand.key, 'acaretek');
      expect(transfer.qrBrand.title, 'ACareTek');
      expect(transfer.qrBrand.logoKey, 'acare');
      expect(transfer.qrBrand.logoAsset, 'assets/icon/acare_logo.png');
    });

    test('falls back to Phong Vu branding for legacy API responses', () {
      final transfer = VietQrTransfer.fromJson({
        'id': 'payment-1',
        'qrPayload': 'payload',
      });

      expect(transfer.qrBrand.key, 'phongvu');
      expect(transfer.qrBrand.title, 'Phong Vũ');
      expect(
        transfer.qrBrand.logoAsset,
        'assets/icon/source/app_icon_master.png',
      );
    });

    test('respects the 15-minute QR expiry boundary', () {
      final createdAt = DateTime.utc(2026, 5, 20, 10, 0, 0);
      final transfer = VietQrTransfer.fromJson({
        'id': 'payment-1',
        'qrPayload': 'payload',
        'createdAt': createdAt.toIso8601String(),
      });
      final historyEntry = VietQrHistoryEntry(
        storeCode: 'CP62',
        transfer: transfer,
      );
      final boundary = createdAt.add(const Duration(minutes: 15));

      expect(historyEntry.isExpired(boundary), isTrue);
      expect(historyEntry.canOpenQr(boundary), isFalse);
      expect(historyEntry.statusCode(boundary), 'EXPIRED');
      expect(historyEntry.statusReason(boundary), 'EXPIRED_VIETNAM_15M');
    });

    test('round-trips history entries through JSON', () {
      final createdAt = DateTime.utc(2026, 5, 20, 10, 0, 0);
      final transfer = VietQrTransfer.fromJson({
        'id': 'payment-1',
        'qrPayload': 'payload',
        'createdAt': createdAt.toIso8601String(),
        'status': 'PENDING',
      });
      final entry = VietQrHistoryEntry(storeCode: 'CP62', transfer: transfer);

      final parsed = VietQrHistoryEntry.fromJson(entry.toJson());

      expect(parsed.storeCode, 'CP62');
      expect(parsed.transfer.id, 'payment-1');
      expect(parsed.transfer.createdAt.toUtc(), createdAt);
      expect(
        parsed.statusCode(createdAt.add(const Duration(minutes: 1))),
        'PENDING',
      );
    });
  });
}
