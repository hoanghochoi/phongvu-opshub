import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../domain/entities/fifo_check_result.dart';
import '../../domain/entities/fifo_inventory_item.dart';
import '../providers/fifo_provider.dart';
import '../../../fifo_check/presentation/widgets/barcode_scanner_screen.dart'
    show BarcodeScannerScreen;

class FifoCheckScreen extends StatefulWidget {
  const FifoCheckScreen({super.key});

  @override
  State<FifoCheckScreen> createState() => _FifoCheckScreenState();
}

class _FifoCheckScreenState extends State<FifoCheckScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
    );
    if (result == null || !mounted) return;
    _controller.text = result.trim().toUpperCase();
    await _search();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    _focusNode.unfocus();
    await context.read<FifoProvider>().check(query);
    _showErrorIfNeeded();
  }

  void _showErrorIfNeeded() {
    final provider = context.read<FifoProvider>();
    final error = provider.error;
    if (error == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error), backgroundColor: AppColors.error),
    );
    provider.clearError();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FifoProvider>(
      builder: (context, provider, _) {
        return AppResponsiveContent(
          maxWidth: 980,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FifoHeader(provider: provider),
              const SizedBox(height: AppLayoutTokens.sectionGap),
              _FifoCommandCard(
                controller: _controller,
                focusNode: _focusNode,
                isLoading: provider.isLoading,
                includeExported: provider.includeExported,
                onIncludeExportedChanged: provider.setIncludeExported,
                onScan: _scan,
                onSearch: _search,
              ),
              const SizedBox(height: AppLayoutTokens.sectionGap),
              Expanded(
                child: _FifoResultPanel(
                  provider: provider,
                  onExportChanged: (item, exported) async {
                    await provider.setExported(item, exported);
                    _showErrorIfNeeded();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FifoHeader extends StatelessWidget {
  final FifoProvider provider;

  const _FifoHeader({required this.provider});

  @override
  Widget build(BuildContext context) {
    final result = provider.result;
    final resultCount = result == null
        ? 0
        : result.isSkuMode
        ? result.items.length
        : result.item == null
        ? 0
        : 1;
    final modeLabel = result == null
        ? 'Chưa kiểm tra'
        : result.isSkuMode
        ? 'SKU'
        : 'Serial';
    final statusLabel = switch (result?.status) {
      'correct' => 'Đúng FIFO',
      'wrong' => 'Sai FIFO',
      'exported' => 'Đã xuất',
      'display_reserved' => 'Trưng bày',
      _ => provider.includeExported ? 'Có đã xuất' : 'Chỉ còn tồn',
    };
    final statusColor = switch (result?.status) {
      'correct' => AppColors.success,
      'wrong' => AppColors.error,
      'exported' => AppColors.neutral600,
      'display_reserved' => AppColors.warning,
      _ => provider.includeExported ? AppColors.warning : AppColors.info,
    };
    final statusBackground = switch (result?.status) {
      'correct' => AppColors.successSurface,
      'wrong' => AppColors.errorSurface,
      'exported' => AppColors.neutral100,
      'display_reserved' => AppColors.warningSurface,
      _ =>
        provider.includeExported
            ? AppColors.warningSurface
            : AppColors.infoSurface,
    };

    return AppSurfaceCard(
      key: const Key('fifo-check-header'),
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
            child: const Icon(
              Icons.qr_code_scanner_rounded,
              color: AppColors.info,
            ),
          );
          final textBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kiểm tra FIFO', style: AppTextStyles.headingM),
              const SizedBox(height: 6),
              Text(
                'Nhập hoặc quét SKU/serial để kiểm tra thứ tự FIFO và trạng thái xuất kho.',
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
                    label: modeLabel,
                    color: result == null ? AppColors.warning : AppColors.info,
                    backgroundColor: result == null
                        ? AppColors.warningSurface
                        : AppColors.infoSurface,
                  ),
                  AppStatusChip(
                    label: '$resultCount sản phẩm',
                    color: AppColors.neutral700,
                    backgroundColor: AppColors.neutral100,
                  ),
                  AppStatusChip(
                    label: statusLabel,
                    color: statusColor,
                    backgroundColor: statusBackground,
                  ),
                  const AppStatusChip(
                    label: 'SKU/Serial',
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

class _FifoCommandCard extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isLoading;
  final bool includeExported;
  final ValueChanged<bool> onIncludeExportedChanged;
  final VoidCallback onScan;
  final VoidCallback onSearch;

  const _FifoCommandCard({
    required this.controller,
    required this.focusNode,
    required this.isLoading,
    required this.includeExported,
    required this.onIncludeExportedChanged,
    required this.onScan,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('fifo-check-command-card'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < AppLayoutTokens.compactBreakpoint;
          final input = AppTextInput(
            controller: controller,
            focusNode: focusNode,
            enabled: !isLoading,
            label: 'SKU hoặc serial',
            hintText: 'Nhập SKU hoặc serial',
            icon: Icons.inventory_2_outlined,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
          );
          final includeExportedToggle = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: includeExported
                  ? AppColors.warningSurface
                  : AppColors.neutral50,
              borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
              border: Border.all(
                color: includeExported
                    ? AppColors.warning.withValues(alpha: 0.32)
                    : AppColors.neutral200,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: AppColors.neutral600,
                ),
                const SizedBox(width: 8),
                Text(
                  'Hiển thị đã xuất kho',
                  style: AppTextStyles.labelM.copyWith(
                    color: AppColors.neutral700,
                  ),
                ),
                const SizedBox(width: 8),
                Switch.adaptive(
                  value: includeExported,
                  onChanged: isLoading ? null : onIncludeExportedChanged,
                ),
              ],
            ),
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
                onPressed: isLoading ? null : onSearch,
                icon: Icons.search_rounded,
                tooltip: 'Tìm FIFO',
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
                includeExportedToggle,
                const SizedBox(height: AppLayoutTokens.formFieldGap),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: input),
                  const SizedBox(width: AppLayoutTokens.formInlineGap),
                  actions,
                ],
              ),
              const SizedBox(height: AppLayoutTokens.cardGap),
              Align(
                alignment: Alignment.centerLeft,
                child: includeExportedToggle,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FifoResultPanel extends StatelessWidget {
  final FifoProvider provider;
  final Future<void> Function(FifoInventoryItem item, bool exported)
  onExportChanged;

  const _FifoResultPanel({
    required this.provider,
    required this.onExportChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (provider.isLoading) {
      return const AppSurfaceCard(
        child: AppStatePanel.loading(
          title: 'Đang kiểm tra FIFO',
          message: 'OpsHub đang đối chiếu thứ tự FIFO theo SKU/serial.',
        ),
      );
    }

    return AppSurfaceCard(
      key: const Key('fifo-check-results'),
      padding: EdgeInsets.zero,
      child: _ResultBody(
        result: provider.result,
        exportingIds: provider.exportingIds,
        onExportChanged: onExportChanged,
      ),
    );
  }
}

class _ResultBody extends StatelessWidget {
  final FifoCheckResult? result;
  final Set<String> exportingIds;
  final Future<void> Function(FifoInventoryItem item, bool exported)
  onExportChanged;

  const _ResultBody({
    required this.result,
    required this.exportingIds,
    required this.onExportChanged,
  });

  @override
  Widget build(BuildContext context) {
    final current = result;
    if (current == null) {
      return const AppStatePanel.empty(
        title: 'Nhập SKU hoặc serial để kiểm tra FIFO',
        message: 'Kết quả sẽ hiển thị thứ tự nhập kho, BIN và trạng thái xuất.',
        icon: Icons.inventory_2_outlined,
      );
    }
    if (current.isSkuMode) {
      return _SkuResultList(
        result: current,
        exportingIds: exportingIds,
        onExportChanged: onExportChanged,
      );
    }
    return _SerialResult(
      result: current,
      exportingIds: exportingIds,
      onExportChanged: onExportChanged,
    );
  }
}

// _EmptyState removed — now uses AppStatePanel.empty()

class _SkuResultList extends StatelessWidget {
  final FifoCheckResult result;
  final Set<String> exportingIds;
  final Future<void> Function(FifoInventoryItem item, bool exported)
  onExportChanged;

  const _SkuResultList({
    required this.result,
    required this.exportingIds,
    required this.onExportChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (result.items.isEmpty) {
      return const AppStatePanel.empty(
        title: 'Không tìm thấy SKU trong SR của bạn',
        message: 'Kiểm tra lại SKU hoặc bật tùy chọn hiển thị đã xuất kho.',
        icon: Icons.inventory_2_outlined,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: result.items.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${result.query} • ${result.srCode} • ${result.items.length} sản phẩm',
              style: AppTextStyles.titleEmphasis.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          );
        }
        final itemIndex = index - 1;
        final item = result.items[itemIndex];
        return _FifoItemCard(
          item: item,
          rank: itemIndex,
          total: result.items.length,
          isBusy: exportingIds.contains(item.id),
          onExportChanged: onExportChanged,
        );
      },
    );
  }
}

class _SerialResult extends StatelessWidget {
  final FifoCheckResult result;
  final Set<String> exportingIds;
  final Future<void> Function(FifoInventoryItem item, bool exported)
  onExportChanged;

  const _SerialResult({
    required this.result,
    required this.exportingIds,
    required this.onExportChanged,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (result.status) {
      'correct' => AppColors.success,
      'wrong' => AppColors.error,
      'exported' => AppColors.neutral500,
      'display_reserved' => AppColors.warning,
      _ => AppColors.warning,
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        AppSurfaceCard(
          backgroundColor: statusColor.withValues(alpha: 0.1),
          borderColor: statusColor.withValues(alpha: 0.5),
          child: Row(
            children: [
              Icon(_statusIcon(result.status), color: statusColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  result.message ?? 'Không có kết quả',
                  style: AppTextStyles.labelM.copyWith(color: statusColor),
                ),
              ),
            ],
          ),
        ),
        if (result.item != null) ...[
          const SizedBox(height: 12),
          _FifoItemCard(
            item: result.item!,
            rank: 0,
            total: 1,
            isBusy: exportingIds.contains(result.item!.id),
            onExportChanged: onExportChanged,
          ),
        ],
        if (_shouldShowSuggestedItem(result)) ...[
          const SizedBox(height: 16),
          Text(
            'Sản phẩm cần lấy trước',
            style: AppTextStyles.titleEmphasis.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          _FifoItemCard(
            item: result.suggestedItem!,
            rank: 0,
            total: 1,
            isBusy: exportingIds.contains(result.suggestedItem!.id),
            onExportChanged: onExportChanged,
          ),
        ],
      ],
    );
  }

  bool _shouldShowSuggestedItem(FifoCheckResult result) {
    return const bool.fromEnvironment('FIFO_SHOW_SUGGESTED_ITEM') &&
        result.suggestedItem != null;
  }

  IconData _statusIcon(String? status) {
    return switch (status) {
      'correct' => Icons.check_circle_rounded,
      'wrong' => Icons.error_rounded,
      'display_reserved' => Icons.storefront_rounded,
      'exported' => Icons.inventory_2_rounded,
      _ => Icons.search_off_rounded,
    };
  }
}

class _FifoItemCard extends StatelessWidget {
  final FifoInventoryItem item;
  final int rank;
  final int total;
  final bool isBusy;
  final Future<void> Function(FifoInventoryItem item, bool exported)
  onExportChanged;

  const _FifoItemCard({
    required this.item,
    required this.rank,
    required this.total,
    required this.isBusy,
    required this.onExportChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = item.exported
        ? AppColors.neutral500
        : _fifoColor(rank, total);
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
                            item.skuName.isNotEmpty ? item.skuName : item.sku,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.labelL.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (item.exported)
                          const AppStatusChip(label: 'Đã xuất')
                        else if (item.isFifo)
                          const AppStatusChip(label: 'FIFO'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        AppInfoChip(Icons.qr_code_rounded, item.serialNumber),
                        AppInfoChip(Icons.inventory_2_outlined, item.sku),
                        AppInfoChip(
                          Icons.calendar_today_outlined,
                          item.importDate,
                        ),
                        if (item.bin.isNotEmpty)
                          AppInfoChip(Icons.location_on_outlined, item.bin),
                        if (item.zone.isNotEmpty)
                          AppInfoChip(Icons.map_outlined, item.zone),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: item.exported,
                          onChanged: isBusy
                              ? null
                              : (value) =>
                                    onExportChanged(item, value ?? false),
                        ),
                        Expanded(
                          child: Text(
                            item.exported
                                ? 'Bỏ đánh dấu xuất kho'
                                : 'Đánh dấu xuất kho',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                        ),
                        if (isBusy)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
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
