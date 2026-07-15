import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/barcode_scanning/mobile_scanner_bootstrap.dart';
import 'core/logging/app_logger.dart';
import 'core/platform/media_kit_bootstrap.dart';
import 'core/platform/text_input_context_menu_bootstrap.dart';

void main() {
  runWithAppLogging(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await AppLogger.instance.initialize();
    initializeMobileScannerWeb();
    await initializeTextInputContextMenu();
    await initializeMediaKitIfSupported();
    runApp(const App());
  });
}
