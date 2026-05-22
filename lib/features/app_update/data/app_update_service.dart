import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../domain/app_update_info.dart';

class AppUpdateService {
  AppUpdateService(this._apiClient);

  final ApiClient _apiClient;

  Future<AppUpdateCheckResult?> checkForUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
    await AppLogger.instance.info(
      'AppUpdate',
      'Update check started',
      context: {'platform': _platformName, 'currentBuild': currentBuild},
    );
    final response = await _apiClient.get(
      ApiConstants.appVersionEndpoint,
      queryParameters: {'platform': _platformName},
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final info = AppUpdateInfo.fromJson(payload);

    if (!info.hasUpdate(currentBuild) && !info.requiresUpdate(currentBuild)) {
      await AppLogger.instance.info(
        'AppUpdate',
        'No update available',
        context: {
          'platform': _platformName,
          'currentBuild': currentBuild,
          'latestBuild': info.latestBuild,
        },
      );
      return null;
    }

    await AppLogger.instance.info(
      'AppUpdate',
      'Update available',
      context: {
        'platform': _platformName,
        'currentBuild': currentBuild,
        'latestBuild': info.latestBuild,
        'required': info.requiresUpdate(currentBuild),
      },
    );

    return AppUpdateCheckResult(
      currentVersion: packageInfo.version,
      currentBuild: currentBuild,
      updateInfo: info,
    );
  }

  String get _platformName {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.windows => 'windows',
      _ => defaultTargetPlatform.name,
    };
  }
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.currentVersion,
    required this.currentBuild,
    required this.updateInfo,
  });

  final String currentVersion;
  final int currentBuild;
  final AppUpdateInfo updateInfo;

  bool get isRequired => updateInfo.requiresUpdate(currentBuild);
}
