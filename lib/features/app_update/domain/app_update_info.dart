class AppUpdateInfo {
  const AppUpdateInfo({
    required this.platform,
    required this.latestVersion,
    required this.latestBuild,
    required this.minSupportedBuild,
    required this.updateUrl,
    required this.releaseNotes,
    required this.forceUpdate,
  });

  final String platform;
  final String latestVersion;
  final int latestBuild;
  final int minSupportedBuild;
  final String updateUrl;
  final String releaseNotes;
  final bool forceUpdate;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      platform: json['platform']?.toString() ?? '',
      latestVersion: json['latestVersion']?.toString() ?? '',
      latestBuild: _readInt(json['latestBuild']),
      minSupportedBuild: _readInt(json['minSupportedBuild']),
      updateUrl: json['updateUrl']?.toString() ?? '',
      releaseNotes: json['releaseNotes']?.toString() ?? '',
      forceUpdate: json['forceUpdate'] == true,
    );
  }

  bool hasUpdate(int currentBuild) => latestBuild > currentBuild;

  bool requiresUpdate(int currentBuild) {
    return minSupportedBuild > currentBuild ||
        (forceUpdate && hasUpdate(currentBuild));
  }

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
