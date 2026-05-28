import '../logging/app_logger.dart';

class AppRestartService {
  Future<void> restart() async {
    await AppLogger.instance.warn(
      'AppRestart',
      'App restart requested on unsupported platform',
    );
  }
}
