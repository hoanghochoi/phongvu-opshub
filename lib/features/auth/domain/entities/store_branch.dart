class StoreBranch {
  final String id;
  final String storeId;
  final String storeName;
  final String? areaCode;
  final String? areaName;
  final String? areaAbbreviation;
  final String? regionCode;
  final String? regionName;
  final String? regionAbbreviation;
  final String? transferAccountNumber;
  final String? transferAccountName;
  final String? transferBankName;
  final String? transferBankBin;
  final String? mapVietinUsername;
  final bool hasMapVietinPassword;
  final int userCount;

  const StoreBranch({
    required this.id,
    required this.storeId,
    required this.storeName,
    this.areaCode,
    this.areaName,
    this.areaAbbreviation,
    this.regionCode,
    this.regionName,
    this.regionAbbreviation,
    this.transferAccountNumber,
    this.transferAccountName,
    this.transferBankName,
    this.transferBankBin,
    this.mapVietinUsername,
    this.hasMapVietinPassword = false,
    this.userCount = 0,
  });

  factory StoreBranch.fromJson(Map<String, dynamic> json) {
    return StoreBranch(
      id: json['id']?.toString() ?? '',
      storeId: json['storeId']?.toString() ?? '',
      storeName: json['storeName']?.toString() ?? '',
      areaCode: json['areaCode']?.toString(),
      areaName: json['areaName']?.toString(),
      areaAbbreviation: json['areaAbbreviation']?.toString(),
      regionCode: json['regionCode']?.toString(),
      regionName: json['regionName']?.toString(),
      regionAbbreviation: json['regionAbbreviation']?.toString(),
      transferAccountNumber: json['transferAccountNumber']?.toString(),
      transferAccountName: json['transferAccountName']?.toString(),
      transferBankName: json['transferBankName']?.toString(),
      transferBankBin: json['transferBankBin']?.toString(),
      mapVietinUsername: json['mapVietinUsername']?.toString(),
      hasMapVietinPassword:
          json['hasMapVietinPassword'] == true ||
          json['hasMapVietinPassword'] == 'true',
      userCount: int.tryParse(json['userCount']?.toString() ?? '') ?? 0,
    );
  }

  String get displayName => '$storeId - $storeName';

  String get regionAreaLabel {
    final region = regionAbbreviation ?? regionCode;
    final area = areaAbbreviation ?? areaCode;
    if ((region ?? '').isEmpty && (area ?? '').isEmpty) {
      return 'Chưa gán Vùng/Miền';
    }
    if (region == area) return region!;
    return [
      area,
      region,
    ].whereType<String>().where((v) => v.isNotEmpty).join(' / ');
  }

  Map<String, dynamic> toAdminJson() {
    return {
      'storeId': storeId,
      'storeName': storeName,
      'areaCode': areaCode,
      'transferAccountNumber': transferAccountNumber,
      'transferAccountName': transferAccountName,
      'transferBankName': transferBankName,
      'transferBankBin': transferBankBin,
      'mapVietinUsername': mapVietinUsername,
    };
  }
}
