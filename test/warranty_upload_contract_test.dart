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

  test('warranty upload timeout scales for large multi-image batches', () {
    final smallBatch = WarrantyRepository.warrantyUploadTimeoutFor(
      totalBytes: 2 * 1024 * 1024,
      imageCount: 1,
    );
    final largeBatch = WarrantyRepository.warrantyUploadTimeoutFor(
      totalBytes: 120 * 1024 * 1024,
      imageCount: 12,
    );
    final cappedBatch = WarrantyRepository.warrantyUploadTimeoutFor(
      totalBytes: 600 * 1024 * 1024,
      imageCount: 20,
    );

    expect(smallBatch, warrantyUploadMinTimeout);
    expect(largeBatch, greaterThan(warrantyUploadMinTimeout));
    expect(cappedBatch, warrantyUploadMaxTimeout);
  });
}
