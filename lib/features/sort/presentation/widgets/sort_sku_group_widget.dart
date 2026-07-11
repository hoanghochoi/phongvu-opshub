import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../fifo_check/domain/entities/sku_group.dart';
import '../../../fifo_check/domain/entities/sku_item.dart';

class SortSKUGroupWidget extends StatelessWidget {
  final SKUGroup group;
  final ValueChanged<SKUItem> onItemCheckChanged;

  const SortSKUGroupWidget({
    super.key,
    required this.group,
    required this.onItemCheckChanged,
  });

  void _toggleGroupCheck() {
    final newState = !group.isFullyChecked;
    for (final item in group.items) {
      onItemCheckChanged(item.copyWith(isChecked: newState));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SortGroupHeader(group: group, onToggleGroup: _toggleGroupCheck),
          const SizedBox(height: 8),
          for (var index = 0; index < group.items.length; index++)
            _SortItemCard(
              item: group.items[index],
              rank: index,
              total: group.totalItems,
              onItemCheckChanged: onItemCheckChanged,
            ),
        ],
      ),
    );
  }
}

class _SortGroupHeader extends StatelessWidget {
  final SKUGroup group;
  final VoidCallback onToggleGroup;

  const _SortGroupHeader({required this.group, required this.onToggleGroup});

  @override
  Widget build(BuildContext context) {
    final progressColor = group.isFullyChecked
        ? AppColors.success
        : AppColors.info;
    final toggleLabel = group.isFullyChecked
        ? 'Bỏ đánh dấu cả nhóm'
        : 'Đánh dấu cả nhóm';

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < AppLayoutTokens.compactBreakpoint;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SKU: ${group.sku}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: AppTextStyles.labelL.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
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
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        );
        final progress = AppStatusChip(
          label: '${group.checkedItems}/${group.totalItems}',
          color: progressColor,
          backgroundColor: progressColor.withValues(alpha: 0.10),
        );
        final toggle = Semantics(
          button: true,
          label: toggleLabel,
          child: InkWell(
            onTap: onToggleGroup,
            borderRadius: AppRadius.allSm,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: group.isFullyChecked,
                    onChanged: (_) => onToggleGroup(),
                  ),
                  Text(
                    'Cả nhóm',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: AppTextStyles.labelS.copyWith(
                      color: AppColors.neutral700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [progress, toggle],
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            const SizedBox(width: 8),
            progress,
            const SizedBox(width: 8),
            toggle,
          ],
        );
      },
    );
  }
}

class _SortItemCard extends StatelessWidget {
  final SKUItem item;
  final int rank;
  final int total;
  final ValueChanged<SKUItem> onItemCheckChanged;

  const _SortItemCard({
    required this.item,
    required this.rank,
    required this.total,
    required this.onItemCheckChanged,
  });

  Future<void> _copyMetadata(
    BuildContext context, {
    required String field,
    required String fieldLabel,
    required String value,
  }) async {
    final startedAt = DateTime.now();
    final logContext = <String, Object?>{
      'field': field,
      'itemId': item.id,
      'valueLength': value.length,
    };
    await AppLogger.instance.info(
      'Sort',
      'Sort item metadata copy started',
      context: logContext,
    );
    try {
      await Clipboard.setData(ClipboardData(text: value));
      await AppLogger.instance.info(
        'Sort',
        'Sort item metadata copy succeeded',
        context: {
          ...logContext,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (!context.mounted) return;
      AppToast.show(
        context,
        SnackBar(content: Text('Đã sao chép $fieldLabel.')),
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'Sort',
        'Sort item metadata copy failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          ...logContext,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (!context.mounted) return;
      AppToast.show(
        context,
        SnackBar(
          content: Text('Chưa sao chép được $fieldLabel. Vui lòng thử lại.'),
        ),
      );
    }
  }

  void _toggleItem() {
    onItemCheckChanged(item.copyWith(isChecked: !item.isChecked));
  }

  @override
  Widget build(BuildContext context) {
    final color = item.isChecked ? AppColors.success : _fifoColor(rank, total);
    final title = item.name.isNotEmpty ? item.name : item.sku;
    final ageLabel = DateFormatter.inventoryAgeLabel(item.date);

    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 8,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(AppRadius.sm),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.labelL.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (item.isChecked)
                          const AppStatusChip(
                            label: 'Đã xếp',
                            color: AppColors.success,
                            backgroundColor: AppColors.successSurface,
                          )
                        else
                          const AppStatusChip(label: 'FIFO'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (item.serial.isNotEmpty)
                          AppInfoChip(
                            Icons.qr_code_rounded,
                            item.serial,
                            key: ValueKey('sort-copy-serial-${item.id}'),
                            tooltip: 'Sao chép serial',
                            semanticsLabel: 'Serial ${item.serial}',
                            onTap: () => unawaited(
                              _copyMetadata(
                                context,
                                field: 'serial',
                                fieldLabel: 'serial',
                                value: item.serial,
                              ),
                            ),
                          ),
                        AppInfoChip(Icons.inventory_2_outlined, item.sku),
                        if (item.date.isNotEmpty)
                          AppInfoChip(Icons.calendar_today_outlined, item.date),
                        if (ageLabel != null)
                          AppInfoChip(Icons.timelapse_rounded, ageLabel),
                        if (item.bin.isNotEmpty)
                          AppInfoChip(
                            Icons.location_on_outlined,
                            item.bin,
                            key: ValueKey('sort-copy-location-${item.id}'),
                            tooltip: 'Sao chép vị trí',
                            semanticsLabel: 'Vị trí ${item.bin}',
                            onTap: () => unawaited(
                              _copyMetadata(
                                context,
                                field: 'location',
                                fieldLabel: 'vị trí',
                                value: item.bin,
                              ),
                            ),
                          ),
                        if (item.zone.isNotEmpty)
                          AppInfoChip(Icons.map_outlined, item.zone),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: item.isChecked,
                          onChanged: (_) => _toggleItem(),
                        ),
                        Expanded(
                          child: Text(
                            item.isChecked
                                ? 'Bỏ đánh dấu đã xếp'
                                : 'Đánh dấu đã xếp',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _fifoColor(int rank, int total) {
    if (total <= 1) return AppColors.success;
    final t = rank / (total - 1);
    return Color.lerp(AppColors.success, AppColors.error, t) ?? AppColors.error;
  }
}
