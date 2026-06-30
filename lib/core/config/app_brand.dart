import '../constants/api_constants.dart';

class AppBrand {
  AppBrand._();

  static const _explicitEnvironment = String.fromEnvironment('APP_ENV');

  static const productionTitle = 'PhongVu OpsHub';
  static const stagingTitle = 'PhongVu OpsHub Staging';

  static const productionLogoAsset = 'assets/icon/source/app_icon_master.png';
  static const productionPaddedLogoAsset =
      'assets/icon/source/app_icon_padded.png';
  static const stagingLogoAsset =
      'assets/icon/staging/source/app_icon_master.png';
  static const stagingPaddedLogoAsset =
      'assets/icon/staging/source/app_icon_padded.png';

  static bool get isStaging => isStagingEnvironment(
    apiBaseUrl: ApiConstants.baseUrl,
    appEnv: _explicitEnvironment,
  );

  static String get title =>
      titleFor(apiBaseUrl: ApiConstants.baseUrl, appEnv: _explicitEnvironment);

  static String get logoAsset => logoAssetFor(
    apiBaseUrl: ApiConstants.baseUrl,
    appEnv: _explicitEnvironment,
  );

  static String get paddedLogoAsset => paddedLogoAssetFor(
    apiBaseUrl: ApiConstants.baseUrl,
    appEnv: _explicitEnvironment,
  );

  static bool isStagingEnvironment({
    required String apiBaseUrl,
    String appEnv = '',
  }) {
    final explicit = appEnv.trim().toLowerCase();
    if (explicit.isNotEmpty) {
      return explicit == 'staging' || explicit == 'staging_build';
    }
    final normalized = apiBaseUrl.trim().toLowerCase();
    return normalized.contains('opshub-staging') ||
        normalized.contains('/staging');
  }

  static String titleFor({required String apiBaseUrl, String appEnv = ''}) {
    return isStagingEnvironment(apiBaseUrl: apiBaseUrl, appEnv: appEnv)
        ? stagingTitle
        : productionTitle;
  }

  static String logoAssetFor({required String apiBaseUrl, String appEnv = ''}) {
    return isStagingEnvironment(apiBaseUrl: apiBaseUrl, appEnv: appEnv)
        ? stagingLogoAsset
        : productionLogoAsset;
  }

  static String paddedLogoAssetFor({
    required String apiBaseUrl,
    String appEnv = '',
  }) {
    return isStagingEnvironment(apiBaseUrl: apiBaseUrl, appEnv: appEnv)
        ? stagingPaddedLogoAsset
        : productionPaddedLogoAsset;
  }
}
