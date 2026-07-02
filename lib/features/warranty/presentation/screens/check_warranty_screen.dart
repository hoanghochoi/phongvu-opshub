import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/utils/date_formatter.dart';
import '../providers/warranty_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'warranty_details_screen.dart';
import '../../../fifo_check/presentation/widgets/barcode_scanner_screen.dart'
    show BarcodeScannerScreen;
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';

class CheckWarrantyScreen extends StatefulWidget {
  const CheckWarrantyScreen({super.key});

  @override
  State<CheckWarrantyScreen> createState() => _CheckWarrantyScreenState();
}

class _CheckWarrantyScreenState extends State<CheckWarrantyScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _isSearchMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllReceipts();
      // Auto-focus search field when screen loads
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadAllReceipts() async {
    final authProvider = context.read<AuthProvider>();
    final warrantyProvider = context.read<WarrantyProvider>();
    final userEmail = authProvider.user?.email ?? '';

    if (userEmail.isNotEmpty) {
      await warrantyProvider.showAllWarranty(userEmail);
    }
  }

  Future<void> _searchReceipt() async {
    if (_searchController.text.trim().isEmpty) {
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final warrantyProvider = context.read<WarrantyProvider>();
    final userEmail = authProvider.user?.email ?? '';

    if (userEmail.isEmpty) return;

    setState(() {
      _isSearchMode = true;
    });

    await warrantyProvider.searchWarranty(
      userEmail: userEmail,
      receiptNumber: _searchController.text.trim().toUpperCase(),
    );
  }

  Future<void> _scanBarcode() async {
    try {
      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
      );

      if (result != null && mounted) {
        _searchController.text = result;
        _searchReceipt();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chưa quét được mã. Vui lòng thử lại.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _isSearchMode = false;
    });
    _loadAllReceipts();
  }

  Future<void> _retryCurrentLookup() async {
    if (_isSearchMode) {
      await _searchReceipt();
      return;
    }
    await _loadAllReceipts();
  }

  void _viewReceiptDetails(Map<String, dynamic> receipt) async {
    final receiptNumber = receipt['receipt']?.toString() ?? '';
    if (receiptNumber.isEmpty) return;

    // Navigate to details screen
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            WarrantyDetailsScreen(receiptNumber: receiptNumber),
      ),
    );

    // Refresh list when returning from details screen
    if (mounted) {
      if (_isSearchMode) {
        _searchReceipt();
      } else {
        _loadAllReceipts();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppResponsiveContent(
      child: Consumer<WarrantyProvider>(
        builder: (context, warrantyProvider, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WarrantyLookupHeader(
                isSearchMode: _isSearchMode,
                receiptCount: warrantyProvider.receipts.length,
                onBackToHub: () => context.go('/warranty-main'),
                onRefresh: _retryCurrentLookup,
              ),
              const SizedBox(height: AppLayoutTokens.sectionGap),
              _WarrantySearchCard(
                controller: _searchController,
                focusNode: _searchFocusNode,
                isSearchMode: _isSearchMode,
                onScan: _scanBarcode,
                onClear: _clearSearch,
                onSearch: _searchReceipt,
              ),
              const SizedBox(height: AppLayoutTokens.sectionGap),
              Expanded(
                child: _WarrantyReceiptList(
                  warrantyProvider: warrantyProvider,
                  isSearchMode: _isSearchMode,
                  onRefresh: _retryCurrentLookup,
                  onViewReceipt: _viewReceiptDetails,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WarrantyLookupHeader extends StatelessWidget {
  final bool isSearchMode;
  final int receiptCount;
  final VoidCallback onBackToHub;
  final VoidCallback onRefresh;

  const _WarrantyLookupHeader({
    required this.isSearchMode,
    required this.receiptCount,
    required this.onBackToHub,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('warranty-lookup-header'),
      backgroundColor: AppColors.infoSurface,
      borderColor: AppColors.info.withValues(alpha: 0.22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < AppLayoutTokens.tabletBreakpoint;
          final icon = Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
            ),
            child: const Icon(
              Icons.manage_search_rounded,
              color: AppColors.info,
            ),
          );
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Xem lại biên nhận', style: AppTextStyles.headingM),
              const SizedBox(height: 6),
              Text(
                'Tìm nhanh biên nhận bảo hành / sửa chữa, mở chi tiết và kiểm tra hình ảnh đã lưu.',
                style: AppTextStyles.bodyM.copyWith(
                  color: AppColors.neutral600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: AppLayoutTokens.cardGap),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppStatusChip(
                    label: isSearchMode ? 'Đang lọc' : 'Tất cả biên nhận',
                    color: AppColors.info,
                    backgroundColor: AppColors.surface,
                  ),
                  AppStatusChip(
                    label: '$receiptCount kết quả',
                    color: receiptCount == 0
                        ? AppColors.neutral700
                        : AppColors.info,
                    backgroundColor: AppColors.surface,
                  ),
                  const AppStatusChip(
                    label: 'Có scanner',
                    color: AppColors.info,
                    backgroundColor: AppColors.surface,
                  ),
                ],
              ),
            ],
          );
          final actions = Wrap(
            spacing: AppLayoutTokens.formInlineGap,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              SizedBox(
                width: 124,
                child: AppSecondaryButton(
                  onPressed: onRefresh,
                  icon: Icons.refresh_rounded,
                  label: 'Tải lại',
                ),
              ),
              SizedBox(
                width: 136,
                child: AppSecondaryButton(
                  onPressed: onBackToHub,
                  icon: Icons.arrow_back_rounded,
                  label: 'Về BH/SC',
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                icon,
                const SizedBox(height: 14),
                content,
                const SizedBox(height: AppLayoutTokens.cardGap),
                actions,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              Expanded(child: content),
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _WarrantySearchCard extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSearchMode;
  final VoidCallback onScan;
  final VoidCallback onClear;
  final VoidCallback onSearch;

  const _WarrantySearchCard({
    required this.controller,
    required this.focusNode,
    required this.isSearchMode,
    required this.onScan,
    required this.onClear,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('warranty-lookup-search-card'),
      child: Row(
        children: [
          AppIconAction(
            icon: Icons.qr_code_scanner,
            onPressed: onScan,
            tooltip: 'Quét mã',
          ),
          const SizedBox(width: AppLayoutTokens.formInlineGap),
          Expanded(
            child: AppTextInput(
              controller: controller,
              focusNode: focusNode,
              textCapitalization: TextCapitalization.characters,
              label: 'Biên nhận',
              hintText: 'CPxx-Jxxxxxxxx hoặc ST-123456',
              icon: Icons.search,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSearchMode)
                    AppIconAction(
                      icon: Icons.clear,
                      onPressed: onClear,
                      tooltip: 'Xóa tìm kiếm',
                    ),
                  AppIconAction(
                    onPressed: onSearch,
                    icon: Icons.search_rounded,
                    tooltip: 'Tìm',
                    filled: true,
                  ),
                ],
              ),
              onSubmitted: (_) => onSearch(),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarrantyReceiptList extends StatelessWidget {
  final WarrantyProvider warrantyProvider;
  final bool isSearchMode;
  final Future<void> Function() onRefresh;
  final ValueChanged<Map<String, dynamic>> onViewReceipt;

  const _WarrantyReceiptList({
    required this.warrantyProvider,
    required this.isSearchMode,
    required this.onRefresh,
    required this.onViewReceipt,
  });

  @override
  Widget build(BuildContext context) {
    if (warrantyProvider.isLoading) {
      return const AppSurfaceCard(
        child: AppStatePanel.loading(title: 'Đang tải biên nhận'),
      );
    }

    if (warrantyProvider.errorMessage != null) {
      return AppSurfaceCard(
        child: AppStatePanel.error(
          title: 'Chưa tải được biên nhận',
          message: warrantyProvider.errorMessage!,
          actionLabel: 'Thử lại',
          actionIcon: Icons.refresh_rounded,
          onAction: onRefresh,
        ),
      );
    }

    if (warrantyProvider.receipts.isEmpty) {
      return AppSurfaceCard(
        child: AppStatePanel.empty(
          title: isSearchMode
              ? 'Không tìm thấy biên nhận'
              : 'Chưa có biên nhận nào',
          icon: Icons.receipt_long_outlined,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: warrantyProvider.receipts.length,
        itemBuilder: (context, index) {
          final receipt = warrantyProvider.receipts[index];
          return _ReceiptCard(
            receipt: receipt,
            onTap: () => onViewReceipt(receipt),
          );
        },
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  final Map<String, dynamic> receipt;
  final VoidCallback onTap;

  const _ReceiptCard({required this.receipt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final receiptNumber = receipt['receipt']?.toString() ?? 'Chưa có';
    final user = receipt['user']?.toString() ?? 'Chưa có';
    final dateString = receipt['date']?.toString();
    final formattedDate = DateFormatter.format(dateString);

    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
            ),
            child: const Icon(
              Icons.receipt_long,
              color: AppColors.info,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  receiptNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: AppTextStyles.labelL,
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Người lưu: ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: AppTextStyles.labelS.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        user,
                        maxLines: 1,
                        style: AppTextStyles.labelS.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Ngày lưu: ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: AppTextStyles.labelS.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      formattedDate,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: AppTextStyles.labelS.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios,
            size: 16,
            color: AppColors.neutral400,
          ),
        ],
      ),
    );
  }
}
