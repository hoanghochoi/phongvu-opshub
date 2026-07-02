import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';

class FifoHistorySearchBar extends StatelessWidget {
  final TextEditingController searchController;
  final TextEditingController userFilterController;
  final VoidCallback onSearch;
  final VoidCallback onClearFilter;
  final int totalCount;
  final String? searchQuery;
  final String? filterUser;

  const FifoHistorySearchBar({
    super.key,
    required this.searchController,
    required this.userFilterController,
    required this.onSearch,
    required this.onClearFilter,
    required this.totalCount,
    this.searchQuery,
    this.filterUser,
  });

  @override
  Widget build(BuildContext context) {
    final hasFilter = searchQuery != null || filterUser != null;
    final searchField = AppTextInput(
      key: const Key('fifo-history-query-field'),
      controller: searchController,
      label: 'Truy vấn',
      hintText: 'Serial, SKU hoặc BIN',
      icon: Icons.search,
      dense: true,
      onSubmitted: (_) => onSearch(),
      textInputAction: TextInputAction.search,
    );
    final userField = AppTextInput(
      key: const Key('fifo-history-user-field'),
      controller: userFilterController,
      label: 'Người dùng',
      hintText: 'Email người dùng',
      icon: Icons.person_outline,
      dense: true,
      onSubmitted: (_) => onSearch(),
      textInputAction: TextInputAction.search,
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconAction(
          onPressed: onSearch,
          icon: Icons.search,
          tooltip: 'Tìm lịch sử',
          filled: true,
        ),
        if (hasFilter) ...[
          const SizedBox(width: AppLayoutTokens.formInlineGap),
          AppIconAction(
            onPressed: onClearFilter,
            icon: Icons.filter_alt_off_outlined,
            tooltip: 'Xóa bộ lọc',
          ),
        ],
      ],
    );

    return AppSurfaceCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                searchField,
                const SizedBox(height: AppLayoutTokens.formFieldGap),
                userField,
                const SizedBox(height: AppLayoutTokens.formInlineGap),
                Align(alignment: Alignment.centerRight, child: actions),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(flex: 2, child: searchField),
                    const SizedBox(width: AppLayoutTokens.formInlineGap),
                    Expanded(child: userField),
                    const SizedBox(width: AppLayoutTokens.formInlineGap),
                    actions,
                  ],
                ),
              const SizedBox(height: AppLayoutTokens.formInlineGap),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppStatusChip(
                    label: '$totalCount bản ghi',
                    color: AppColors.info,
                  ),
                  if (hasFilter)
                    const AppStatusChip(
                      label: 'Đang lọc',
                      color: AppColors.warning,
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
