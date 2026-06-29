import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color:
            Theme.of(context).cardTheme.color ??
            Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          AppTextInput(
            controller: searchController,
            label: 'Tìm kiếm',
            hintText: 'Tìm theo Serial / SKU / BIN...',
            icon: Icons.search,
            dense: true,
            suffixIcon: searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: onClearFilter,
                  )
                : null,
            onSubmitted: (_) => onSearch(),
            textInputAction: TextInputAction.search,
          ),
          const SizedBox(height: AppLayoutTokens.formFieldGap),
          Row(
            children: [
              Expanded(
                child: AppTextInput(
                  controller: userFilterController,
                  label: 'Người dùng',
                  hintText: 'Lọc theo email người dùng...',
                  icon: Icons.person_outline,
                  dense: true,
                  onSubmitted: (_) => onSearch(),
                  textInputAction: TextInputAction.search,
                ),
              ),
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              AppIconAction(
                onPressed: onSearch,
                icon: Icons.search,
                tooltip: 'Tìm',
                filled: true,
              ),
            ],
          ),
          const SizedBox(height: AppLayoutTokens.formInlineGap),
          Row(
            children: [
              Text(
                'Tổng: $totalCount bản ghi',
                style: AppTextStyles.labelS.copyWith(
                  color: AppColors.neutral500,
                ),
              ),
              if (searchQuery != null || filterUser != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onClearFilter,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(
                        AppLayoutTokens.cardRadius,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.filter_alt_off,
                          size: 12,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Xóa bộ lọc',
                          style: AppTextStyles.captionBold.copyWith(
                            color: AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
