import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _isTorchOn = false;

  @override
  void dispose() {
    _controller.dispose();
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
    setState(() {
      _isTorchOn = !_isTorchOn;
    });
    _controller.toggleTorch();
  }

  @override
  Widget build(BuildContext context) {
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
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera scanner
          MobileScanner(controller: _controller, onDetect: _onDetect),
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
