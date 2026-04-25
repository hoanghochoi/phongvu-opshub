import 'package:flutter_test/flutter_test.dart';
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
}
