class VietQrTransfer {
  final String bankBin;
  final String bankName;
  final String accountNumber;
  final String accountName;
  final int amount;
  final String transferContent;
  final String qrPayload;

  const VietQrTransfer({
    required this.bankBin,
    required this.bankName,
    required this.accountNumber,
    required this.accountName,
    required this.amount,
    required this.transferContent,
    required this.qrPayload,
  });

  factory VietQrTransfer.fromJson(Map<String, dynamic> json) {
    return VietQrTransfer(
      bankBin: json['bankBin'] as String? ?? '',
      bankName: json['bankName'] as String? ?? json['bankBin'] as String? ?? '',
      accountNumber: json['accountNumber'] as String? ?? '',
      accountName: json['accountName'] as String? ?? '',
      amount: json['amount'] as int? ?? 0,
      transferContent: json['transferContent'] as String? ?? '',
      qrPayload: json['qrPayload'] as String? ?? '',
    );
  }
}
