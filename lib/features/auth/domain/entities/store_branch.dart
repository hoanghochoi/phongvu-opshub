class StoreBranch {
  final String id;
  final String storeId;
  final String storeName;
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

  Map<String, dynamic> toAdminJson() {
    return {
      'storeId': storeId,
      'storeName': storeName,
      'transferAccountNumber': transferAccountNumber,
      'transferAccountName': transferAccountName,
      'transferBankName': transferBankName,
      'transferBankBin': transferBankBin,
      'mapVietinUsername': mapVietinUsername,
    };
  }
}
