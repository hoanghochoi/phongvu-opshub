import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../chat/domain/entities/sku_group.dart';
import '../../../chat/domain/entities/sku_item.dart';

class SortSKUGroupWidget extends StatelessWidget {
  final SKUGroup group;
  final Function(SKUItem) onItemCheckChanged;

  const SortSKUGroupWidget({
    super.key,
    required this.group,
    required this.onItemCheckChanged,
  });

  Future<void> _copyToClipboard(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã sao chép: $text'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _toggleGroupCheck() {
    final newState = !group.isFullyChecked;
    for (var item in group.items) {
      item.isChecked = newState;
      onItemCheckChanged(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = group.isFullyChecked ? Colors.green[100] : Colors.yellow[100];
    final headerColor = group.isFullyChecked ? Colors.green : Colors.orange[800];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group header
          Container(
            padding: const EdgeInsets.all(12),
            color: backgroundColor,
            child: Row(
              children: [
                // Group tick button
                InkWell(
                  onTap: _toggleGroupCheck,
                  child: Icon(
                    group.isFullyChecked ? Icons.check_circle : Icons.check_circle_outline,
                    color: group.isFullyChecked ? Colors.green : Colors.grey,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  group.isFullyChecked ? Icons.inventory_2 : Icons.access_time,
                  color: headerColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SKU: ${group.sku}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: headerColor,
                        ),
                      ),
                      if (group.name.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          group.name,
                          style: TextStyle(
                            fontSize: 13,
                            color: headerColor?.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${group.checkedItems}/${group.totalItems}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: headerColor,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Items list
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            itemCount: group.items.length,
            separatorBuilder: (context, index) => const Divider(height: 16),
            itemBuilder: (context, index) {
              final item = group.items[index];
              return _buildItem(context, item);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, SKUItem item) {
    return SelectionArea(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Checkbox
          InkWell(
            onTap: () {
              item.isChecked = !item.isChecked;
              onItemCheckChanged(item);
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              child: Icon(
                item.isChecked ? Icons.check_box : Icons.check_box_outline_blank,
                color: item.isChecked ? Colors.green : Colors.grey,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Item details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.serial.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () => _copyToClipboard(context, item.serial),
                    child: Row(
                      children: [
                        const Text(
                          'Serial: ',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        Expanded(
                          child: Text(
                            item.serial,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                if (item.bin.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () => _copyToClipboard(context, item.bin),
                    child: Row(
                      children: [
                        const Text(
                          'Mã BIN: ',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        Expanded(
                          child: Text(
                            item.bin,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                if (item.zone.isNotEmpty)
                  Text(
                    'Zone: ${item.zone}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                if (item.date.isNotEmpty)
                  Text(
                    'Ngày nhập: ${item.date}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
