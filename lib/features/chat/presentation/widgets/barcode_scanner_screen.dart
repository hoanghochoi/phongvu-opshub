import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../app/widgets/app_layout.dart';

class BarcodeScannerScreen extends StatefulWidget {
  final String title;
  final String instruction;
  final String helperText;
  final bool parsePhongVuSku;

  const BarcodeScannerScreen({
    super.key,
    this.title = 'Quét mã SKU',
    this.instruction = 'Đưa mã vào khung hình để quét',
    this.helperText = 'Hỗ trợ Barcode và QR Code',
    this.parsePhongVuSku = true,
  });

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  MobileScannerController? _controller;
  final _manualController = TextEditingController();
  bool _isTorchOn = false;
  bool get _supportsCameraScanner =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
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
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && mounted) {
      final code = barcodes.first.rawValue;
      if (code != null && code.isNotEmpty) {
        // Parse SKU từ QR code
        final sku = widget.parsePhongVuSku ? _parseSku(code) : code;
        if (sku != null && sku.isNotEmpty) {
          Navigator.of(context).pop(sku);
        }
      }
    }
  }

  void _toggleTorch() {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      _isTorchOn = !_isTorchOn;
    });
    controller.toggleTorch();
  }

  void _submitManualCode() {
    final rawCode = _manualController.text.trim();
    if (rawCode.isEmpty) return;
    final code = widget.parsePhongVuSku ? _parseSku(rawCode) : rawCode;
    if (code == null || code.isEmpty) return;
    Navigator.of(context).pop(code);
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
                'Camera scanner is not supported on this device. Enter the code manually.',
                textAlign: TextAlign.center,
              ),
              TextField(
                controller: _manualController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Code',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitManualCode(),
              ),
              FilledButton.icon(
                onPressed: _submitManualCode,
                icon: const Icon(Icons.check_rounded),
                label: const Text(
                  'Use code',
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
            icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off),
            onPressed: _toggleTorch,
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: () => controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera scanner
          MobileScanner(controller: controller, onDetect: _onDetect),
          // Overlay với hướng dẫn
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.qr_code_scanner,
                    color: Colors.white,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.instruction,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.helperText,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
