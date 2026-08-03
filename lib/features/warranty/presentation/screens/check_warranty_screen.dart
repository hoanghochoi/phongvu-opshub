import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';
import '../../../../core/utils/date_formatter.dart';
import '../providers/warranty_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../fifo_check/presentation/widgets/barcode_scanner_screen.dart'
    show showBarcodeScanner;
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/logging/app_logger.dart';

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

    if (userEmail.isEmpty) {
      await AppLogger.instance.warn(
        'WarrantyLookup',
        'Warranty receipt list skipped because no authenticated user is available',
      );
      return;
    }

    final startedAt = DateTime.now();
    await AppLogger.instance.info(
      'WarrantyLookup',
      'Warranty receipt list load started',
    );
    final succeeded = await warrantyProvider.showAllWarranty(userEmail);
    final logContext = {
      'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
      'receiptCount': warrantyProvider.receipts.length,
    };
    if (succeeded) {
      await AppLogger.instance.info(
        'WarrantyLookup',
        'Warranty receipt list load succeeded',
        context: logContext,
      );
      return;
    }
    await AppLogger.instance.warn(
      'WarrantyLookup',
      'Warranty receipt list load failed',
      context: logContext,
    );
  }

  Future<void> _searchReceipt() async {
    final query = _searchController.text.trim().toUpperCase();
    if (query.isEmpty) {
      await AppLogger.instance.info(
        'WarrantyLookup',
        'Warranty receipt search skipped because the query is empty',
      );
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final warrantyProvider = context.read<WarrantyProvider>();
    final userEmail = authProvider.user?.email ?? '';

    if (userEmail.isEmpty) {
      await AppLogger.instance.warn(
        'WarrantyLookup',
        'Warranty receipt search skipped because no authenticated user is available',
        context: {'queryLength': query.length},
      );
      return;
    }

    setState(() {
      _isSearchMode = true;
    });

    final startedAt = DateTime.now();
    await AppLogger.instance.info(
      'WarrantyLookup',
      'Warranty receipt search started',
      context: {'queryLength': query.length},
    );
    final succeeded = await warrantyProvider.searchWarranty(
      userEmail: userEmail,
      receiptNumber: query,
    );
    final logContext = {
      'queryLength': query.length,
      'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
      'resultCount': warrantyProvider.receipts.length,
    };
    if (succeeded) {
      await AppLogger.instance.info(
        'WarrantyLookup',
        'Warranty receipt search succeeded',
        context: logContext,
      );
      return;
    }
    await AppLogger.instance.warn(
      'WarrantyLookup',
      'Warranty receipt search failed',
      context: logContext,
    );
  }

  Future<void> _scanBarcode() async {
    await AppLogger.instance.info(
      'WarrantyLookup',
      'Warranty receipt scanner opened',
    );
    if (!mounted) return;
    try {
      final result = await showBarcodeScanner(context);

      if (result != null && mounted) {
        await AppLogger.instance.info(
          'WarrantyLookup',
          'Warranty receipt scanner returned a value',
          context: {'valueLength': result.length},
        );
        _searchController.text = result;
        await _searchReceipt();
        return;
      }
      await AppLogger.instance.info(
        'WarrantyLookup',
        'Warranty receipt scanner closed without a value',
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'WarrantyLookup',
        'Warranty receipt scanner failed',
        error: error,
        stackTrace: stackTrace,
        context: {'errorType': error.runtimeType.toString()},
      );
      if (mounted) {
        AppToast.show(
          context,
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
    unawaited(
      AppLogger.instance.info(
        'WarrantyLookup',
        'Warranty receipt search cleared; reloading the full list',
      ),
    );
    unawaited(_loadAllReceipts());
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
    if (receiptNumber.isEmpty) {
      await AppLogger.instance.warn(
        'WarrantyLookup',
        'Warranty receipt detail navigation skipped because the receipt identifier is missing',
      );
      return;
    }

    await AppLogger.instance.info(
      'WarrantyLookup',
      'Warranty receipt detail opened',
      context: {'receiptLength': receiptNumber.length},
    );
    if (!mounted) return;

    await context.push(
      '/check-warranty/details/${Uri.encodeComponent(receiptNumber)}',
    );

    // Refresh list when returning from details screen
    if (mounted) {
      await AppLogger.instance.info(
        'WarrantyLookup',
        'Warranty receipt detail closed; refreshing the active lookup',
        context: {'searchMode': _isSearchMode},
      );
      if (_isSearchMode) {
        await _searchReceipt();
      } else {
        await _loadAllReceipts();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final isWide = viewportWidth >= AppLayoutTokens.desktopBreakpoint;
    final pagePadding = isWide
        ? const EdgeInsets.fromLTRB(32, 32, 32, 24)
        : const EdgeInsets.fromLTRB(16, 16, 16, 16);
    return AppResponsiveContent(
      maxWidth: isWide ? double.infinity : 375,
      padding: pagePadding,
      alignment: Alignment.topLeft,
      child: Consumer<WarrantyProvider>(
        builder: (context, warrantyProvider, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WarrantyLookupHeader(
                isWide: isWide,
                isSearchMode: _isSearchMode,
                receiptCount: warrantyProvider.receipts.length,
                isLoading: warrantyProvider.isLoading,
                onBackToHub: () => context.go('/warranty-main'),
                onRefresh: _retryCurrentLookup,
              ),
              SizedBox(height: isWide ? 4 : 18),
              _WarrantySearchCard(
                controller: _searchController,
                focusNode: _searchFocusNode,
                isSearchMode: _isSearchMode,
                isLoading: warrantyProvider.isLoading,
                onScan: _scanBarcode,
                onClear: _clearSearch,
                onSearch: _searchReceipt,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _WarrantyReceiptList(
                  warrantyProvider: warrantyProvider,
                  isWide: isWide,
                  hasCompactStateAuthority:
                      viewportWidth < AppLayoutTokens.compactBreakpoint,
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
  final bool isWide;
  final bool isSearchMode;
  final int receiptCount;
  final bool isLoading;
  final VoidCallback onBackToHub;
  final VoidCallback onRefresh;

  const _WarrantyLookupHeader({
    required this.isWide,
    required this.isSearchMode,
    required this.receiptCount,
    required this.isLoading,
    required this.onBackToHub,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final chips = SizedBox(
      key: const Key('warranty-lookup-chips'),
      height: 24,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 115,
            child: AppStatusChip(
              label: isSearchMode ? 'Đang lọc' : 'Tất cả biên nhận',
              color: AppColors.info,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 25),
          SizedBox(
            width: 80,
            child: AppStatusChip(
              label: '$receiptCount kết quả',
              color: receiptCount == 0 ? AppColors.neutral700 : AppColors.info,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 18),
          const SizedBox(
            width: 84,
            child: AppStatusChip(
              label: 'Có scanner',
              color: AppColors.info,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    final actions = _WarrantyLookupActions(
      isLoading: isLoading,
      onBackToHub: onBackToHub,
      onRefresh: onRefresh,
    );

    return Column(
      key: const Key('warranty-lookup-header'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 26,
          child: Text('Xem lại biên nhận', style: AppTextStyles.headingS),
        ),
        if (isWide) ...[
          const SizedBox(height: 38),
          SizedBox(
            height: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: chips,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 37),
                  child: actions,
                ),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 14),
          actions,
          const SizedBox(height: 4),
          chips,
        ],
      ],
    );
  }
}

class _WarrantyLookupActions extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onBackToHub;
  final VoidCallback onRefresh;

  const _WarrantyLookupActions({
    required this.isLoading,
    required this.onBackToHub,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final compactPhone = MediaQuery.sizeOf(context).width < 600;
    return SizedBox(
      key: const Key('warranty-lookup-actions'),
      height: 48,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: AppSecondaryButton(
              key: const Key('warranty-lookup-refresh'),
              onPressed: isLoading ? null : onRefresh,
              icon: PhosphorIconsRegular.arrowCounterClockwise,
              label: 'Tải lại',
              size: AppButtonSize.medium,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 151,
            child: AppSecondaryButton(
              key: const Key('warranty-lookup-back'),
              onPressed: onBackToHub,
              icon: PhosphorIconsRegular.arrowLeft,
              label: 'Về bảo hành',
              size: compactPhone ? AppButtonSize.medium : AppButtonSize.small,
            ),
          ),
        ],
      ),
    );
  }
}

class _WarrantySearchCard extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSearchMode;
  final bool isLoading;
  final VoidCallback onScan;
  final VoidCallback onClear;
  final VoidCallback onSearch;

  const _WarrantySearchCard({
    required this.controller,
    required this.focusNode,
    required this.isSearchMode,
    required this.isLoading,
    required this.onScan,
    required this.onClear,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('warranty-lookup-search-card'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: SizedBox(
              height: 76,
              child: AppTextInput(
                key: const Key('warranty-lookup-input'),
                controller: controller,
                focusNode: focusNode,
                enabled: !isLoading,
                textCapitalization: TextCapitalization.characters,
                label: 'Biên nhận',
                hintText: 'CPxx-Jxxxxxxxx hoặc ST-123456',
                suffixIcon: isSearchMode
                    ? IconButton(
                        key: const Key('warranty-lookup-clear'),
                        icon: const Icon(PhosphorIconsRegular.x),
                        onPressed: isLoading ? null : onClear,
                        tooltip: 'Xóa tìm kiếm',
                      )
                    : null,
                onSubmitted: (_) => onSearch(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          AppIconAction(
            key: const Key('warranty-lookup-scan'),
            icon: PhosphorIconsRegular.qrCode,
            onPressed: isLoading ? null : onScan,
            tooltip: 'Quét mã',
          ),
          const SizedBox(width: 12),
          AppIconAction(
            key: const Key('warranty-lookup-submit'),
            onPressed: isLoading ? null : onSearch,
            icon: isLoading
                ? PhosphorIconsRegular.spinnerGap
                : PhosphorIconsRegular.magnifyingGlass,
            tooltip: isLoading ? 'Đang tìm' : 'Tìm',
            filled: true,
          ),
        ],
      ),
    );
  }
}

class _WarrantyReceiptList extends StatelessWidget {
  final WarrantyProvider warrantyProvider;
  final bool isWide;
  final bool hasCompactStateAuthority;
  final bool isSearchMode;
  final Future<void> Function() onRefresh;
  final ValueChanged<Map<String, dynamic>> onViewReceipt;

  const _WarrantyReceiptList({
    required this.warrantyProvider,
    required this.isWide,
    required this.hasCompactStateAuthority,
    required this.isSearchMode,
    required this.onRefresh,
    required this.onViewReceipt,
  });

  @override
  Widget build(BuildContext context) {
    if (warrantyProvider.isLoading) {
      if (hasCompactStateAuthority) {
        return const AppListSkeleton(
          key: Key('warranty-lookup-loading'),
          itemCount: 3,
          itemHeight: 76,
          scrollable: false,
        );
      }
      return const AppSurfaceCard(
        key: Key('warranty-lookup-loading'),
        child: AppStatePanel.loading(title: 'Đang tải biên nhận'),
      );
    }

    if (warrantyProvider.errorMessage != null) {
      return AppSurfaceCard(
        key: const Key('warranty-lookup-error'),
        child: AppStatePanel.error(
          title: 'Chưa tải được biên nhận',
          message: 'Kiểm tra kết nối rồi thử lại.',
          actionLabel: hasCompactStateAuthority ? 'Thử tải lại' : 'Thử lại',
          actionIcon: PhosphorIconsRegular.arrowCounterClockwise,
          onAction: onRefresh,
          compact: hasCompactStateAuthority,
        ),
      );
    }

    if (warrantyProvider.receipts.isEmpty) {
      return AppSurfaceCard(
        key: const Key('warranty-lookup-empty'),
        child: AppStatePanel.empty(
          title: hasCompactStateAuthority || isSearchMode
              ? 'Không tìm thấy biên nhận'
              : 'Chưa có biên nhận nào',
          icon: PhosphorIconsRegular.receipt,
          compact: hasCompactStateAuthority,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: warrantyProvider.receipts.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final receipt = warrantyProvider.receipts[index];
          return _ReceiptCard(
            receipt: receipt,
            isWide: isWide,
            onTap: () => onViewReceipt(receipt),
          );
        },
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  final Map<String, dynamic> receipt;
  final bool isWide;
  final VoidCallback onTap;

  const _ReceiptCard({
    required this.receipt,
    required this.isWide,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final receiptNumber = receipt['receipt']?.toString() ?? 'Chưa có';
    final user = receipt['user']?.toString() ?? 'Chưa có';
    final dateString = receipt['date']?.toString();
    final formattedDate = DateFormatter.format(dateString);

    final metadataStyle = AppTextStyles.bodyS.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      height: 20 / 13,
    );
    return SizedBox(
      key: const Key('warranty-receipt-card'),
      height: isWide ? 104 : 112,
      child: AppSurfaceCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
        onTap: onTap,
        child: Row(
          children: [
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
                  SizedBox(height: isWide ? 12 : 8),
                  Text(
                    'Người lưu: $user',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: metadataStyle,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Ngày lưu: $formattedDate',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: metadataStyle,
                  ),
                ],
              ),
            ),
            SizedBox.square(
              dimension: isWide ? 24 : 44,
              child: const Center(
                child: Icon(
                  PhosphorIconsRegular.caretRight,
                  size: 24,
                  color: AppColors.neutral400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
