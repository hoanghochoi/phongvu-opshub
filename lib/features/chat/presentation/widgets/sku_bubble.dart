import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../app/theme/app_colors.dart';
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
        content: Text('Đã sao chép: $text'),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.skuItem.isChecked
            ? (isDark ? Colors.green.withValues(alpha: 0.15) : Colors.green[50])
            : (isDark ? AppColors.darkCard : Colors.grey[50]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.skuItem.isChecked
              ? (isDark ? Colors.green[700]! : Colors.green[400]!)
              : (isDark ? AppColors.neutral700 : Colors.grey[300]!),
          width: widget.skuItem.isChecked ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with SKU and check button
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      'SKU: ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: onSurfaceVariant,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        widget.skuItem.sku,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: primary,
                        ),
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
                    color: widget.skuItem.isChecked ? Colors.green : onSurfaceVariant,
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
              style: TextStyle(
                fontSize: 13,
                color: onSurface,
              ),
            ),
            const SizedBox(height: 6),
          ],

          // Serial (tap to copy)
          if (widget.skuItem.serial.isNotEmpty) ...[
            GestureDetector(
              onTap: () => _copyToClipboard(context, widget.skuItem.serial),
              child: Row(
                children: [
                  Text(
                    'Serial: ',
                    style: TextStyle(
                      fontSize: 13,
                      color: onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      widget.skuItem.serial,
                      style: TextStyle(
                        fontSize: 13,
                        color: primary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  Icon(Icons.copy, size: 14, color: onSurfaceVariant.withValues(alpha: 0.5)),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],

          // BIN (tap to copy)
          if (widget.skuItem.bin.isNotEmpty) ...[
            GestureDetector(
              onTap: () => _copyToClipboard(context, widget.skuItem.bin),
              child: Row(
                children: [
                  Text(
                    'Mã BIN: ',
                    style: TextStyle(
                      fontSize: 13,
                      color: onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      widget.skuItem.bin,
                      style: TextStyle(
                        fontSize: 13,
                        color: primary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  Icon(Icons.copy, size: 14, color: onSurfaceVariant.withValues(alpha: 0.5)),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],

          // Zone
          if (widget.skuItem.zone.isNotEmpty) ...[
            Text(
              'Zone: ${widget.skuItem.zone}',
              style: TextStyle(
                fontSize: 13,
                color: onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
          ],

          // Date
          if (widget.skuItem.date.isNotEmpty)
            Text(
              'Ngày nhập: ${widget.skuItem.date}',
              style: TextStyle(
                fontSize: 13,
                color: onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
