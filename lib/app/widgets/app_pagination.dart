import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';

class AppPaginationControls extends StatelessWidget {
  final int pageIndex;
  final int totalItems;
  final String itemLabel;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onRefresh;
  final bool isRefreshing;
  final String? label;

  const AppPaginationControls({
    super.key,
    required this.pageIndex,
    required this.totalItems,
    required this.itemLabel,
    required this.onPrevious,
    required this.onNext,
    this.onRefresh,
    this.isRefreshing = false,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('app-pagination-controls'),
      children: [
        IconButton(
          tooltip: 'Trang trước',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Center(
            child: Text(
              label ?? 'Trang ${pageIndex + 1} - $totalItems $itemLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: AppTextStyles.labelM,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Trang sau',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        if (onRefresh != null)
          IconButton(
            tooltip: 'Làm mới',
            onPressed: isRefreshing ? null : onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
      ],
    );
  }
}
