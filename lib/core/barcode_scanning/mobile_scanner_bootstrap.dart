import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

const String opsHubBarcodeLibraryScriptUrl =
    'vendor/zxing-library-0.21.3.min.js';

void initializeMobileScannerWeb() {
  if (!kIsWeb) return;

  // Keep the ZXing runtime on the same origin so the scanner continues to
  // work under the production `script-src 'self'` security policy.
  MobileScannerPlatform.instance.setBarcodeLibraryScriptUrl(
    opsHubBarcodeLibraryScriptUrl,
  );
}
