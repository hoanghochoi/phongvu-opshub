import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../data/repositories/fifo_log_repository.dart';

class FifoItemCard extends StatelessWidget {
  final FifoLogItem log;
  final bool isExpanded;
  final VoidCallback onTap;

  const FifoItemCard({
    super.key,
    required this.log,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(log.createdAt);
    final dateStr = date != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal())
        : log.createdAt;

    final isCorrect = log.result?.contains('Đúng') ?? false;
    final isWrong =
        log.result?.contains('Sai') ?? log.result?.contains('Chưa') ?? false;
    final resultColor = isCorrect
        ? AppColors.success
        : isWrong
        ? AppColors.error
        : AppColors.neutral700;

    final items = _parseResultJson(log.resultJson);
    final hasItems = items.isNotEmpty;

    return GestureDetector(
      onTap: hasItems ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color:
              Theme.of(context).cardTheme.color ??
              Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
          border: isExpanded
              ? Border.all(
                  color: AppColors.info.withValues(alpha: 0.3),
                  width: 1.5,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: User + Time
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.info.withValues(alpha: 0.15),
                    child: Text(
                      (log.userName ?? log.userEmail ?? '?')[0].toUpperCase(),
                      style: AppTextStyles.labelM.copyWith(
                        color: AppColors.info,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log.userName ?? log.userEmail ?? 'Chưa rõ',
                          style: AppTextStyles.labelM.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        if (log.storeName != null)
                          Text(
                            '${log.storeId ?? ''} - ${log.storeName}',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.neutral500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    dateStr,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.neutral500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Query + Item count + expand arrow
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkChipBg
                          : AppColors.neutral100,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: Text(
                      'Truy vấn',
                      style: AppTextStyles.caption.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      log.query,
                      style: AppTextStyles.labelM.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (hasItems) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        '${items.length} sản phẩm',
                        style: AppTextStyles.captionBold.copyWith(
                          color: AppColors.info,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 20,
                      color: AppColors.neutral500,
                    ),
                  ],
                ],
              ),
              // Result
              if (log.result != null && log.result!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: resultColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        'Kết quả',
                        style: AppTextStyles.caption.copyWith(
                          color: resultColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        log.result!,
                        style: AppTextStyles.bodyS.copyWith(
                          color: resultColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              // Expanded detail: show each item
              if (isExpanded && hasItems) ...[
                const SizedBox(height: 10),
                Divider(height: 1, color: Theme.of(context).dividerColor),
                const SizedBox(height: 8),
                ...items.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  return _buildItemDetail(context, item, idx + 1);
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Parse resultJson into a list of maps
  List<Map<String, dynamic>> _parseResultJson(dynamic resultJson) {
    if (resultJson == null) return [];
    if (resultJson is List) {
      return resultJson.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  /// Build a single item detail row
  Widget _buildItemDetail(
    BuildContext context,
    Map<String, dynamic> item,
    int index,
  ) {
    final sku = item['sku']?.toString() ?? '';
    final skuName = item['sku_name']?.toString() ?? '';
    final serial = item['serial_number']?.toString() ?? '';
    final bin = item['bin']?.toString() ?? '';
    final importDate = item['import_date']?.toString() ?? '';
    final fifo = item['fifo']?.toString();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkNeutral100 : AppColors.neutral50,
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        border: fifo == 'yes'
            ? Border.all(color: AppColors.success.withValues(alpha: 0.30))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SKU Name
          Row(
            children: [
              Text(
                '#$index',
                style: AppTextStyles.captionBold.copyWith(
                  color: AppColors.neutral500,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  skuName.isNotEmpty ? skuName : sku,
                  style: AppTextStyles.bodyS.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (fifo == 'yes')
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Text(
                    'Đúng FIFO',
                    style: AppTextStyles.captionBold.copyWith(
                      color: AppColors.success,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // Serial + BIN + Date
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (serial.isNotEmpty) AppInfoChip(Icons.qr_code, serial),
              if (bin.isNotEmpty) AppInfoChip(Icons.inventory_2_outlined, bin),
              if (importDate.isNotEmpty)
                AppInfoChip(Icons.calendar_today, importDate),
            ],
          ),
        ],
      ),
    );
  }
}
