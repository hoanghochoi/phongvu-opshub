class SKUItem {
  final String id;
  final String sku;
  final String name;
  final String serial;
  final String bin;
  final String zone;
  final String date;
  bool isChecked;

  SKUItem({
    required this.id,
    required this.sku,
    required this.name,
    required this.serial,
    required this.bin,
    required this.zone,
    required this.date,
    this.isChecked = false,
  });

  SKUItem copyWith({
    String? id,
    String? sku,
    String? name,
    String? serial,
    String? bin,
    String? zone,
    String? date,
    bool? isChecked,
  }) {
    return SKUItem(
      id: id ?? this.id,
      sku: sku ?? this.sku,
      name: name ?? this.name,
      serial: serial ?? this.serial,
      bin: bin ?? this.bin,
      zone: zone ?? this.zone,
      date: date ?? this.date,
      isChecked: isChecked ?? this.isChecked,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sku': sku,
    'name': name,
    'serial': serial,
    'bin': bin,
    'zone': zone,
    'date': date,
  };

  factory SKUItem.fromJson(Map<String, dynamic> json) => SKUItem(
    id: json['id'] ?? '',
    sku: json['sku'] ?? '',
    name: json['name'] ?? '',
    serial: json['serial'] ?? '',
    bin: json['bin'] ?? '',
    zone: json['zone'] ?? '',
    date: json['date'] ?? '',
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is SKUItem &&
        other.id == id &&
        other.sku == sku &&
        other.name == name &&
        other.serial == serial &&
        other.bin == bin &&
        other.zone == zone &&
        other.date == date &&
        other.isChecked == isChecked;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        sku.hashCode ^
        name.hashCode ^
        serial.hashCode ^
        bin.hashCode ^
        zone.hashCode ^
        date.hashCode ^
        isChecked.hashCode;
  }

  @override
  String toString() {
    return 'SKUItem(id: $id, sku: $sku, serial: $serial, bin: $bin, isChecked: $isChecked)';
  }
}
