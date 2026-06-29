import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../fifo_check/domain/entities/sku_group.dart';
import '../../../fifo_check/domain/entities/sku_item.dart';

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

  // Tính màu cho từng item dựa vào ngày nhập kho
  Color _getItemBackgroundColor(SKUItem item) {
    if (item.isChecked) return AppColors.success.withValues(alpha: 0.08);
    if (item.date.isEmpty) return AppColors.neutral50;

    final itemDate = DateFormatter.tryParse(item.date);
    if (itemDate == null) return AppColors.neutral50;

    final daysDiff = DateTime.now().difference(itemDate).inDays;
    final ratio = (daysDiff / 60).clamp(0.0, 1.0);

    // Gradient từ xanh nhạt (mới) -> cam nhạt (cũ)
    return Color.lerp(
      AppColors.info.withValues(alpha: 0.08),
      AppColors.warning.withValues(alpha: 0.18),
      ratio,
    )!;
  }

  // Tính màu border cho item
  Color _getItemBorderColor(SKUItem item) {
    if (item.isChecked) return AppColors.success;
    if (item.date.isEmpty) return AppColors.neutral200;

    final itemDate = DateFormatter.tryParse(item.date);
    if (itemDate == null) return AppColors.neutral200;

    final daysDiff = DateTime.now().difference(itemDate).inDays;
    final ratio = (daysDiff / 60).clamp(0.0, 1.0);

    // Gradient từ xanh đậm (mới) -> cam đậm (cũ)
    return Color.lerp(
      AppColors.info.withValues(alpha: 0.72),
      AppColors.warning.withValues(alpha: 0.85),
      ratio,
    )!;
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = group.isFullyChecked
        ? AppColors.success.withValues(alpha: 0.12)
        : AppColors.warning.withValues(alpha: 0.12);
    final headerColor = group.isFullyChecked
        ? AppColors.success
        : AppColors.warning;

    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              color: backgroundColor,
              child: Row(
                children: [
                  InkWell(
                    onTap: _toggleGroupCheck,
                    child: Icon(
                      group.isFullyChecked
                          ? Icons.check_circle
                          : Icons.check_circle_outline,
                      color: group.isFullyChecked
                          ? AppColors.success
                          : AppColors.neutral400,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    group.isFullyChecked
                        ? Icons.inventory_2
                        : Icons.access_time,
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
                          style: AppTextStyles.labelM.copyWith(
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
                            style: AppTextStyles.bodyS.copyWith(
                              color: headerColor.withValues(alpha: 0.8),
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
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(
                        AppLayoutTokens.cardRadius,
                      ),
                    ),
                    child: Text(
                      '${group.checkedItems}/${group.totalItems}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: AppTextStyles.labelS.copyWith(color: headerColor),
                    ),
                  ),
                ],
              ),
            ),
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
      ),
    );
  }

  Widget _buildItem(BuildContext context, SKUItem item) {
    return Container(
      decoration: BoxDecoration(
        color: _getItemBackgroundColor(item),
        border: Border.all(color: _getItemBorderColor(item), width: 1.5),
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
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
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: Icon(
                item.isChecked
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                color: item.isChecked
                    ? AppColors.success
                    : AppColors.neutral400,
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
                          style: AppTextStyles.bodyS.copyWith(
                            color: AppColors.neutral700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            item.serial,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: AppTextStyles.labelS.copyWith(
                              color: AppColors.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        Icon(Icons.copy, size: 14, color: AppColors.neutral300),
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
                          style: AppTextStyles.bodyS.copyWith(
                            color: AppColors.neutral700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            item.bin,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: AppTextStyles.labelS.copyWith(
                              color: AppColors.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        Icon(Icons.copy, size: 14, color: AppColors.neutral300),
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
                    style: AppTextStyles.bodyS.copyWith(
                      color: AppColors.neutral600,
                    ),
                  ),
                if (item.date.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Ngày nhập: ${item.date}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: AppTextStyles.bodyS.copyWith(
                      color: AppColors.neutral600,
                    ),
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
