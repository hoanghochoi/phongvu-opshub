import '../../../core/logging/app_logger.dart';

class StartupSettingsSnapshot {
  const StartupSettingsSnapshot({
    required this.isSupported,
    required this.isEnabled,
    this.hasStaleEntry = false,
    this.message,
  });

  final bool isSupported;
  final bool isEnabled;
  final bool hasStaleEntry;
  final String? message;
}

class StartupSettingsService {
  static const _source = 'StartupSettings';

  Future<StartupSettingsSnapshot> load() async {
    await AppLogger.instance.info(
      _source,
      'Startup setting load skipped on unsupported platform',
      context: {'supported': false},
    );
    return const StartupSettingsSnapshot(
      isSupported: false,
      isEnabled: false,
      message: 'Tùy chọn này chỉ hỗ trợ trên Windows.',
    );
  }

  Future<StartupSettingsSnapshot> setEnabled(bool enabled) async {
    await AppLogger.instance.warn(
      _source,
      'Startup setting toggle rejected on unsupported platform',
      context: {'targetEnabled': enabled, 'supported': false},
    );
    return const StartupSettingsSnapshot(
      isSupported: false,
      isEnabled: false,
      message: 'Tùy chọn này chỉ hỗ trợ trên Windows.',
    );
  }
}
