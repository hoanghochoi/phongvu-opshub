import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../app/widgets/app_layout.dart';
import '../../../../core/logging/app_logger.dart';

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

class BarcodeScannerScreen extends StatefulWidget {
  final String title;
  final String instruction;
  final String helperText;
  final bool parsePhongVuSku;

  const BarcodeScannerScreen({
    super.key,
    this.title = 'Quét QR/Barcode',
    this.instruction = 'Hướng camera vào QR hoặc barcode serial',
    this.helperText = 'Chỉ nhận mã nằm trong khung quét',
    this.parsePhongVuSku = true,
  });

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  MobileScannerController? _controller;
  final _manualController = TextEditingController();
  bool _isTorchOn = false;
  bool _hasResolved = false;
  String? _lastScannerErrorText;
  bool get _supportsCameraScanner =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    unawaited(
      AppLogger.instance.info(
        'BarcodeScanner',
        'Scanner screen opened',
        context: {
          'cameraScannerSupported': _supportsCameraScanner,
          'parsePhongVuSku': widget.parsePhongVuSku,
          'title': widget.title,
        },
      ),
    );
    if (_supportsCameraScanner) {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
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

  void _onDetect(BarcodeCapture capture) {
    if (_hasResolved) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty || !mounted) return;

    String? code;
    for (final barcode in barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.isNotEmpty) {
        code = rawValue;
        break;
      }
    }

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
          'rawCodeLength': code.length,
          'resultLength': sku.length,
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

  Widget _buildScannerError(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Chưa mở được camera. Vui lòng kiểm tra quyền camera rồi thử lại.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomHint(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 20 + bottomPadding),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.instruction,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                if (widget.helperText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.helperText,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _logScannerError(MobileScannerException error) {
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
        body: AppResponsiveContent(
          maxWidth: AppLayoutTokens.formMaxWidth,
          child: AppFormColumn(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.keyboard_alt_outlined, size: 56),
              const Text(
                'Thiết bị này chưa hỗ trợ quét bằng camera. Vui lòng nhập mã thủ công.',
                textAlign: TextAlign.center,
              ),
              TextField(
                controller: _manualController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Mã',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_submitManualCode()),
              ),
              FilledButton.icon(
                onPressed: () => unawaited(_submitManualCode()),
                icon: const Icon(Icons.check_rounded),
                label: const Text(
                  'Dùng mã',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
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
              MobileScanner(
                controller: controller,
                onDetect: _onDetect,
                scanWindow: scanWindow,
                scanWindowUpdateThreshold: 8,
                errorBuilder: (context, error, child) {
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
              _buildBottomHint(context),
            ],
          );
        },
      ),
    );
  }
}

class _ScannerWindowOverlay extends CustomPainter {
  const _ScannerWindowOverlay({required this.scanWindow});

  static const _radius = Radius.circular(22);

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
        ..color = Colors.black.withValues(alpha: 0.36)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(scanWindow, _radius),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerWindowOverlay oldDelegate) {
    return scanWindow != oldDelegate.scanWindow;
  }
}
