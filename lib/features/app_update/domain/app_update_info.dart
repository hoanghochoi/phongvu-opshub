class AppUpdateInfo {
  const AppUpdateInfo({
    required this.platform,
    required this.latestVersion,
    required this.latestBuild,
    required this.minSupportedBuild,
    required this.updateUrl,
    required this.packageUrl,
    required this.packageSha256,
    required this.packageSizeBytes,
    required this.packageType,
    required this.installerArgs,
    required this.releaseNotes,
    required this.forceUpdate,
  });

  final String platform;
  final String latestVersion;
  final int latestBuild;
  final int minSupportedBuild;
  final String updateUrl;
  final String packageUrl;
  final String packageSha256;
  final int packageSizeBytes;
  final String packageType;
  final List<String> installerArgs;
  final String releaseNotes;
  final bool forceUpdate;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    final updateUrl = json['updateUrl']?.toString() ?? '';
    return AppUpdateInfo(
      platform: json['platform']?.toString() ?? '',
      latestVersion: json['latestVersion']?.toString() ?? '',
      latestBuild: _readInt(json['latestBuild']),
      minSupportedBuild: _readInt(json['minSupportedBuild']),
      updateUrl: updateUrl,
      packageUrl: json['packageUrl']?.toString() ?? updateUrl,
      packageSha256: json['packageSha256']?.toString().toLowerCase() ?? '',
      packageSizeBytes: _readInt(json['packageSizeBytes']),
      packageType: json['packageType']?.toString() ?? '',
      installerArgs: _readStringList(json['installerArgs']),
      releaseNotes: json['releaseNotes']?.toString() ?? '',
      forceUpdate: json['forceUpdate'] == true,
    );
  }

  bool hasUpdate(int currentBuild) => latestBuild > currentBuild;

  bool requiresUpdate(int currentBuild) {
    return minSupportedBuild > currentBuild ||
        (forceUpdate && hasUpdate(currentBuild));
  }

  bool get hasSelfUpdatePackage {
    return packageUrl.trim().isNotEmpty &&
        packageSha256.trim().isNotEmpty &&
        packageSizeBytes > 0;
  }

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static List<String> _readStringList(Object? value) {
    if (value is List) {
      return value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }
}
