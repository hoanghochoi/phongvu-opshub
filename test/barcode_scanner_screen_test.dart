import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/app_buttons.dart';
import 'package:phongvu_opshub/core/barcode_scanning/barcode_scanner_service.dart';
import 'package:phongvu_opshub/core/barcode_scanning/mobile_scanner_bootstrap.dart';
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

    test('uses the frame as guidance while detecting across the preview', () {
      const size = Size(400, 800);

      expect(barcodeDetectionWindowForSize(size), isNull);
      expect(barcodeScanWindowForSize(size), isNotNull);
    });
  });

  test('uses action-oriented non-restrictive scan guidance', () {
    const scanner = BarcodeScannerScreen();

    expect(scanner.helperText, 'Đưa trọn mã vào giữa khung để quét nhanh hơn');
  });

  test('keeps all scanner formats enabled through the service contract', () {
    expect(opsHubBarcodeFormatLabels, <String>['all']);
  });

  test('loads the web barcode library from the same origin', () {
    expect(opsHubBarcodeLibraryScriptUrl, startsWith('vendor/'));
    expect(opsHubBarcodeLibraryScriptUrl, isNot(contains('://')));
    expect(opsHubBarcodeLibraryScriptUrl, endsWith('.min.js'));
  });

  group('barcode scanner platform support', () {
    test('allows camera scanner on web browsers', () {
      expect(
        barcodeCameraScannerSupported(
          isWeb: true,
          platform: TargetPlatform.iOS,
        ),
        isTrue,
      );
      expect(
        barcodeCameraScannerSupported(
          isWeb: true,
          platform: TargetPlatform.windows,
        ),
        isTrue,
      );
    });

    test('allows camera scanner on supported native targets only', () {
      expect(
        barcodeCameraScannerSupported(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
      expect(
        barcodeCameraScannerSupported(
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        isTrue,
      );
      expect(
        barcodeCameraScannerSupported(
          isWeb: false,
          platform: TargetPlatform.macOS,
        ),
        isTrue,
      );
      expect(
        barcodeCameraScannerSupported(
          isWeb: false,
          platform: TargetPlatform.windows,
        ),
        isFalse,
      );
      expect(
        barcodeCameraScannerSupported(
          isWeb: false,
          platform: TargetPlatform.linux,
        ),
        isFalse,
      );
    });

    test('keeps torch off web and desktop targets', () {
      expect(
        barcodeTorchSupported(isWeb: true, platform: TargetPlatform.iOS),
        isFalse,
      );
      expect(
        barcodeTorchSupported(isWeb: false, platform: TargetPlatform.android),
        isTrue,
      );
      expect(
        barcodeTorchSupported(isWeb: false, platform: TargetPlatform.iOS),
        isTrue,
      );
      expect(
        barcodeTorchSupported(isWeb: false, platform: TargetPlatform.macOS),
        isFalse,
      );
      expect(
        barcodeTorchSupported(isWeb: false, platform: TargetPlatform.windows),
        isFalse,
      );
    });

    test('enables tap to focus only on native mobile targets', () {
      expect(
        barcodeTapToFocusSupported(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
      expect(
        barcodeTapToFocusSupported(isWeb: false, platform: TargetPlatform.iOS),
        isTrue,
      );
      expect(
        barcodeTapToFocusSupported(isWeb: true, platform: TargetPlatform.iOS),
        isFalse,
      );
      expect(
        barcodeTapToFocusSupported(
          isWeb: false,
          platform: TargetPlatform.windows,
        ),
        isFalse,
      );
    });

    test('requests a sharper analyzer stream only on Android', () {
      expect(
        barcodeCameraResolutionForPlatform(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        const Size(1280, 720),
      );
      expect(
        barcodeCameraResolutionForPlatform(
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        isNull,
      );
      expect(
        barcodeCameraResolutionForPlatform(
          isWeb: true,
          platform: TargetPlatform.android,
        ),
        isNull,
      );
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
                      scannedCode = await showBarcodeScanner(context);
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
      await tester.tap(find.byKey(const Key('barcode-manual-submit')));
      await tester.pumpAndSettle();

      expect(scannedCode, '200601320');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('scanner navigation can return raw order codes', (tester) async {
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
                      scannedCode = await showBarcodeScanner(
                        context,
                        parsePhongVuSku: false,
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
      await tester.enterText(
        find.byType(TextField),
        'https://phongvu.vn/esl-s200601320.html?pv_source=esl',
      );
      await tester.tap(find.byKey(const Key('barcode-manual-submit')));
      await tester.pumpAndSettle();

      expect(
        scannedCode,
        'https://phongvu.vn/esl-s200601320.html?pv_source=esl',
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('scanner screen accepts an injected scanner service', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BarcodeScannerScreen(scannerService: MockBarcodeScannerService()),
      ),
    );

    expect(
      find.text(
        'Thiết bị này chưa hỗ trợ quét bằng camera. Vui lòng nhập mã thủ công.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'camera scanner keeps manual input and compact action in one row',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: BarcodeScannerScreen(
            scannerService: _CameraBarcodeScannerService(),
          ),
        ),
      );
      await tester.pump();

      final inputRect = tester.getRect(
        find.byKey(const Key('barcode-manual-input')),
      );
      final buttonRect = tester.getRect(
        find.byKey(const Key('barcode-manual-submit')),
      );

      expect(inputRect.center.dy, closeTo(buttonRect.center.dy, 0.01));
      expect(buttonRect.width, AppButtonMetrics.iconSize);
      expect(inputRect.width, greaterThan(buttonRect.width));
      expect(find.byTooltip('Hoàn thành'), findsOneWidget);
      expect(find.text('Hoàn thành'), findsNothing);
      expect(
        find.text('Hướng camera vào QR hoặc barcode serial'),
        findsNothing,
      );
      expect(
        find.text('Đưa trọn mã vào giữa khung để quét nhanh hơn'),
        findsNothing,
      );
    },
  );

  testWidgets('camera error offers an explicit retry action', (tester) async {
    final service = _CameraBarcodeScannerService(showError: true);

    await tester.pumpWidget(
      MaterialApp(home: BarcodeScannerScreen(scannerService: service)),
    );
    await tester.pump();

    expect(find.text('Thử lại camera'), findsOneWidget);
    await tester.tap(find.text('Thử lại camera'));
    await tester.pump();

    expect(service.controller.startCount, 1);
  });
}

class MockBarcodeScannerService implements BarcodeScannerService {
  const MockBarcodeScannerService();

  @override
  String get backendName => 'mock';

  @override
  List<String> get enabledFormatLabels => const <String>['all'];

  @override
  bool cameraScannerSupported({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    return false;
  }

  @override
  bool torchSupported({required bool isWeb, required TargetPlatform platform}) {
    return false;
  }

  @override
  bool tapToFocusSupported({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    return false;
  }

  @override
  Size? cameraResolutionForPlatform({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    return null;
  }

  @override
  Rect? detectionWindowForSize(Size size) => null;

  @override
  BarcodeScannerControllerHandle createController({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    throw UnimplementedError('Mock scanner does not create controllers.');
  }

  @override
  Widget buildScannerView({
    required BarcodeScannerControllerHandle controller,
    required Size layoutSize,
    required bool isWeb,
    required TargetPlatform platform,
    required ValueChanged<BarcodeScanCapture> onDetect,
    required BarcodeScannerErrorBuilder errorBuilder,
  }) {
    throw UnimplementedError('Mock scanner does not build camera views.');
  }
}

class _CameraBarcodeScannerService implements BarcodeScannerService {
  _CameraBarcodeScannerService({this.showError = false});

  final bool showError;
  final _CameraBarcodeScannerController controller =
      _CameraBarcodeScannerController();

  @override
  String get backendName => 'camera-mock';

  @override
  List<String> get enabledFormatLabels => const <String>['all'];

  @override
  bool cameraScannerSupported({
    required bool isWeb,
    required TargetPlatform platform,
  }) => true;

  @override
  bool torchSupported({required bool isWeb, required TargetPlatform platform}) {
    return false;
  }

  @override
  bool tapToFocusSupported({
    required bool isWeb,
    required TargetPlatform platform,
  }) => false;

  @override
  Size? cameraResolutionForPlatform({
    required bool isWeb,
    required TargetPlatform platform,
  }) => null;

  @override
  Rect? detectionWindowForSize(Size size) => null;

  @override
  BarcodeScannerControllerHandle createController({
    required bool isWeb,
    required TargetPlatform platform,
  }) => controller;

  @override
  Widget buildScannerView({
    required BarcodeScannerControllerHandle controller,
    required Size layoutSize,
    required bool isWeb,
    required TargetPlatform platform,
    required ValueChanged<BarcodeScanCapture> onDetect,
    required BarcodeScannerErrorBuilder errorBuilder,
  }) {
    if (showError) {
      return Builder(
        builder: (context) =>
            errorBuilder(context, StateError('Camera test failure')),
      );
    }
    return const ColoredBox(color: Colors.black);
  }
}

class _CameraBarcodeScannerController
    implements BarcodeScannerControllerHandle {
  int startCount = 0;

  @override
  Future<void> start() async {
    startCount += 1;
  }

  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> toggleTorch() async {}

  @override
  void dispose() {}
}
