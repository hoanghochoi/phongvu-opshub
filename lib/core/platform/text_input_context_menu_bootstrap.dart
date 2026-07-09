import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../logging/app_logger.dart';

typedef DisableBrowserContextMenu = Future<void> Function();

@visibleForTesting
bool shouldUseFlutterTextInputContextMenu({required bool isWeb}) => isWeb;

Future<void> initializeTextInputContextMenu({
  bool? isWebOverride,
  DisableBrowserContextMenu? disableBrowserContextMenu,
}) async {
  final isWeb = isWebOverride ?? kIsWeb;
  await AppLogger.instance.info(
    'Startup',
    'Text input context menu bootstrap started',
    context: {'isWeb': isWeb},
  );

  if (!shouldUseFlutterTextInputContextMenu(isWeb: isWeb)) {
    await AppLogger.instance.info(
      'Startup',
      'Text input context menu bootstrap skipped',
      context: {'isWeb': isWeb},
    );
    return;
  }

  try {
    await (disableBrowserContextMenu ??
        BrowserContextMenu.disableContextMenu)();
    await AppLogger.instance.info(
      'Startup',
      'Flutter text input context menu enabled for web paste',
      context: {'isWeb': isWeb, 'browserContextMenuDisabled': true},
    );
  } catch (error, stackTrace) {
    await AppLogger.instance.error(
      'Startup',
      'Text input context menu bootstrap failed; continuing with browser defaults',
      error: error,
      stackTrace: stackTrace,
      context: {'isWeb': isWeb, 'browserContextMenuDisabled': false},
    );
  }
}
