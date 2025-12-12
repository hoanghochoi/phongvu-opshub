import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../chat/domain/entities/sku_item.dart';

class SortSKUBubble extends StatefulWidget {
  final SKUItem skuItem;
  final Function(SKUItem) onCheckChanged;

  const SortSKUBubble({
    super.key,
    required this.skuItem,
    required this.onCheckChanged,
  });

  @override
  State<SortSKUBubble> createState() => _SortSKUBubbleState();
}

class _SortSKUBubbleState extends State<SortSKUBubble> {
  void _toggleCheck() {
    setState(() {
      widget.skuItem.isChecked = !widget.skuItem.isChecked;
    });
    widget.onCheckChanged(widget.skuItem);
  }

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

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // SKU row with tick icon
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'SKU: ${widget.skuItem.sku}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _toggleCheck,
                    child: Icon(
                      widget.skuItem.isChecked
                          ? Icons.check_circle
                          : Icons.check_circle_outline,
                      color: widget.skuItem.isChecked
                          ? Colors.green
                          : Colors.grey,
                      size: 28,
                    ),
                  ),
                ],
              ),
              if (widget.skuItem.name.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Tên: ${widget.skuItem.name}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
              if (widget.skuItem.serial.isNotEmpty) ...[
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _copyToClipboard(context, widget.skuItem.serial),
                  child: Row(
                    children: [
                      const Text(
                        'Serial: ',
                        style: TextStyle(fontSize: 13),
                      ),
                      Expanded(
                        child: Text(
                          widget.skuItem.serial,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (widget.skuItem.bin.isNotEmpty) ...[
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _copyToClipboard(context, widget.skuItem.bin),
                  child: Row(
                    children: [
                      const Text(
                        'Mã BIN: ',
                        style: TextStyle(fontSize: 13),
                      ),
                      Expanded(
                        child: Text(
                          widget.skuItem.bin,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (widget.skuItem.zone.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Zone: ${widget.skuItem.zone}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
              if (widget.skuItem.date.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Ngày nhập: ${widget.skuItem.date}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
