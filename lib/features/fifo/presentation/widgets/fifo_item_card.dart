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
        ? AppColors.successOf(context)
        : isWrong
        ? AppColors.errorOf(context)
        : AppColors.neutral700Of(context);

    final items = _parseResultJson(log.resultJson);
    final hasItems = items.isNotEmpty;

    return GestureDetector(
      onTap: hasItems ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color:
              Theme.of(context).cardTheme.color ??
              Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: isExpanded
              ? Border.all(
                  color: AppColors.infoOf(context).withValues(alpha: 0.3),
                  width: 1.5,
                )
              : Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      log.query,
                      style: AppTextStyles.labelL.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (hasItems)
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppColors.neutral500Of(context),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  log.userName ?? log.userEmail ?? 'Chưa rõ',
                  if ((log.storeId ?? '').isNotEmpty) log.storeId!,
                  if (dateStr.isNotEmpty) dateStr,
                ].join(' • '),
                style: AppTextStyles.bodyS.copyWith(
                  color: AppColors.neutral600Of(context),
                ),
              ),
              if (log.result != null && log.result!.isNotEmpty) ...[
                const SizedBox(height: 10),
                AppStatusChip(
                  label:
                      '${log.type == 'FIFO_CHECK' ? 'Kiểm tra' : 'Sắp xếp'} • ${log.result!}',
                  color: resultColor,
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

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.neutral50Of(context),
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        border: fifo == 'yes'
            ? Border.all(
                color: AppColors.successOf(context).withValues(alpha: 0.30),
              )
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
                  color: AppColors.neutral500Of(context),
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
                    color: AppColors.successOf(context).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Text(
                    'Đúng FIFO',
                    style: AppTextStyles.captionBold.copyWith(
                      color: AppColors.successOf(context),
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
