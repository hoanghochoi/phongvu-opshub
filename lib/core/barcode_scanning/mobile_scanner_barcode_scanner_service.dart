import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'barcode_scanner_service.dart';

// An empty format list enables every format supported by mobile_scanner,
// including Code 128 and Data Matrix used on product serial labels.
const List<BarcodeFormat> opsHubMobileScannerFormats = <BarcodeFormat>[];
const Size androidBarcodeCameraResolution = Size(1280, 720);

class MobileScannerBarcodeScannerService implements BarcodeScannerService {
  const MobileScannerBarcodeScannerService();

  @override
  String get backendName => 'mobile_scanner';

  @override
  List<String> get enabledFormatLabels => const <String>['all'];

  @override
  bool cameraScannerSupported({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    return isWeb ||
        platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS ||
        platform == TargetPlatform.macOS;
  }

  @override
  bool torchSupported({required bool isWeb, required TargetPlatform platform}) {
    return !isWeb &&
        (platform == TargetPlatform.android || platform == TargetPlatform.iOS);
  }

  @override
  bool tapToFocusSupported({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    return !isWeb &&
        (platform == TargetPlatform.android || platform == TargetPlatform.iOS);
  }

  @override
  Size? cameraResolutionForPlatform({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    if (!isWeb && platform == TargetPlatform.android) {
      return androidBarcodeCameraResolution;
    }
    return null;
  }

  @override
  Rect? detectionWindowForSize(Size _) {
    // The frame guides the user, while the detector analyzes the full preview.
    // Texture-space scan windows have caused valid codes to be missed on devices.
    return null;
  }

  @override
  BarcodeScannerControllerHandle createController({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    return MobileScannerControllerAdapter(
      MobileScannerController(
        cameraResolution: cameraResolutionForPlatform(
          isWeb: isWeb,
          platform: platform,
        ),
        detectionSpeed: DetectionSpeed.noDuplicates,
        autoZoom: !isWeb && platform == TargetPlatform.android,
        formats: opsHubMobileScannerFormats,
      ),
    );
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
    final mobileController = controller as MobileScannerControllerAdapter;
    return MobileScanner(
      controller: mobileController.inner,
      onDetect: (capture) {
        onDetect(
          BarcodeScanCapture(
            values: [
              for (final barcode in capture.barcodes)
                if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty)
                  BarcodeScanValue(
                    rawValue: barcode.rawValue!,
                    formatName: barcode.format.name,
                  ),
            ],
          ),
        );
      },
      scanWindow: detectionWindowForSize(layoutSize),
      tapToFocus: tapToFocusSupported(isWeb: isWeb, platform: platform),
      errorBuilder: errorBuilder,
    );
  }
}

class MobileScannerControllerAdapter implements BarcodeScannerControllerHandle {
  MobileScannerControllerAdapter(this.inner);

  final MobileScannerController inner;

  @override
  Future<void> toggleTorch() => inner.toggleTorch();

  @override
  Future<void> switchCamera() => inner.switchCamera();

  @override
  void dispose() => inner.dispose();
}
