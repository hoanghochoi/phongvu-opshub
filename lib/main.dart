import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/barcode_scanning/mobile_scanner_bootstrap.dart';
import 'core/logging/app_logger.dart';
import 'core/network/api_client.dart';
import 'core/platform/media_kit_bootstrap.dart';
import 'core/platform/text_input_context_menu_bootstrap.dart';

void main() {
  runWithAppLogging(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await AppLogger.instance.initialize();
    ApiClient().setRateLimitObserver((event) {
      final context = <String, Object?>{
        'action': event.action,
        'method': event.method,
        'endpoint': event.endpoint,
        'attempt': event.attempt,
        'retryAt': event.retryAt?.toIso8601String(),
        'source': event.source,
      };
      unawaited(
        event.action == 'activated'
            ? AppLogger.instance.warn(
                'ApiClient',
                'API endpoint backoff activated',
                context: context,
              )
            : AppLogger.instance.info(
                'ApiClient',
                event.action == 'recovered'
                    ? 'API endpoint backoff recovered'
                    : 'API request deferred by endpoint backoff',
                context: context,
              ),
      );
    });
    initializeMobileScannerWeb();
    await initializeTextInputContextMenu();
    await initializeMediaKitIfSupported();
    runApp(const App());
  });
}
