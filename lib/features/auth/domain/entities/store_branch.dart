class StoreBranch {
  final String id;
  final String storeId;
  final String storeName;
  final String? transferAccountNumber;
  final String? transferAccountName;
  final String? transferBankName;

  const StoreBranch({
    required this.id,
    required this.storeId,
    required this.storeName,
    this.transferAccountNumber,
    this.transferAccountName,
    this.transferBankName,
  });

  factory StoreBranch.fromJson(Map<String, dynamic> json) {
    return StoreBranch(
      id: json['id']?.toString() ?? '',
      storeId: json['storeId']?.toString() ?? '',
      storeName: json['storeName']?.toString() ?? '',
      transferAccountNumber: json['transferAccountNumber']?.toString(),
      transferAccountName: json['transferAccountName']?.toString(),
      transferBankName: json['transferBankName']?.toString(),
    );
  }

  String get displayName => '$storeId - $storeName';
}
