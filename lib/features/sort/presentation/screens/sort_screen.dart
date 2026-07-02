import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../fifo_check/presentation/widgets/barcode_scanner_screen.dart';
import '../providers/sort_provider.dart';
import '../widgets/sort_sku_group_widget.dart';

class SortScreen extends StatefulWidget {
  const SortScreen({super.key});

  @override
  State<SortScreen> createState() => _SortScreenState();
}

class _SortScreenState extends State<SortScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    try {
      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
      );

      if (result != null && mounted) {
        _controller.text = result;
        _focusNode.requestFocus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa quét được mã. Vui lòng thử lại.')),
        );
      }
    }
  }

  bool _looksLikeSerial(String text) {
    final trimmed = text.trim();
    if (trimmed.contains('.') || trimmed.contains('-')) return false;
    final hasLetters = RegExp(r'[a-zA-Z]').hasMatch(trimmed);
    final hasDigits = RegExp(r'[0-9]').hasMatch(trimmed);
    return hasLetters && hasDigits;
  }

  Future<void> _sendSortRequest() async {
    final text = _controller.text.trim();

    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập SKU hoặc BIN')),
      );
      return;
    }

    if (_looksLikeSerial(text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sắp xếp chỉ hỗ trợ SKU hoặc BIN.\nNếu cần kiểm tra serial, vui lòng dùng Kiểm tra FIFO.',
          ),
          duration: Duration(seconds: 3),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final sortProvider = context.read<SortProvider>();
    final userEmail = context.read<AuthProvider>().user?.email ?? '';

    _controller.clear();
    _focusNode.unfocus();

    await sortProvider.sendSortRequest(text, userEmail);

    if (mounted) {
      final error = sortProvider.error;

      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SortProvider>(
      builder: (context, provider, child) {
        return AppResponsiveContent(
          maxWidth: 980,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SortHeader(provider: provider),
              const SizedBox(height: AppLayoutTokens.sectionGap),
              _SortCommandCard(
                controller: _controller,
                focusNode: _focusNode,
                isLoading: provider.isLoading,
                onScan: _scanBarcode,
                onSubmit: _sendSortRequest,
              ),
              const SizedBox(height: AppLayoutTokens.sectionGap),
              Expanded(child: _SortResultPanel(provider: provider)),
            ],
          ),
        );
      },
    );
  }
}

class _SortHeader extends StatelessWidget {
  final SortProvider provider;

  const _SortHeader({required this.provider});

  @override
  Widget build(BuildContext context) {
    final groupCount = provider.skuGroups?.length ?? 0;
    final itemCount = provider.skuItems?.length ?? 0;
    final checkedCount =
        provider.skuGroups?.fold<int>(
          0,
          (total, group) => total + group.checkedItems,
        ) ??
        0;

    return AppSurfaceCard(
      key: const Key('sort-fifo-header'),
      backgroundColor: AppColors.infoSurface,
      borderColor: AppColors.info.withValues(alpha: 0.24),
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
            child: const Icon(Icons.swap_vert_rounded, color: AppColors.info),
          );
          final textBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sắp xếp FIFO', style: AppTextStyles.headingM),
              const SizedBox(height: 6),
              Text(
                'Nhập hoặc quét SKU/BIN để xem vị trí hàng hóa theo FIFO.',
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
                    label: groupCount == 0
                        ? 'Chưa có kết quả'
                        : '$groupCount nhóm SKU',
                    color: groupCount == 0 ? AppColors.warning : AppColors.info,
                    backgroundColor: groupCount == 0
                        ? AppColors.warningSurface
                        : AppColors.infoSurface,
                  ),
                  AppStatusChip(
                    label: '$itemCount vị trí',
                    color: AppColors.neutral700,
                    backgroundColor: AppColors.neutral100,
                  ),
                  AppStatusChip(
                    label: '$checkedCount đã kiểm',
                    color: checkedCount == 0
                        ? AppColors.neutral600
                        : AppColors.success,
                    backgroundColor: checkedCount == 0
                        ? AppColors.neutral100
                        : AppColors.successSurface,
                  ),
                  const AppStatusChip(
                    label: 'SKU/BIN',
                    color: AppColors.primary,
                    backgroundColor: AppColors.primarySurface,
                  ),
                ],
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [icon, const SizedBox(height: 14), textBlock],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              Expanded(child: textBlock),
            ],
          );
        },
      ),
    );
  }
}

class _SortCommandCard extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isLoading;
  final VoidCallback onScan;
  final VoidCallback onSubmit;

  const _SortCommandCard({
    required this.controller,
    required this.focusNode,
    required this.isLoading,
    required this.onScan,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('sort-fifo-command-card'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < AppLayoutTokens.compactBreakpoint;
          final input = AppTextInput(
            controller: controller,
            focusNode: focusNode,
            enabled: !isLoading,
            label: 'SKU hoặc BIN',
            hintText: 'Nhập SKU hoặc BIN',
            icon: Icons.inventory_2_outlined,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSubmit(),
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconAction(
                onPressed: isLoading ? null : onScan,
                icon: Icons.qr_code_scanner_rounded,
                tooltip: 'Quét mã',
              ),
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              AppIconAction(
                onPressed: isLoading ? null : onSubmit,
                icon: Icons.send_rounded,
                tooltip: 'Gửi yêu cầu sắp xếp',
                filled: true,
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                input,
                const SizedBox(height: AppLayoutTokens.formFieldGap),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: input),
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _SortResultPanel extends StatelessWidget {
  final SortProvider provider;

  const _SortResultPanel({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider.isLoading) {
      return const AppSurfaceCard(
        child: AppStatePanel.loading(
          title: 'Đang tìm vị trí hàng hóa',
          message: 'OpsHub đang đọc dữ liệu FIFO theo SKU/BIN.',
        ),
      );
    }

    final error = provider.error;
    if (error != null) {
      return AppSurfaceCard(
        borderColor: AppColors.error.withValues(alpha: 0.24),
        backgroundColor: AppColors.errorSurface,
        child: AppStatePanel.error(
          title: error,
          message: 'Kiểm tra lại SKU/BIN hoặc thử gửi lại.',
          actionLabel: 'Đóng thông báo',
          actionIcon: Icons.close_rounded,
          onAction: provider.clearError,
        ),
      );
    }

    final groups = provider.skuGroups;
    if (groups == null || groups.isEmpty) {
      return const AppSurfaceCard(
        child: AppStatePanel(
          icon: Icons.inventory_2_outlined,
          title: 'Chưa có kết quả sắp xếp',
          message: 'Nhập SKU hoặc BIN để xem vị trí hàng hóa.',
        ),
      );
    }

    return Column(
      key: const Key('sort-fifo-results'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.inventory_2, color: AppColors.info, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Kết quả sắp xếp',
                style: AppTextStyles.labelL.copyWith(color: AppColors.info),
              ),
            ),
            AppStatusChip(
              label: '${groups.length} nhóm',
              color: AppColors.info,
              backgroundColor: AppColors.infoSurface,
            ),
          ],
        ),
        const SizedBox(height: AppLayoutTokens.cardGap),
        Expanded(
          child: ListView.builder(
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              return SortSKUGroupWidget(
                group: group,
                onItemCheckChanged: provider.updateSKUItem,
              );
            },
          ),
        ),
      ],
    );
  }
}
