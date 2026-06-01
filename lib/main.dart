import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app/app.dart';
import 'core/logging/app_logger.dart';

void main() {
  runWithAppLogging(() async {
    WidgetsFlutterBinding.ensureInitialized();
    MediaKit.ensureInitialized();
    await AppLogger.instance.initialize();
    runApp(const App());
  });
}
