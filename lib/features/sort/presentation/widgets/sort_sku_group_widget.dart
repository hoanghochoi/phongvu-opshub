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

  // Parse date string theo nhiều format
  DateTime? _parseDate(String dateStr) {
    try {
      // Thử format DD/MM/YYYY hoặc DD-MM-YYYY
      if (dateStr.contains('/') || dateStr.contains('-')) {
        final separator = dateStr.contains('/') ? '/' : '-';
        final parts = dateStr.split(separator);
        if (parts.length == 3) {
          // Kiểm tra xem là DD/MM/YYYY hay YYYY-MM-DD
          if (parts[0].length == 4) {
            // YYYY-MM-DD
            return DateTime(
              int.parse(parts[0]), // year
              int.parse(parts[1]), // month
              int.parse(parts[2]), // day
            );
          } else {
            // DD/MM/YYYY
            return DateTime(
              int.parse(parts[2]), // year
              int.parse(parts[1]), // month
              int.parse(parts[0]), // day
            );
          }
        }
      }

      // Thử format timestamp (milliseconds)
      final timestamp = int.tryParse(dateStr);
      if (timestamp != null) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // Tính màu cho từng item dựa vào ngày nhập kho
  Color _getItemBackgroundColor(SKUItem item) {
    if (item.isChecked) return Colors.green[50]!;
    if (item.date.isEmpty) return Colors.grey[50]!;

    final itemDate = _parseDate(item.date);
    if (itemDate == null) return Colors.grey[50]!;

    final daysDiff = DateTime.now().difference(itemDate).inDays;
    final ratio = (daysDiff / 60).clamp(0.0, 1.0);

    // Gradient từ xanh nhạt (mới) -> cam nhạt (cũ)
    return Color.lerp(Colors.blue[50], Colors.deepOrange[100], ratio)!;
  }

  // Tính màu border cho item
  Color _getItemBorderColor(SKUItem item) {
    if (item.isChecked) return Colors.green[400]!;
    if (item.date.isEmpty) return Colors.grey[300]!;

    final itemDate = _parseDate(item.date);
    if (itemDate == null) return Colors.grey[300]!;

    final daysDiff = DateTime.now().difference(itemDate).inDays;
    final ratio = (daysDiff / 60).clamp(0.0, 1.0);

    // Gradient từ xanh đậm (mới) -> cam đậm (cũ)
    return Color.lerp(Colors.blue[400], Colors.deepOrange[400], ratio)!;
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = group.isFullyChecked
        ? Colors.green[100]
        : Colors.yellow[100];
    final headerColor = group.isFullyChecked
        ? Colors.green
        : Colors.orange[800];

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
                    group.isFullyChecked
                        ? Icons.check_circle
                        : Icons.check_circle_outline,
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${group.checkedItems}/${group.totalItems}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
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
            separatorBuilder: (context, index) => const SizedBox(height: 12),
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
    return Container(
      decoration: BoxDecoration(
        color: _getItemBackgroundColor(item),
        border: Border.all(color: _getItemBorderColor(item), width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Checkbox
          InkWell(
            onTap: () {
              item.isChecked = !item.isChecked;
              onItemCheckChanged(item);
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: Icon(
                item.isChecked
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                color: item.isChecked ? Colors.green : Colors.grey,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 8),
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
                        Text(
                          'Serial: ',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            item.serial,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        Icon(Icons.copy, size: 14, color: Colors.grey[400]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                if (item.bin.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () => _copyToClipboard(context, item.bin),
                    child: Row(
                      children: [
                        Text(
                          'Mã BIN: ',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            item.bin,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        Icon(Icons.copy, size: 14, color: Colors.grey[400]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                if (item.zone.isNotEmpty)
                  Text(
                    'Zone: ${item.zone}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                if (item.date.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Ngày nhập: ${item.date}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
