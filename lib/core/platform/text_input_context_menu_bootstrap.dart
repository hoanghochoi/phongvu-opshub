import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../logging/app_logger.dart';

typedef ConfigureBrowserContextMenu = Future<void> Function();

enum TextInputContextMenuMode { platformNative, flutter }

@visibleForTesting
TextInputContextMenuMode resolveTextInputContextMenuMode({
  required bool isWeb,
  required TargetPlatform targetPlatform,
}) {
  if (!isWeb) return TextInputContextMenuMode.platformNative;
  return targetPlatform == TargetPlatform.android ||
          targetPlatform == TargetPlatform.iOS
      ? TextInputContextMenuMode.platformNative
      : TextInputContextMenuMode.flutter;
}

bool shouldSuppressFlutterTextInputContextMenu({
  required bool isWeb,
  required TargetPlatform targetPlatform,
}) =>
    resolveTextInputContextMenuMode(
          isWeb: isWeb,
          targetPlatform: targetPlatform,
        ) ==
        TextInputContextMenuMode.platformNative &&
    isWeb;

Future<void> initializeTextInputContextMenu({
  bool? isWebOverride,
  TargetPlatform? targetPlatformOverride,
  ConfigureBrowserContextMenu? disableBrowserContextMenu,
  ConfigureBrowserContextMenu? enableBrowserContextMenu,
}) async {
  final isWeb = isWebOverride ?? kIsWeb;
  final targetPlatform = targetPlatformOverride ?? defaultTargetPlatform;
  final mode = resolveTextInputContextMenuMode(
    isWeb: isWeb,
    targetPlatform: targetPlatform,
  );
  await AppLogger.instance.info(
    'Startup',
    'Text input context menu bootstrap started',
    context: {
      'isWeb': isWeb,
      'targetPlatform': targetPlatform.name,
      'mode': mode.name,
    },
  );

  if (!isWeb) {
    await AppLogger.instance.info(
      'Startup',
      'Text input context menu bootstrap skipped',
      context: {
        'isWeb': isWeb,
        'targetPlatform': targetPlatform.name,
        'mode': mode.name,
      },
    );
    return;
  }

  try {
    if (mode == TextInputContextMenuMode.platformNative) {
      await (enableBrowserContextMenu ??
          BrowserContextMenu.enableContextMenu)();
    } else {
      await (disableBrowserContextMenu ??
          BrowserContextMenu.disableContextMenu)();
    }
    await AppLogger.instance.info(
      'Startup',
      'Text input context menu bootstrap succeeded',
      context: {
        'isWeb': isWeb,
        'targetPlatform': targetPlatform.name,
        'mode': mode.name,
        'browserContextMenuDisabled': mode == TextInputContextMenuMode.flutter,
      },
    );
  } catch (error, stackTrace) {
    await AppLogger.instance.error(
      'Startup',
      'Text input context menu bootstrap failed; continuing with browser defaults',
      error: error,
      stackTrace: stackTrace,
      context: {
        'isWeb': isWeb,
        'targetPlatform': targetPlatform.name,
        'mode': mode.name,
        'browserContextMenuDisabled': false,
      },
    );
  }
}
