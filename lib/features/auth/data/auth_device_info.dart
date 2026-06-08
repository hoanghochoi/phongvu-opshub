import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/app_storage_keys.dart';

class AuthDevicePayload {
  const AuthDevicePayload({
    required this.platform,
    required this.deviceId,
    this.deviceLabel,
    this.appVersion,
    this.buildNumber,
  });

  final String platform;
  final String deviceId;
  final String? deviceLabel;
  final String? appVersion;
  final String? buildNumber;

  Map<String, dynamic> toJson() => {
    'platform': platform,
    'deviceId': deviceId,
    if (deviceLabel != null) 'deviceLabel': deviceLabel,
    if (appVersion != null) 'appVersion': appVersion,
    if (buildNumber != null) 'buildNumber': buildNumber,
  };
}

class AuthDeviceInfoProvider {
  AuthDeviceInfoProvider({
    FlutterSecureStorage? storage,
    Future<PackageInfo> Function()? packageInfoLoader,
    Uuid? uuid,
    TargetPlatform? platformOverride,
    bool? isWebOverride,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
       _uuid = uuid ?? const Uuid(),
       _platformOverride = platformOverride,
       _isWebOverride = isWebOverride;

  static const deviceIdKey = 'auth_device_id';
  static String get storageDeviceIdKey => AppStorageKeys.secure(deviceIdKey);

  final FlutterSecureStorage _storage;
  final Future<PackageInfo> Function() _packageInfoLoader;
  final Uuid _uuid;
  final TargetPlatform? _platformOverride;
  final bool? _isWebOverride;

  Future<AuthDevicePayload> load() async {
    final platform = platformName(
      platform: _platformOverride,
      isWeb: _isWebOverride,
    );
    var deviceId = await _storage.read(key: storageDeviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = _uuid.v4();
      await _storage.write(key: storageDeviceIdKey, value: deviceId);
    }
    final packageInfo = await _packageInfoOrNull();
    return AuthDevicePayload(
      platform: platform,
      deviceId: deviceId,
      deviceLabel: platform,
      appVersion: packageInfo?.version,
      buildNumber: packageInfo?.buildNumber,
    );
  }

  static String platformName({TargetPlatform? platform, bool? isWeb}) {
    if (isWeb ?? kIsWeb) return 'web';
    return switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'linux',
    };
  }

  Future<PackageInfo?> _packageInfoOrNull() async {
    try {
      return await _packageInfoLoader();
    } catch (_) {
      return null;
    }
  }
}
