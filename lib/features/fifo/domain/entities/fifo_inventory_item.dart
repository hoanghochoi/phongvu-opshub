class FifoInventoryItem {
  final String id;
  final String srCode;
  final String sku;
  final String skuName;
  final String serialNumber;
  final String bin;
  final String zone;
  final String importDate;
  final int count;
  final bool exported;
  final bool isFifo;

  const FifoInventoryItem({
    required this.id,
    required this.srCode,
    required this.sku,
    required this.skuName,
    required this.serialNumber,
    required this.bin,
    required this.zone,
    required this.importDate,
    required this.count,
    required this.exported,
    required this.isFifo,
  });

  factory FifoInventoryItem.fromJson(Map<String, dynamic> json) {
    return FifoInventoryItem(
      id: json['id']?.toString() ?? '',
      srCode: json['sr_code']?.toString() ?? json['srCode']?.toString() ?? '',
      sku: json['sku']?.toString() ?? '',
      skuName:
          json['sku_name']?.toString() ?? json['skuName']?.toString() ?? '',
      serialNumber:
          json['serial_number']?.toString() ??
          json['serialNumber']?.toString() ??
          '',
      bin: json['bin']?.toString() ?? '',
      zone: json['zone']?.toString() ?? '',
      importDate:
          json['import_date']?.toString() ??
          json['importDate']?.toString() ??
          '',
      count: int.tryParse(json['count']?.toString() ?? '') ?? 1,
      exported: json['exported'] == true || json['exported'] == 'true',
      isFifo: json['fifo'] == 'yes' || json['fifo'] == true,
    );
  }
}
