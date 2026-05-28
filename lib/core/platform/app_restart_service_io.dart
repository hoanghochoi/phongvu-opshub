import 'dart:io';

import '../logging/app_logger.dart';

class AppRestartService {
  Future<void> restart() async {
    if (!Platform.isWindows) {
      await AppLogger.instance.warn(
        'AppRestart',
        'App restart requested on unsupported platform',
        context: {'platform': Platform.operatingSystem},
      );
      return;
    }

    final executable = Platform.resolvedExecutable;
    await AppLogger.instance.info(
      'AppRestart',
      'Restarting Windows app',
      context: {'executable': executable},
    );
    await Process.start(executable, const [], mode: ProcessStartMode.detached);
    await AppLogger.instance.info('AppRestart', 'Windows app restart launched');
    exit(0);
  }
}
