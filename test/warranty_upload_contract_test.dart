import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/warranty/data/repositories/warranty_repository.dart';

void main() {
  test('warranty upload fields match backend DTO without user metadata', () {
    final fields = WarrantyRepository.buildWarrantyMultipartFields(
      receiptNumber: '  CP62-J12345678  ',
    );

    expect(fields, {'receipt': 'CP62-J12345678'});
    expect(fields, isNot(contains('user')));
  });
}
