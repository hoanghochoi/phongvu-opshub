import 'dart:io';

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
  static const _registryPath =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _valueName = 'PhongVuOpsHub';

  Future<StartupSettingsSnapshot> load() async {
    await AppLogger.instance.info(
      _source,
      'Loading Windows startup setting',
      context: {'platform': Platform.operatingSystem},
    );

    if (!Platform.isWindows) {
      await AppLogger.instance.info(
        _source,
        'Startup setting unsupported on this platform',
        context: {'platform': Platform.operatingSystem},
      );
      return const StartupSettingsSnapshot(
        isSupported: false,
        isEnabled: false,
        message: 'Tùy chọn này chỉ hỗ trợ trên Windows.',
      );
    }

    try {
      final snapshot = await _readWindowsSnapshot();
      await AppLogger.instance.info(
        _source,
        'Windows startup setting loaded',
        context: {
          'enabled': snapshot.isEnabled,
          'hasStaleEntry': snapshot.hasStaleEntry,
        },
      );
      return snapshot;
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        _source,
        'Windows startup setting load failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<StartupSettingsSnapshot> setEnabled(bool enabled) async {
    await AppLogger.instance.info(
      _source,
      'Changing Windows startup setting',
      context: {'targetEnabled': enabled, 'platform': Platform.operatingSystem},
    );

    if (!Platform.isWindows) {
      await AppLogger.instance.warn(
        _source,
        'Startup setting toggle rejected on unsupported platform',
        context: {
          'targetEnabled': enabled,
          'platform': Platform.operatingSystem,
        },
      );
      return const StartupSettingsSnapshot(
        isSupported: false,
        isEnabled: false,
        message: 'Tùy chọn này chỉ hỗ trợ trên Windows.',
      );
    }

    final startedAt = DateTime.now();
    try {
      if (enabled) {
        await _setWindowsStartupValue(_quotedExecutablePath());
      } else {
        await _deleteWindowsStartupValue();
      }

      final snapshot = await _readWindowsSnapshot();
      await AppLogger.instance.info(
        _source,
        'Windows startup setting changed',
        context: {
          'targetEnabled': enabled,
          'enabled': snapshot.isEnabled,
          'hasStaleEntry': snapshot.hasStaleEntry,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return snapshot;
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        _source,
        'Windows startup setting change failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'targetEnabled': enabled,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      rethrow;
    }
  }

  Future<StartupSettingsSnapshot> _readWindowsSnapshot() async {
    final result = await _runPowerShell('''
try {
  (Get-ItemProperty -Path ${_powerShellLiteral(_registryProviderPath)} -Name ${_powerShellLiteral(_valueName)} -ErrorAction Stop).$_valueName
} catch {
  exit 1
}
''');

    if (result.exitCode != 0) {
      return const StartupSettingsSnapshot(isSupported: true, isEnabled: false);
    }

    final existingValue = result.stdout.toString().trim();
    final currentValue = _quotedExecutablePath();
    final matchesCurrent =
        _normalizeRegistryValue(existingValue) ==
        _normalizeRegistryValue(currentValue);

    return StartupSettingsSnapshot(
      isSupported: true,
      isEnabled: matchesCurrent,
      hasStaleEntry: existingValue.isNotEmpty && !matchesCurrent,
      message: existingValue.isNotEmpty && !matchesCurrent
          ? 'Đang có đường dẫn khởi động cũ. Bật lại để cập nhật đúng bản OpsHub hiện tại.'
          : null,
    );
  }

  Future<void> _setWindowsStartupValue(String command) async {
    final result = await _runPowerShell('''
New-Item -Path ${_powerShellLiteral(_registryProviderPath)} -Force | Out-Null
New-ItemProperty -Path ${_powerShellLiteral(_registryProviderPath)} -Name ${_powerShellLiteral(_valueName)} -Value ${_powerShellLiteral(command)} -PropertyType String -Force | Out-Null
''');

    if (result.exitCode == 0) return;

    throw StateError(_powerShellError('set startup value', result));
  }

  Future<void> _deleteWindowsStartupValue() async {
    final result = await _runPowerShell('''
if (Get-ItemProperty -Path ${_powerShellLiteral(_registryProviderPath)} -Name ${_powerShellLiteral(_valueName)} -ErrorAction SilentlyContinue) {
  Remove-ItemProperty -Path ${_powerShellLiteral(_registryProviderPath)} -Name ${_powerShellLiteral(_valueName)} -ErrorAction Stop
}
''');

    if (result.exitCode == 0) return;

    throw StateError(_powerShellError('delete startup value', result));
  }

  Future<ProcessResult> _runPowerShell(String command) {
    return Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      command,
    ]);
  }

  String _quotedExecutablePath() {
    final path = Platform.resolvedExecutable.replaceAll('"', '');
    return '"$path"';
  }
}

String? _normalizeRegistryValue(String? value) {
  if (value == null) return null;
  var normalized = value.trim();
  if (normalized.startsWith('"') && normalized.endsWith('"')) {
    normalized = normalized.substring(1, normalized.length - 1);
  }
  return normalized.replaceAll('/', '\\').toLowerCase();
}

String get _registryProviderPath =>
    StartupSettingsService._registryPath.replaceFirst('HKCU', 'HKCU:');

String _powerShellLiteral(String value) {
  return "'${value.replaceAll("'", "''")}'";
}

String _powerShellError(String action, ProcessResult result) {
  final stderrText = result.stderr.toString().trim();
  final stdoutText = result.stdout.toString().trim();
  return 'PowerShell $action failed (${result.exitCode}): '
      '${stderrText.isNotEmpty ? stderrText : stdoutText}';
}
