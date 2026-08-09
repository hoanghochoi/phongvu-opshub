import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_command_bar.dart';
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
      final result = await showBarcodeScanner(context);

      if (result != null && mounted) {
        _controller.text = result;
        _focusNode.requestFocus();
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
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
      AppToast.show(
        context,
        const SnackBar(content: Text('Vui lòng nhập SKU hoặc BIN')),
      );
      return;
    }

    if (_looksLikeSerial(text)) {
      AppToast.show(
        context,
        SnackBar(
          content: Text(
            'Sắp xếp chỉ hỗ trợ SKU hoặc BIN.\nNếu cần kiểm tra serial, vui lòng dùng Kiểm tra FIFO.',
          ),
          duration: Duration(seconds: 3),
          backgroundColor: AppColors.warningOf(context),
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
        AppToast.show(
          context,
          SnackBar(
            content: Text(error),
            backgroundColor: AppColors.errorOf(context),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SortProvider>(
      builder: (context, provider, child) {
        return AppResponsiveContent(
          maxWidth: AppLayoutTokens.commandWorkspaceMaxWidth,
          onRefresh: AppRefreshCallbacks.noop,
          refreshLogSource: 'Sort',
          refreshLogContext: () => {
            'hasInput': _controller.text.trim().isNotEmpty,
            'hasResult': provider.skuGroups?.isNotEmpty == true,
            'isLoading': provider.isLoading,
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SortWorkspaceHeader(),
              const SizedBox(height: 16),
              _SortCommandCard(
                controller: _controller,
                focusNode: _focusNode,
                isLoading: provider.isLoading,
                onScan: _scanBarcode,
                onSubmit: _sendSortRequest,
              ),
              const SizedBox(height: 16),
              Expanded(child: _SortResultPanel(provider: provider)),
            ],
          ),
        );
      },
    );
  }
}

class _SortWorkspaceHeader extends StatelessWidget {
  const _SortWorkspaceHeader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      key: Key('sort-fifo-workspace-header'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sắp xếp FIFO', style: AppTextStyles.headingM),
        SizedBox(height: 4),
        Text(
          'Tìm vị trí hàng hóa theo SKU hoặc BIN.',
          style: AppTextStyles.bodyS,
        ),
      ],
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
    return AppCommandBar(
      key: const Key('sort-fifo-command-card'),
      controller: controller,
      focusNode: focusNode,
      isLoading: isLoading,
      label: 'SKU hoặc BIN',
      hintText: 'SKU hoặc BIN',
      textCapitalization: TextCapitalization.characters,
      onSubmitted: (_) => onSubmit(),
      onScan: onScan,
      onPrimaryAction: onSubmit,
      scanTooltip: 'Quét mã',
      primaryActionTooltip: 'Tìm hàng để sắp xếp',
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
        borderColor: AppColors.errorOf(context).withValues(alpha: 0.36),
        backgroundColor: AppColors.errorSurfaceOf(context),
        child: AppStatePanel.error(
          title: error,
          message: 'Kiểm tra lại SKU/BIN hoặc thử gửi lại.',
          actionLabel: 'Đóng thông báo',
          actionIcon: PhosphorIconsRegular.x,
          onAction: provider.clearError,
        ),
      );
    }

    final groups = provider.skuGroups;
    if (groups == null || groups.isEmpty) {
      return const AppSurfaceCard(
        child: AppStatePanel(
          icon: PhosphorIconsRegular.package,
          title: 'Chưa có kết quả sắp xếp',
          message: 'Nhập SKU hoặc BIN để xem vị trí hàng hóa.',
        ),
      );
    }

    final totalItems = groups.fold<int>(
      0,
      (total, group) => total + group.totalItems,
    );

    return AppSurfaceCard(
      key: const Key('sort-fifo-results'),
      padding: EdgeInsets.zero,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: groups.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Kết quả sắp xếp • $totalItems sản phẩm',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleEmphasis.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AppStatusChip(
                    label: '${groups.length} nhóm',
                    color: AppColors.infoOf(context),
                    backgroundColor: AppColors.infoSurfaceOf(context),
                  ),
                ],
              ),
            );
          }

          final group = groups[index - 1];
          return SortSKUGroupWidget(
            group: group,
            onItemCheckChanged: provider.updateSKUItem,
          );
        },
      ),
    );
  }
}
