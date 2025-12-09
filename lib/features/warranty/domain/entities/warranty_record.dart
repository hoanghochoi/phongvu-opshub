class WarrantyRecord {
  final String receiptNumber;
  final String driveFolderLink;
  final List<String> imageUrls;

  WarrantyRecord({
    required this.receiptNumber,
    required this.driveFolderLink,
    required this.imageUrls,
  });

  factory WarrantyRecord.fromJson(Map<String, dynamic> json) {
    return WarrantyRecord(
      receiptNumber: json['receipt_number'] as String? ?? '',
      driveFolderLink: json['drive_link'] as String? ?? '',
      imageUrls: (json['images'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}
