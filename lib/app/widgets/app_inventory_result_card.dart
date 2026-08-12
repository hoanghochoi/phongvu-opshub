import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_text_styles.dart';
import 'app_cards.dart';
import 'app_chips.dart';

class AppInventoryMetadata {
  final IconData icon;
  final String text;
  final Key? key;
  final VoidCallback? onTap;
  final String? tooltip;
  final String? semanticsLabel;

  const AppInventoryMetadata({
    required this.icon,
    required this.text,
    this.key,
    this.onTap,
    this.tooltip,
    this.semanticsLabel,
  });
}

/// Shared inventory card used by FIFO sort and FIFO check results.
///
/// Metadata chips always use the same visual footprint. Copy semantics live
/// inside the chip instead of adding a taller wrapper to the surrounding Wrap.
class AppInventoryResultCard extends StatelessWidget {
  final Key? cardKey;
  final Key? titleKey;
  final Key? statusKey;
  final Key? metadataWrapKey;
  final Key? actionKey;
  final String title;
  final String statusLabel;
  final Color accentColor;
  final Color? statusColor;
  final Color? statusBackgroundColor;
  final List<AppInventoryMetadata> metadata;
  final bool checked;
  final bool busy;
  final String uncheckedActionLabel;
  final String checkedActionLabel;
  final ValueChanged<bool>? onCheckedChanged;
  final EdgeInsetsGeometry margin;

  const AppInventoryResultCard({
    super.key,
    this.cardKey,
    this.titleKey,
    this.statusKey,
    this.metadataWrapKey,
    this.actionKey,
    required this.title,
    required this.statusLabel,
    required this.accentColor,
    this.statusColor,
    this.statusBackgroundColor,
    required this.metadata,
    required this.checked,
    this.busy = false,
    required this.uncheckedActionLabel,
    required this.checkedActionLabel,
    required this.onCheckedChanged,
    this.margin = const EdgeInsets.only(bottom: 10),
  });

  @override
  Widget build(BuildContext context) {
    final effectiveStatusColor =
        statusColor ?? AppColors.textSecondaryOf(context);
    final effectiveStatusBackground =
        statusBackgroundColor ?? effectiveStatusColor.withValues(alpha: 0.08);

    return AppSurfaceCard(
      key: cardKey,
      margin: margin,
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 8,
              decoration: BoxDecoration(
                color: accentColor,
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
                            key: titleKey,
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.labelL.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        AppStatusChip(
                          key: statusKey,
                          label: statusLabel,
                          color: effectiveStatusColor,
                          backgroundColor: effectiveStatusBackground,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      key:
                          metadataWrapKey ??
                          const Key('inventory-metadata-wrap'),
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final item in metadata)
                          AppInfoChip(
                            item.icon,
                            item.text,
                            key: item.key,
                            onTap: item.onTap,
                            tooltip: item.tooltip,
                            semanticsLabel: item.semanticsLabel,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      key: actionKey,
                      onTap: busy || onCheckedChanged == null
                          ? null
                          : () => onCheckedChanged!(!checked),
                      borderRadius: AppRadius.allSm,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: checked,
                            onChanged: busy || onCheckedChanged == null
                                ? null
                                : (value) => onCheckedChanged!(value ?? false),
                          ),
                          Flexible(
                            child: Text(
                              checked
                                  ? checkedActionLabel
                                  : uncheckedActionLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                          ),
                        ],
                      ),
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
}
