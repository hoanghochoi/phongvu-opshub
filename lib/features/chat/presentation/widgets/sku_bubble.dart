import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/entities/sku_item.dart';

class SKUBubble extends StatefulWidget {
  final SKUItem skuItem;
  final Function(SKUItem) onCheckChanged;

  const SKUBubble({
    super.key,
    required this.skuItem,
    required this.onCheckChanged,
  });

  @override
  State<SKUBubble> createState() => _SKUBubbleState();
}

class _SKUBubbleState extends State<SKUBubble> {
  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã copy: $text'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _toggleCheck() {
    setState(() {
      widget.skuItem.isChecked = !widget.skuItem.isChecked;
    });
    widget.onCheckChanged(widget.skuItem);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.skuItem.isChecked ? Colors.green : Colors.grey[300]!,
          width: widget.skuItem.isChecked ? 2 : 1,
        ),
      ),
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with SKU and check button
            Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Text(
                      'SKU: ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      widget.skuItem.sku,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
              // Check button
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
            const SizedBox(height: 8),

            // Name
            if (widget.skuItem.name.isNotEmpty) ...[
            Text(
              'Tên: ${widget.skuItem.name}',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
              ),
            ),
              const SizedBox(height: 6),
            ],

            // Serial (selectable with copy on tap)
            if (widget.skuItem.serial.isNotEmpty) ...[
            Row(
              children: [
                const Text(
                  'Serial: ',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _copyToClipboard(context, widget.skuItem.serial),
                    child: Text(
                      widget.skuItem.serial,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],

          // BIN (selectable with copy on tap)
          if (widget.skuItem.bin.isNotEmpty) ...[
            Row(
              children: [
                const Text(
                  'Mã BIN: ',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _copyToClipboard(context, widget.skuItem.bin),
                    child: Text(
                      widget.skuItem.bin,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],

          // Zone
          if (widget.skuItem.zone.isNotEmpty) ...[
            Text(
              'Zone: ${widget.skuItem.zone}',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
              ),
              ),
              const SizedBox(height: 6),
            ],

            // Date
            if (widget.skuItem.date.isNotEmpty)
              Text(
              'Ngày nhập: ${widget.skuItem.date}',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
              ),
              ),
          ],
        ),
      ),
    );
  }
}
