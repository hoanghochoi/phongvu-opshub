import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/chat/presentation/widgets/barcode_scanner_screen.dart';

void main() {
  group('barcodeScanWindowForSize', () {
    test('keeps the scan window smaller than the full camera preview', () {
      const size = Size(400, 800);

      final window = barcodeScanWindowForSize(size);

      expect(window.width, 288);
      expect(window.height, closeTo(178.56, 0.01));
      expect(window.center.dx, 200);
      expect(window.center.dy, 384);
    });

    test('caps the scan window on wider layouts', () {
      const size = Size(900, 700);

      final window = barcodeScanWindowForSize(size);

      expect(window.width, 420);
      expect(window.height, 210);
      expect(window.left, 240);
      expect(window.right, 660);
    });
  });
}
