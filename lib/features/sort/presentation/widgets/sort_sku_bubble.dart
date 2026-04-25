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
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.skuItem.isChecked ? Colors.green[50] : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.skuItem.isChecked ? Colors.green[400]! : Colors.grey[300]!,
          width: widget.skuItem.isChecked ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SKU row with tick icon
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      'SKU: ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                    Flexible(
                      child: Text(
                        widget.skuItem.sku,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: _toggleCheck,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    widget.skuItem.isChecked
                        ? Icons.check_circle
                        : Icons.check_circle_outline,
                    color: widget.skuItem.isChecked ? Colors.green : Colors.grey,
                    size: 28,
                  ),
                ),
              ),
            ],
          ),
          if (widget.skuItem.name.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Tên: ${widget.skuItem.name}',
              style: TextStyle(fontSize: 13, color: Colors.grey[800]),
            ),
          ],
          if (widget.skuItem.serial.isNotEmpty) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => _copyToClipboard(context, widget.skuItem.serial),
              child: Row(
                children: [
                  Text(
                    'Serial: ',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.w500),
                  ),
                  Expanded(
                    child: Text(
                      widget.skuItem.serial,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  Icon(Icons.copy, size: 14, color: Colors.grey[400]),
                ],
              ),
            ),
          ],
          if (widget.skuItem.bin.isNotEmpty) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => _copyToClipboard(context, widget.skuItem.bin),
              child: Row(
                children: [
                  Text(
                    'Mã BIN: ',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.w500),
                  ),
                  Expanded(
                    child: Text(
                      widget.skuItem.bin,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  Icon(Icons.copy, size: 14, color: Colors.grey[400]),
                ],
              ),
            ),
          ],
          if (widget.skuItem.zone.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Zone: ${widget.skuItem.zone}',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
          if (widget.skuItem.date.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Ngày nhập: ${widget.skuItem.date}',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }
}
