import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../domain/entities/fifo_check_result.dart';
import '../../domain/entities/fifo_inventory_item.dart';
import '../providers/fifo_provider.dart';
import '../../../chat/presentation/widgets/barcode_scanner_screen.dart'
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
    return Scaffold(
      appBar: GradientHeader(
        title: 'Kiểm tra FIFO',
        showBack: true,
      ),
      body: SafeArea(
        child: Consumer<FifoProvider>(
          builder: (context, provider, _) {
            return AppResponsiveContent(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        _ResultBody(
                          result: provider.result,
                          exportingIds: provider.exportingIds,
                          onExportChanged: (item, exported) async {
                            await provider.setExported(item, exported);
                            _showErrorIfNeeded();
                          },
                        ),
                        if (provider.isLoading)
                          Positioned.fill(
                            child: ColoredBox(
                              color: Theme.of(
                                context,
                              ).scaffoldBackgroundColor.withValues(alpha: 0.7),
                              child: const AppStatePanel.loading(
                                title: 'Đang kiểm tra FIFO',
                                compact: true,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _FifoInputBar(
                    controller: _controller,
                    focusNode: _focusNode,
                    isLoading: provider.isLoading,
                    includeExported: provider.includeExported,
                    onIncludeExportedChanged: provider.setIncludeExported,
                    onScan: _scan,
                    onSearch: _search,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FifoInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isLoading;
  final bool includeExported;
  final ValueChanged<bool> onIncludeExportedChanged;
  final VoidCallback onScan;
  final VoidCallback onSearch;

  const _FifoInputBar({
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayoutTokens.actionBarMaxWidth,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: includeExported,
                  onChanged: isLoading ? null : onIncludeExportedChanged,
                  title: const Text('Hiển thị đã xuất kho'),
                  secondary: const Icon(Icons.inventory_2_outlined),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        enabled: !isLoading,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          hintText: 'Nhập SKU hoặc serial',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                        ),
                        onSubmitted: (_) => onSearch(),
                      ),
                    ),
                    const SizedBox(width: AppLayoutTokens.formInlineGap),
                    AppIconAction(
                      onPressed: isLoading ? null : onScan,
                      icon: Icons.qr_code_scanner_rounded,
                      tooltip: 'Quét mã',
                    ),
                    const SizedBox(width: AppLayoutTokens.formInlineGap),
                    AppIconAction(
                      onPressed: isLoading ? null : onSearch,
                      icon: Icons.search_rounded,
                      tooltip: 'Tìm',
                      filled: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
        Container(
          padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            border: Border.all(color: statusColor.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(_statusIcon(result.status), color: statusColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  result.message ?? 'Không có kết quả',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
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
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 8,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(8),
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
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
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
