import 'package:flutter/material.dart';
import 'app/app.dart';
import 'core/logging/app_logger.dart';

void main() {
  runWithAppLogging(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await AppLogger.instance.initialize();
    runApp(const App());
  });
}
