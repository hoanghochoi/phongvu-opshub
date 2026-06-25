import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/utils/validators.dart';
import 'package:phongvu_opshub/features/vietqr/domain/entities/vietqr_transfer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Validators.parseMessage', () {
    test('parses SKU-only input with default quantity', () {
      expect(Validators.parseMessage('abc123'), {'sku': 'ABC123', 'qty': '1'});
    });

    test('parses SKU and quantity input', () {
      expect(Validators.parseMessage('abc123 10'), {
        'sku': 'ABC123',
        'qty': '10',
      });
    });

    test('rejects inputs with too many parts', () {
      expect(
        () => Validators.parseMessage('abc123 10 extra'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Validators.isValidMessage', () {
    test('accepts SKU, serial, and SKU quantity formats', () {
      expect(Validators.isValidMessage('ABC123'), isTrue);
      expect(Validators.isValidMessage('SN123ABC456'), isTrue);
      expect(Validators.isValidMessage('ABC123 2'), isTrue);
    });

    test('rejects multi-token free text', () {
      expect(Validators.isValidMessage('ABC123 two items'), isFalse);
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
  });
}
