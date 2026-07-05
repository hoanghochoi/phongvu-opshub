import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../domain/entities/fifo_check_entry.dart';
import 'fifo_sku_item_card.dart';

class FifoCheckEntryCard extends StatelessWidget {
  final FifoCheckEntry entry;

  // Cached formatters - avoid recreating on every build
  static final DateFormat _timeFormat = DateFormat('HH:mm');
  static final RegExp _resultRegex = RegExp(
    r'(Serial|Mã BIN):\s*(\S+)',
    caseSensitive: false,
  );
  static final RegExp _inputRegex = RegExp(
    r'(SKU|sku):\s*(\S+)',
    caseSensitive: false,
  );

  const FifoCheckEntryCard({super.key, required this.entry});

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    AppToast.show(
      context,
      SnackBar(
        content: Text('Đã sao chép: $text'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Build rich text with highlighted Serial and BIN for FIFO result entries.
  Widget _buildResultEntry(BuildContext context) {
    final content = entry.content;
    final spans = <TextSpan>[];

    // Regex to match Serial: followed by value and BIN: followed by value
    final regex = _resultRegex;
    int lastIndex = 0;

    for (final match in regex.allMatches(content)) {
      // Add normal text before match
      if (match.start > lastIndex) {
        spans.add(
          TextSpan(
            text: content.substring(lastIndex, match.start),
            style: AppTextStyles.bodyM.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        );
      }

      // Add label (Serial: or BIN:)
      spans.add(
        TextSpan(
          text: '${match.group(1)!}: ',
          style: AppTextStyles.labelM.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );

      // Add highlighted value (selectable)
      final value = match.group(2)!;

      spans.add(
        TextSpan(
          text: value,
          style: AppTextStyles.labelM.copyWith(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
        ),
      );

      lastIndex = match.end;
    }

    // Add remaining text
    if (lastIndex < content.length) {
      spans.add(
        TextSpan(
          text: content.substring(lastIndex),
          style: AppTextStyles.bodyM.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );
    }

    // Use SelectableText.rich to allow text selection while keeping tap recognizers
    return SelectableText.rich(TextSpan(children: spans));
  }

  // Build rich text with highlighted SKU for staff input entries.
  Widget _buildInputEntry(BuildContext context) {
    final content = entry.content;

    // Regex to match SKU: followed by value
    final regex = _inputRegex;
    final matches = regex.allMatches(content).toList();

    // If no SKU found, return plain selectable text
    if (matches.isEmpty) {
      return SelectableText(
        content,
        style: AppTextStyles.bodyM.copyWith(color: AppColors.surface),
      );
    }

    // Build rich text with SKU highlighting
    final spans = <TextSpan>[];
    int lastIndex = 0;

    for (final match in matches) {
      // Add normal text before match
      if (match.start > lastIndex) {
        spans.add(
          TextSpan(
            text: content.substring(lastIndex, match.start),
            style: AppTextStyles.bodyM.copyWith(color: AppColors.surface),
          ),
        );
      }

      // Add label (SKU:)
      spans.add(
        TextSpan(
          text: '${match.group(1)!}: ',
          style: AppTextStyles.labelM.copyWith(color: AppColors.surface),
        ),
      );

      // Add highlighted value (selectable)
      final value = match.group(2)!;

      spans.add(
        TextSpan(
          text: value,
          style: AppTextStyles.labelM.copyWith(
            color: AppColors.warning,
            decoration: TextDecoration.underline,
          ),
        ),
      );

      lastIndex = match.end;
    }

    // Add remaining text
    if (lastIndex < content.length) {
      spans.add(
        TextSpan(
          text: content.substring(lastIndex),
          style: AppTextStyles.bodyM.copyWith(color: AppColors.surface),
        ),
      );
    }

    // Use SelectableText.rich to allow text selection while keeping tap recognizers
    return SelectableText.rich(TextSpan(children: spans));
  }

  @override
  Widget build(BuildContext context) {
    final timeFormat = _timeFormat;

    // If result entry has SKU items, display FIFO SKU cards.
    if (!entry.isUserInput &&
        entry.skuItems != null &&
        entry.skuItems!.isNotEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Show result text above SKU cards (e.g., "Đúng FIFO").
              if (entry.content.isNotEmpty &&
                  !entry.content.contains('SKU:')) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: entry.content.contains('✅')
                        ? (Theme.of(context).brightness == Brightness.dark
                              ? AppColors.success.withValues(alpha: 0.15)
                              : AppColors.success.withValues(alpha: 0.08))
                        : entry.content.contains('❌')
                        ? (Theme.of(context).brightness == Brightness.dark
                              ? AppColors.error.withValues(alpha: 0.15)
                              : AppColors.error.withValues(alpha: 0.08))
                        : (Theme.of(context).brightness == Brightness.dark
                              ? AppColors.darkNeutral100
                              : AppColors.neutral200),
                    borderRadius: BorderRadius.circular(
                      AppLayoutTokens.cardRadius,
                    ),
                    border: Border.all(
                      color: entry.content.contains('✅')
                          ? AppColors.success
                          : entry.content.contains('❌')
                          ? AppColors.error
                          : (Theme.of(context).brightness == Brightness.dark
                                ? AppColors.neutral700
                                : AppColors.neutral400),
                    ),
                  ),
                  child: Text(
                    entry.content,
                    style: AppTextStyles.labelL.copyWith(
                      color: entry.content.contains('✅')
                          ? AppColors.success
                          : entry.content.contains('❌')
                          ? AppColors.error
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
              // Checked item's FIFO SKU cards.
              ...entry.skuItems!.map(
                (skuItem) => FifoSkuItemCard(
                  skuItem: skuItem,
                  onCheckChanged: (item) {
                    // State is managed in SKUItem.isChecked
                  },
                ),
              ),
              // FIFO Suggestion section
              if (entry.suggestedItems != null &&
                  entry.suggestedItems!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.warning.withValues(alpha: 0.15)
                        : AppColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(
                      AppLayoutTokens.cardRadius,
                    ),
                    border: Border.all(color: AppColors.warning, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            color: AppColors.warning,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Gợi ý — Sản phẩm cần lấy trước:',
                              style: AppTextStyles.labelM.copyWith(
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...entry.suggestedItems!.map(
                        (skuItem) => FifoSkuItemCard(
                          skuItem: skuItem,
                          onCheckChanged: (item) {},
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 4),
              // Timestamp
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  timeFormat.format(entry.timestamp),
                  style: AppTextStyles.caption.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Default entry card for staff inputs or text-only FIFO results.
    return Align(
      alignment: entry.isUserInput
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: entry.isUserInput
              ? Theme.of(context).colorScheme.primary
              : (Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkNeutral100
                    : AppColors.neutral300),
          borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nội dung kiểm tra FIFO.
            SelectionArea(
              child: entry.isUserInput
                  ? _buildInputEntry(context)
                  : _buildResultEntry(context),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeFormat.format(entry.timestamp),
                  style: AppTextStyles.caption.copyWith(
                    color: entry.isUserInput
                        ? AppColors.surface.withValues(alpha: 0.70)
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                // Nút copy toàn bộ cho kết quả FIFO.
                if (!entry.isUserInput) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _copyToClipboard(context, entry.content),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.copy,
                        size: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.check_circle,
                    size: 14,
                    color: AppColors.success,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
