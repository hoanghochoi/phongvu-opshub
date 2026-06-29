import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/fifo_check/presentation/widgets/barcode_scanner_screen.dart';

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

  testWidgets('manual scanner fallback returns parsed PhongVu SKU', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      String? scannedCode;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      scannedCode = await Navigator.of(context).push<String>(
                        MaterialPageRoute(
                          builder: (_) => const BarcodeScannerScreen(),
                        ),
                      );
                    },
                    child: const Text('Mở scanner'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Mở scanner'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Thiết bị này chưa hỗ trợ quét bằng camera. Vui lòng nhập mã thủ công.',
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.byType(TextField),
        'https://phongvu.vn/esl-s200601320.html?pv_source=esl',
      );
      await tester.tap(find.text('Dùng mã'));
      await tester.pumpAndSettle();

      expect(scannedCode, '200601320');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
