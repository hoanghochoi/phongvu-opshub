import 'package:flutter/material.dart';

class BarcodeScanValue {
  const BarcodeScanValue({required this.rawValue, required this.formatName});

  final String rawValue;
  final String formatName;
}

class BarcodeScanCapture {
  const BarcodeScanCapture({required this.values});

  final List<BarcodeScanValue> values;
}

abstract interface class BarcodeScannerControllerHandle {
  Future<void> toggleTorch();

  Future<void> switchCamera();

  void dispose();
}

typedef BarcodeScannerErrorBuilder =
    Widget Function(BuildContext context, Object error);

abstract interface class BarcodeScannerService {
  String get backendName;

  List<String> get enabledFormatLabels;

  bool cameraScannerSupported({
    required bool isWeb,
    required TargetPlatform platform,
  });

  bool torchSupported({required bool isWeb, required TargetPlatform platform});

  bool tapToFocusSupported({
    required bool isWeb,
    required TargetPlatform platform,
  });

  Size? cameraResolutionForPlatform({
    required bool isWeb,
    required TargetPlatform platform,
  });

  Rect? detectionWindowForSize(Size size);

  BarcodeScannerControllerHandle createController({
    required bool isWeb,
    required TargetPlatform platform,
  });

  Widget buildScannerView({
    required BarcodeScannerControllerHandle controller,
    required Size layoutSize,
    required bool isWeb,
    required TargetPlatform platform,
    required ValueChanged<BarcodeScanCapture> onDetect,
    required BarcodeScannerErrorBuilder errorBuilder,
  });
}
