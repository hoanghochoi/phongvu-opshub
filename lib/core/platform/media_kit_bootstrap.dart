import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../logging/app_logger.dart';

@visibleForTesting
bool shouldInitializeMediaKit({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  return !isWeb && platform == TargetPlatform.windows;
}

Future<void> initializeMediaKitIfSupported({
  bool? isWebOverride,
  TargetPlatform? platformOverride,
}) async {
  final isWeb = isWebOverride ?? kIsWeb;
  final platform = platformOverride ?? defaultTargetPlatform;

  if (!shouldInitializeMediaKit(isWeb: isWeb, platform: platform)) {
    await AppLogger.instance.info(
      'Startup',
      'MediaKit initialization skipped',
      context: {'platform': platform.name, 'isWeb': isWeb},
    );
    return;
  }

  try {
    MediaKit.ensureInitialized();
    await AppLogger.instance.info(
      'Startup',
      'MediaKit initialized',
      context: {'platform': platform.name},
    );
  } catch (error, stackTrace) {
    await AppLogger.instance.error(
      'Startup',
      'MediaKit initialization failed; continuing with fallback audio',
      error: error,
      stackTrace: stackTrace,
      context: {'platform': platform.name},
    );
  }
}
