import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Search field
          TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'Tìm theo Serial / SKU / BIN...',
              hintStyle: TextStyle(
                fontSize: 14,
                color: AppColors.neutral500,
              ),
              prefixIcon: Icon(
                Icons.search,
                color: AppColors.neutral500,
                size: 20,
              ),
              suffixIcon: searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: onClearFilter,
                    )
                  : null,
              filled: true,
              fillColor: isDark ? AppColors.darkNeutral50 : AppColors.neutral50,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
            onSubmitted: (_) => onSearch(),
            textInputAction: TextInputAction.search,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: AppLayoutTokens.formFieldGap),
          // User filter
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: userFilterController,
                  decoration: InputDecoration(
                    hintText: 'Lọc theo email người dùng...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: AppColors.neutral500,
                    ),
                    prefixIcon: Icon(
                      Icons.person_outline,
                      color: AppColors.neutral500,
                      size: 18,
                    ),
                    filled: true,
                    fillColor: isDark ? AppColors.darkNeutral50 : AppColors.neutral50,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                  ),
                  onSubmitted: (_) => onSearch(),
                  textInputAction: TextInputAction.search,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              Material(
                color: AppColors.info,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onSearch,
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.search,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppLayoutTokens.formInlineGap),
          // Result count
          Row(
            children: [
              Text(
                'Tổng: $totalCount bản ghi',
                style: TextStyle(fontSize: 12, color: AppColors.neutral500),
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
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.filter_alt_off,
                          size: 12,
                          color: Colors.orange[700],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Xóa bộ lọc',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange[700],
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
