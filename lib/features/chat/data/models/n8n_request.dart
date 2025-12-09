class N8nRequest {
  final String userEmail;
  final String sku;
  final String qty;
  final String timestamp;

  const N8nRequest({
    required this.userEmail,
    required this.sku,
    required this.qty,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'user_email': userEmail,
      'sku': sku,
      'qty': qty,
      'timestamp': timestamp,
    };
  }
}
