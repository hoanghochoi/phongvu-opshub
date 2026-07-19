import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/barcode_scanning/barcode_scanner_service.dart';
import '../../../../core/barcode_scanning/mobile_scanner_barcode_scanner_service.dart';
import '../../../../core/logging/app_logger.dart';

const BarcodeScannerService defaultBarcodeScannerService =
    MobileScannerBarcodeScannerService();

List<String> get opsHubBarcodeFormatLabels =>
    defaultBarcodeScannerService.enabledFormatLabels;

Rect barcodeScanWindowForSize(Size size) {
  final availableWidth = math.max(0.0, size.width - 48);
  final scanWidth = math.min(
    math.min(size.width * 0.72, 420.0),
    availableWidth,
  );
  final scanHeight = math.min(scanWidth * 0.62, size.height * 0.30);
  final center = Offset(size.width / 2, size.height * 0.48);

  return Rect.fromCenter(center: center, width: scanWidth, height: scanHeight);
}

Rect? barcodeDetectionWindowForSize(Size size) {
  return defaultBarcodeScannerService.detectionWindowForSize(size);
}

bool barcodeCameraScannerSupported({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  return defaultBarcodeScannerService.cameraScannerSupported(
    isWeb: isWeb,
    platform: platform,
  );
}

bool barcodeTorchSupported({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  return defaultBarcodeScannerService.torchSupported(
    isWeb: isWeb,
    platform: platform,
  );
}

bool barcodeTapToFocusSupported({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  return defaultBarcodeScannerService.tapToFocusSupported(
    isWeb: isWeb,
    platform: platform,
  );
}

Size? barcodeCameraResolutionForPlatform({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  return defaultBarcodeScannerService.cameraResolutionForPlatform(
    isWeb: isWeb,
    platform: platform,
  );
}

Future<String?> showBarcodeScanner(
  BuildContext context, {
  String title = 'Quét QR/Barcode',
  String instruction = 'Hướng camera vào QR hoặc barcode serial',
  String helperText = 'Đưa trọn mã vào giữa khung để quét nhanh hơn',
  bool parsePhongVuSku = true,
  bool rootNavigator = false,
  BarcodeScannerService scannerService = defaultBarcodeScannerService,
}) {
  return Navigator.of(context, rootNavigator: rootNavigator).push<String>(
    MaterialPageRoute(
      settings: const RouteSettings(name: '/barcode-scanner'),
      builder: (_) => BarcodeScannerScreen(
        title: title,
        instruction: instruction,
        helperText: helperText,
        parsePhongVuSku: parsePhongVuSku,
        scannerService: scannerService,
      ),
    ),
  );
}

class BarcodeScannerScreen extends StatefulWidget {
  final String title;
  final String instruction;
  final String helperText;
  final bool parsePhongVuSku;
  final BarcodeScannerService scannerService;

  const BarcodeScannerScreen({
    super.key,
    this.title = 'Quét QR/Barcode',
    this.instruction = 'Hướng camera vào QR hoặc barcode serial',
    this.helperText = 'Đưa trọn mã vào giữa khung để quét nhanh hơn',
    this.parsePhongVuSku = true,
    this.scannerService = defaultBarcodeScannerService,
  });

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  BarcodeScannerControllerHandle? _controller;
  final _manualController = TextEditingController();
  bool _isTorchOn = false;
  bool _hasResolved = false;
  String? _lastScannerErrorText;
  bool get _supportsCameraScanner => widget.scannerService
      .cameraScannerSupported(isWeb: kIsWeb, platform: defaultTargetPlatform);
  bool get _supportsTorch => widget.scannerService.torchSupported(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
  );

  String get _requestedCameraResolutionLabel {
    final resolution = widget.scannerService.cameraResolutionForPlatform(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    );
    if (resolution == null) return 'platform_default';
    return '${resolution.width.toInt()}x${resolution.height.toInt()}';
  }

  @override
  void initState() {
    super.initState();
    unawaited(
      AppLogger.instance.info(
        'BarcodeScanner',
        'Scanner screen opened',
        context: {
          'cameraScannerSupported': _supportsCameraScanner,
          'scannerBackend': widget.scannerService.backendName,
          'detectionRegion': 'full_preview',
          'formats': widget.scannerService.enabledFormatLabels.join(','),
          'requestedCameraResolution': _requestedCameraResolutionLabel,
          'parsePhongVuSku': widget.parsePhongVuSku,
          'title': widget.title,
        },
      ),
    );
    if (_supportsCameraScanner) {
      _controller = widget.scannerService.createController(
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _manualController.dispose();
    super.dispose();
  }

  String? _parseSku(String rawCode) {
    // Nếu là URL phongvu.vn, parse để lấy SKU
    // Format: https://phongvu.vn/esl-s200601320.html?pv_source=esl
    // Extract: 200601320 (số giữa 's' và '.')
    if (rawCode.contains('phongvu.vn')) {
      final regex = RegExp(r'esl-s(\d+)\.html');
      final match = regex.firstMatch(rawCode);
      if (match != null && match.groupCount >= 1) {
        return match.group(1); // Trả về SKU number
      }
    }

    // Nếu không phải URL hoặc không match pattern, trả về raw code
    return rawCode;
  }

  void _onDetect(BarcodeScanCapture capture) {
    if (_hasResolved) return;
    final barcodes = capture.values;
    if (barcodes.isEmpty || !mounted) return;

    BarcodeScanValue? selectedBarcode;
    for (final barcode in barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue.isNotEmpty) {
        selectedBarcode = barcode;
        break;
      }
    }

    final code = selectedBarcode?.rawValue;
    if (code == null) {
      unawaited(
        AppLogger.instance.warn(
          'BarcodeScanner',
          'Detected barcode without readable value',
          context: {'barcodeCount': barcodes.length},
        ),
      );
      return;
    }

    // Parse SKU từ QR code
    final sku = widget.parsePhongVuSku ? _parseSku(code) : code;
    if (sku == null || sku.isEmpty) {
      unawaited(
        AppLogger.instance.warn(
          'BarcodeScanner',
          'Detected barcode parse returned empty result',
          context: {
            'rawCodeLength': code.length,
            'parsePhongVuSku': widget.parsePhongVuSku,
          },
        ),
      );
      return;
    }

    _hasResolved = true;
    unawaited(
      AppLogger.instance.info(
        'BarcodeScanner',
        'Barcode scan succeeded',
        context: {
          'barcodeCount': barcodes.length,
          'barcodeFormat': selectedBarcode!.formatName,
          'rawCodeLength': code.length,
          'resultLength': sku.length,
          'detectionRegion': 'full_preview',
          'scannerBackend': widget.scannerService.backendName,
          'parsePhongVuSku': widget.parsePhongVuSku,
        },
      ),
    );
    Navigator.of(context).pop(sku);
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null) return;
    final nextTorchState = !_isTorchOn;
    setState(() {
      _isTorchOn = nextTorchState;
    });
    try {
      await controller.toggleTorch();
      await AppLogger.instance.info(
        'BarcodeScanner',
        'Scanner torch toggled',
        context: {'enabled': nextTorchState},
      );
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() {
          _isTorchOn = !nextTorchState;
        });
      }
      await AppLogger.instance.error(
        'BarcodeScanner',
        'Scanner torch toggle failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _switchCamera() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.switchCamera();
      await AppLogger.instance.info(
        'BarcodeScanner',
        'Scanner camera switched',
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'BarcodeScanner',
        'Scanner camera switch failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _submitManualCode() async {
    final rawCode = _manualController.text.trim();
    if (rawCode.isEmpty) return;
    final code = widget.parsePhongVuSku ? _parseSku(rawCode) : rawCode;
    if (code == null || code.isEmpty) return;
    unawaited(
      AppLogger.instance.info(
        'BarcodeScanner',
        'Manual barcode submitted',
        context: {
          'rawCodeLength': rawCode.length,
          'resultLength': code.length,
          'parsePhongVuSku': widget.parsePhongVuSku,
        },
      ),
    );
    Navigator.of(context).pop(code);
  }

  Future<void> _retryCamera() async {
    final controller = _controller;
    if (controller == null) return;

    await AppLogger.instance.info(
      'BarcodeScanner',
      'Scanner camera retry requested',
      context: {
        'scannerBackend': widget.scannerService.backendName,
        'isWeb': kIsWeb,
        'platform': defaultTargetPlatform.name,
      },
    );
    try {
      await controller.start();
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'BarcodeScanner',
        'Scanner camera retry failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Widget _buildScannerError(BuildContext context) {
    return ColoredBox(
      color: AppColors.shadow,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Chưa mở được camera. Hãy cho phép camera cho trang này rồi thử lại.',
                style: AppTextStyles.bodyL.copyWith(color: AppColors.surface),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              AppSecondaryButton(
                onPressed: () => unawaited(_retryCamera()),
                icon: Icons.refresh_rounded,
                label: 'Thử lại camera',
                foregroundColor: AppColors.surface,
                borderColor: AppColors.surface,
                expand: false,
                height: AppButtonMetrics.compactActionHeight,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManualEntryBar({bool autofocus = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: AppTextInput(
            key: const Key('barcode-manual-input'),
            controller: _manualController,
            label: 'Nhập mã',
            dense: true,
            autofocus: autofocus,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => unawaited(_submitManualCode()),
          ),
        ),
        const SizedBox(width: 8),
        AppIconAction(
          key: const Key('barcode-manual-submit'),
          onPressed: () => unawaited(_submitManualCode()),
          icon: Icons.check_rounded,
          tooltip: 'Hoàn thành',
          filled: true,
        ),
      ],
    );
  }

  Widget _buildBottomPanel(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomPadding),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayoutTokens.formMaxWidth,
          ),
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
            elevation: 8,
            shadowColor: AppColors.shadow.withValues(alpha: 0.20),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: _buildManualEntryBar(),
            ),
          ),
        ),
      ),
    );
  }

  void _logScannerError(Object error) {
    final errorText = error.toString();
    if (_lastScannerErrorText == errorText) return;
    _lastScannerErrorText = errorText;
    unawaited(
      AppLogger.instance.error(
        'BarcodeScanner',
        'Scanner camera failed',
        error: error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_supportsCameraScanner) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: AppResponsiveScrollView(
          key: const Key('barcode-fallback-scroll'),
          maxWidth: AppLayoutTokens.formMaxWidth,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: AppFormColumn(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.keyboard_alt_outlined, size: 56),
              const Text(
                'Thiết bị này chưa hỗ trợ quét bằng camera. Vui lòng nhập mã thủ công.',
                textAlign: TextAlign.center,
              ),
              _buildManualEntryBar(autofocus: true),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return const Scaffold(
        body: AppStatePanel.loading(
          title: 'Đang mở máy quét',
          message: 'Vui lòng chờ trong giây lát.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_supportsTorch)
            IconButton(
              tooltip: 'Bật/tắt đèn flash',
              icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off),
              onPressed: () => unawaited(_toggleTorch()),
            ),
          IconButton(
            tooltip: 'Đổi camera',
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: () => unawaited(_switchCamera()),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final layoutSize = constraints.biggest;
          final scanWindow = barcodeScanWindowForSize(layoutSize);

          return Stack(
            fit: StackFit.expand,
            children: [
              widget.scannerService.buildScannerView(
                controller: controller,
                layoutSize: layoutSize,
                isWeb: kIsWeb,
                platform: defaultTargetPlatform,
                onDetect: _onDetect,
                errorBuilder: (context, error) {
                  _logScannerError(error);
                  return _buildScannerError(context);
                },
              ),
              IgnorePointer(
                child: CustomPaint(
                  painter: _ScannerWindowOverlay(scanWindow: scanWindow),
                  child: const SizedBox.expand(),
                ),
              ),
              _buildBottomPanel(context),
            ],
          );
        },
      ),
    );
  }
}

class _ScannerWindowOverlay extends CustomPainter {
  const _ScannerWindowOverlay({required this.scanWindow});

  static const _radius = Radius.circular(AppRadius.xl);

  final Rect scanWindow;

  @override
  void paint(Canvas canvas, Size size) {
    final fullScreen = Path()..addRect(Offset.zero & size);
    final cutout = Path()
      ..addRRect(RRect.fromRectAndRadius(scanWindow, _radius));
    final overlay = Path.combine(PathOperation.difference, fullScreen, cutout);

    canvas.drawPath(
      overlay,
      Paint()
        ..color = AppColors.shadow.withValues(alpha: 0.36)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(scanWindow, _radius),
      Paint()
        ..color = AppColors.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerWindowOverlay oldDelegate) {
    return scanWindow != oldDelegate.scanWindow;
  }
}
