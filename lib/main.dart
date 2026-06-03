import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/logging/app_logger.dart';
import 'core/platform/media_kit_bootstrap.dart';

void main() {
  runWithAppLogging(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await AppLogger.instance.initialize();
    await initializeMediaKitIfSupported();
    runApp(const App());
  });
}
