class SaveWarrantyRequest {
  final String userEmail;
  final String receiptNumber;
  final List<String> imagesBase64;

  SaveWarrantyRequest({
    required this.userEmail,
    required this.receiptNumber,
    required this.imagesBase64,
  });

  Map<String, dynamic> toJson() {
    return {
      'user': userEmail,
      'receipt': receiptNumber,
      'images': imagesBase64,
    };
  }
}

class CheckWarrantyRequest {
  final String receiptNumber;

  CheckWarrantyRequest({required this.receiptNumber});

  Map<String, dynamic> toJson() {
    return {'receipt_number': receiptNumber};
  }
}
