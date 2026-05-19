import 'dart:convert';

import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../domain/app_update_info.dart';

class AppUpdateService {
  AppUpdateService(this._apiClient);

  final ApiClient _apiClient;

  Future<AppUpdateCheckResult?> checkForUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
    final response = await _apiClient.get(ApiConstants.appVersionEndpoint);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final info = AppUpdateInfo.fromJson(payload);

    if (!info.hasUpdate(currentBuild) && !info.requiresUpdate(currentBuild)) {
      return null;
    }

    return AppUpdateCheckResult(
      currentVersion: packageInfo.version,
      currentBuild: currentBuild,
      updateInfo: info,
    );
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
