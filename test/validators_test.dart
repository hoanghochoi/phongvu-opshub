import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/utils/email_domain_policy.dart';
import 'package:phongvu_opshub/core/utils/validators.dart';

void main() {
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

  group('EmailDomainPolicy', () {
    test('parses allowed Phong Vu email domains from file contents', () {
      expect(EmailDomainPolicy.parse('phongvu-shop.vn\nphongvu-mna.vn\t\n'), [
        'phongvu-shop.vn',
        'phongvu-mna.vn',
      ]);
    });

    test('accepts only configured Phong Vu email domains', () {
      const domains = ['phongvu-shop.vn', 'phongvu-care.vn'];

      expect(
        EmailDomainPolicy.isAllowedEmail('staff@phongvu-shop.vn', domains),
        isTrue,
      );
      expect(
        EmailDomainPolicy.isAllowedEmail('staff@example.com', domains),
        isFalse,
      );
    });

    test('uses fallback domains before asset load finishes', () {
      expect(
        EmailDomainPolicy.isAllowedEmail('staff@phongvu-office.vn', const []),
        isTrue,
      );
    });
  });
}
