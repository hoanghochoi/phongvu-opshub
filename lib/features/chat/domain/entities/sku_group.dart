import 'sku_item.dart';

class SKUGroup {
  final String sku;
  final String name;
  final List<SKUItem> items;

  SKUGroup({
    required this.sku,
    required this.name,
    required this.items,
  });

  bool get isFullyChecked => items.isNotEmpty && items.every((item) => item.isChecked);

  int get totalItems => items.length;

  int get checkedItems => items.where((item) => item.isChecked).length;
}
