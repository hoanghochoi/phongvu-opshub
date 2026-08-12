import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/storage/app_storage_keys.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_command_bar.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../domain/entities/fifo_check_result.dart';
import '../../domain/entities/fifo_inventory_item.dart';
import '../providers/fifo_provider.dart';
import '../../../fifo_check/presentation/widgets/barcode_scanner_screen.dart'
    show showBarcodeScanner;

class FifoCheckScreen extends StatefulWidget {
  const FifoCheckScreen({super.key});

  @override
  State<FifoCheckScreen> createState() => _FifoCheckScreenState();
}

class _FifoCheckScreenState extends State<FifoCheckScreen> {
  static const _recentSearchStorageKey = 'fifo_check_recent_searches';
  static const _maxRecentSearches = 5;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<String> _recentSearches = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecentSearches());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecentSearches() async {
    await AppLogger.instance.info('FIFO', 'FIFO recent searches load started');
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored =
          prefs.getStringList(AppStorageKeys.shared(_recentSearchStorageKey)) ??
          const [];
      final recentSearches = _normalizeRecentSearches(stored);
      if (mounted) {
        setState(() => _recentSearches = recentSearches);
      }
      await AppLogger.instance.info(
        'FIFO',
        'FIFO recent searches load succeeded',
        context: {'count': recentSearches.length},
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'FIFO',
        'FIFO recent searches load failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _scan() async {
    final result = await showBarcodeScanner(context);
    if (result == null || !mounted) return;
    _controller.text = result.trim().toUpperCase();
    await _search();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    _focusNode.unfocus();
    final provider = context.read<FifoProvider>();
    await provider.check(query);
    final hasError = provider.error != null;
    _showErrorIfNeeded();
    if (!hasError) await _rememberRecentSearch(query);
  }

  Future<void> _selectRecentSearch(String query) async {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    await AppLogger.instance.info(
      'FIFO',
      'FIFO recent search selected',
      context: {'queryLength': query.length},
    );
    await _search();
  }

  Future<void> _refreshScreen() async {
    await _loadRecentSearches();
    if (_controller.text.trim().isNotEmpty) {
      await _search();
    }
  }

  Future<void> _rememberRecentSearch(String rawQuery) async {
    final query = _normalizeRecentSearch(rawQuery);
    if (query.isEmpty) return;
    final updated = _normalizeRecentSearches([query, ..._recentSearches]);
    if (mounted) {
      setState(() => _recentSearches = updated);
    }
    await AppLogger.instance.info(
      'FIFO',
      'FIFO recent searches save started',
      context: {'count': updated.length, 'queryLength': query.length},
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        AppStorageKeys.shared(_recentSearchStorageKey),
        updated,
      );
      await AppLogger.instance.info(
        'FIFO',
        'FIFO recent searches save succeeded',
        context: {'count': updated.length},
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'FIFO',
        'FIFO recent searches save failed',
        error: error,
        stackTrace: stackTrace,
        context: {'count': updated.length},
      );
    }
  }

  List<String> _normalizeRecentSearches(Iterable<String> values) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final value in values) {
      final query = _normalizeRecentSearch(value);
      if (query.isEmpty || !seen.add(query)) continue;
      normalized.add(query);
      if (normalized.length == _maxRecentSearches) break;
    }
    return normalized;
  }

  String _normalizeRecentSearch(String value) {
    return value.trim().toUpperCase();
  }

  void _showErrorIfNeeded() {
    final provider = context.read<FifoProvider>();
    final error = provider.error;
    if (error == null || !mounted) return;
    AppToast.show(
      context,
      SnackBar(
        content: Text(error),
        backgroundColor: AppColors.errorOf(context),
      ),
    );
    provider.clearError();
  }

  @override
  Widget build(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    return Consumer<FifoProvider>(
      builder: (context, provider, _) {
        final resultPanel = _FifoResultPanel(
          provider: provider,
          onExportChanged: (item, exported) async {
            await provider.setExported(item, exported);
            _showErrorIfNeeded();
          },
        );
        final contentSizedCompactSerial =
            viewportWidth < 600 &&
            provider.result?.isSerialMode == true &&
            provider.result?.item != null;
        return AppResponsiveContent(
          maxWidth: AppLayoutTokens.commandWorkspaceMaxWidth,
          padding: AppLayoutTokens.pagePaddingFor(viewportWidth),
          onRefresh: _refreshScreen,
          refreshLogSource: 'FIFO',
          refreshLogContext: () => {
            'hasQuery': _controller.text.trim().isNotEmpty,
            'hasResult': provider.result != null,
            'recentSearchCount': _recentSearches.length,
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: _recentSearches.isEmpty ? 172 : 204,
                child: _FifoCommandCard(
                  controller: _controller,
                  focusNode: _focusNode,
                  isLoading: provider.isLoading,
                  includeExported: provider.includeExported,
                  onIncludeExportedChanged: provider.setIncludeExported,
                  onScan: _scan,
                  onSearch: _search,
                  recentSearches: _recentSearches,
                  showRecentSearches: _recentSearches.isNotEmpty,
                  onRecentSearchSelected: _selectRecentSearch,
                ),
              ),
              const SizedBox(height: 16),
              if (contentSizedCompactSerial)
                resultPanel
              else
                SizedBox(
                  height: _fifoResultHeight(result: provider.result),
                  child: resultPanel,
                ),
            ],
          ),
        );
      },
    );
  }

  double _fifoResultHeight({required FifoCheckResult? result}) {
    if (result?.isSerialMode == true && result?.item != null) {
      return 248;
    }
    return 340;
  }
}

class _FifoSwitchRow extends StatelessWidget {
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _FifoSwitchRow({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: Semantics(
            container: true,
            toggled: value,
            label: 'Hiển thị đã xuất kho',
            child: Center(
              // Scale only the paint; retain the native 48 px hit test area.
              child: Transform.scale(
                scale: 0.77,
                transformHitTests: false,
                child: Switch(
                  value: value,
                  onChanged: enabled ? onChanged : null,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Hiển thị đã xuất kho',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelM.copyWith(
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
        ),
      ],
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
  final List<String> recentSearches;
  final bool showRecentSearches;
  final ValueChanged<String> onRecentSearchSelected;

  const _FifoCommandCard({
    required this.controller,
    required this.focusNode,
    required this.isLoading,
    required this.includeExported,
    required this.onIncludeExportedChanged,
    required this.onScan,
    required this.onSearch,
    required this.recentSearches,
    required this.showRecentSearches,
    required this.onRecentSearchSelected,
  });

  @override
  Widget build(BuildContext context) {
    final recentSearchBar = showRecentSearches && recentSearches.isNotEmpty
        ? _RecentSearchChips(
            searches: recentSearches,
            enabled: !isLoading,
            onSelected: onRecentSearchSelected,
          )
        : null;
    return Material(
      key: const Key('fifo-check-command-card'),
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCommandBar(
            key: const Key('fifo-check-command-bar'),
            controller: controller,
            focusNode: focusNode,
            isLoading: isLoading,
            label: 'SKU hoặc serial',
            hintText: 'SKU-12345',
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) => onSearch(),
            onScan: onScan,
            onPrimaryAction: onSearch,
            scanTooltip: 'Quét mã',
            primaryActionTooltip: 'Tìm FIFO',
          ),
          const SizedBox(height: 16),
          SizedBox(
            key: const Key('fifo-check-exported-toggle'),
            height: 48,
            child: _FifoSwitchRow(
              value: includeExported,
              enabled: !isLoading,
              onChanged: onIncludeExportedChanged,
            ),
          ),
          if (recentSearchBar != null) ...[
            const SizedBox(height: 8),
            SizedBox(height: 24, child: recentSearchBar),
          ],
        ],
      ),
    );
  }
}

class _RecentSearchChips extends StatelessWidget {
  final List<String> searches;
  final bool enabled;
  final ValueChanged<String> onSelected;

  const _RecentSearchChips({
    required this.searches,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final mobileDensity = MediaQuery.sizeOf(context).width < 600;
    return Semantics(
      container: true,
      label: 'Tra cứu gần đây',
      child: SingleChildScrollView(
        key: const Key('fifo-check-recent-searches'),
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          height: mobileDensity ? 48 : 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Tra cứu gần đây',
                style:
                    (mobileDensity
                            ? AppTextStyles.labelS
                            : AppTextStyles.labelM)
                        .copyWith(color: AppColors.textSecondaryOf(context)),
              ),
              SizedBox(width: mobileDensity ? 6 : 8),
              for (var index = 0; index < searches.length; index++) ...[
                AppActionPill(
                  key: ValueKey('fifo-check-recent-${searches[index]}'),
                  label: searches[index],
                  mobileDensity: mobileDensity,
                  onPressed: enabled ? () => onSelected(searches[index]) : null,
                ),
                if (index < searches.length - 1)
                  SizedBox(width: mobileDensity ? 6 : 8),
              ],
            ],
          ),
        ),
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
      return AppSurfaceCard(
        key: const Key('fifo-check-results'),
        backgroundColor: AppColors.cardOf(context),
        borderColor: AppColors.subtleBorderOf(context),
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: AppStatePanel.loading(
          title: 'Đang kiểm tra FIFO',
          message: 'OpsHub đang đối chiếu thứ tự FIFO theo SKU/serial.',
        ),
      );
    }

    if (provider.result?.isSerialMode == true &&
        provider.result?.item != null) {
      return SizedBox(
        key: const Key('fifo-check-results'),
        width: double.infinity,
        child: _ResultBody(
          result: provider.result,
          exportingIds: provider.exportingIds,
          onExportChanged: onExportChanged,
        ),
      );
    }

    return AppSurfaceCard(
      key: const Key('fifo-check-results'),
      backgroundColor: AppColors.cardOf(context),
      borderColor: AppColors.subtleBorderOf(context),
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 1),
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
        icon: PhosphorIconsRegular.package,
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
        title: 'Không tìm thấy SKU trong showroom của bạn',
        message: 'Kiểm tra lại SKU hoặc bật tùy chọn hiển thị đã xuất kho.',
        icon: PhosphorIconsRegular.package,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          children: [
            Text(
              '${result.query} • ${result.srCode} • ${result.items.length} sản phẩm',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelL.copyWith(
                fontSize: 16,
                height: 20 / 16,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < result.items.length; index++) ...[
              _FifoCompactItem(
                key: ValueKey('fifo-compact-item-${result.items[index].id}'),
                item: result.items[index],
                compact: constraints.maxWidth < 600,
              ),
              if (index < result.items.length - 1) const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _FifoCompactItem extends StatelessWidget {
  final FifoInventoryItem item;
  final bool compact;

  const _FifoCompactItem({
    super.key,
    required this.item,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final badgeLabel = item.exported ? 'Đã xuất' : 'FIFO';
    final badgeTone = item.exported ? 'info' : 'success';
    final importDate = DateFormatter.format(item.importDate);
    final productName = item.skuName.isNotEmpty ? item.skuName : item.sku;
    final metadata = <Widget>[
      AppMetadataPill(
        icon: PhosphorIconsRegular.qrCode,
        text: item.serialNumber,
        mobileDensity: compact,
      ),
      AppMetadataPill(
        icon: PhosphorIconsRegular.mapPin,
        text: item.bin,
        mobileDensity: compact,
      ),
      AppMetadataPill(
        icon: PhosphorIconsRegular.calendarBlank,
        text: importDate,
        mobileDensity: compact,
      ),
    ];

    return Container(
      key: ValueKey('fifo-sku-item-card-${item.id}'),
      constraints: BoxConstraints(minHeight: compact ? 124 : 82),
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        border: Border.all(color: AppColors.subtleBorderOf(context)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        productName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelM.copyWith(height: 20 / 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _FifoBadge(
                      label: badgeLabel,
                      tone: badgeTone,
                      mobileDensity: true,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 0, children: metadata),
              ],
            )
          : Row(
              children: [
                SizedBox(
                  width: 320,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        productName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelM,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.binType.isEmpty
                            ? 'Chưa có loại hàng'
                            : item.binType,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyS.copyWith(
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(spacing: 12, runSpacing: 12, children: metadata),
                ),
                const SizedBox(width: 12),
                _FifoBadge(label: badgeLabel, tone: badgeTone),
              ],
            ),
    );
  }
}

class _FifoBadge extends StatelessWidget {
  final String label;
  final String tone;
  final bool mobileDensity;

  const _FifoBadge({
    super.key,
    required this.label,
    required this.tone,
    this.mobileDensity = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.statusColorOf(context, tone);
    return Container(
      height: mobileDensity ? 30 : 28,
      padding: EdgeInsets.symmetric(horizontal: mobileDensity ? 10 : 10),
      decoration: BoxDecoration(
        color: AppColors.statusSurfaceOf(context, tone),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: AppTextStyles.labelS.copyWith(color: color),
      ),
    );
  }
}

class _SerialCorrectResult extends StatelessWidget {
  final FifoCheckResult result;
  final FifoInventoryItem item;
  final bool isBusy;
  final Future<void> Function(FifoInventoryItem item, bool exported)
  onExportChanged;
  final String statusLabel;
  final String statusTone;
  final String? itemBadgeLabel;
  final String? itemBadgeTone;

  const _SerialCorrectResult({
    required this.result,
    required this.item,
    required this.isBusy,
    required this.onExportChanged,
    this.statusLabel = 'Đúng FIFO',
    this.statusTone = 'success',
    this.itemBadgeLabel,
    this.itemBadgeTone,
  });

  Future<void> _copyMetadata(
    BuildContext context, {
    required String field,
    required String fieldLabel,
    required String value,
  }) async {
    final startedAt = DateTime.now();
    final logContext = <String, Object?>{
      'field': field,
      'inventoryId': item.id,
      'valueLength': value.length,
    };
    await AppLogger.instance.info(
      'FIFO',
      'FIFO serial result metadata copy started',
      context: logContext,
    );
    try {
      await Clipboard.setData(ClipboardData(text: value));
      await AppLogger.instance.info(
        'FIFO',
        'FIFO serial result metadata copy succeeded',
        context: {
          ...logContext,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (!context.mounted) return;
      AppToast.show(
        context,
        SnackBar(content: Text('Đã sao chép $fieldLabel.')),
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'FIFO',
        'FIFO serial result metadata copy failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          ...logContext,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (!context.mounted) return;
      AppToast.show(
        context,
        SnackBar(
          content: Text('Chưa sao chép được $fieldLabel. Vui lòng thử lại.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final age = DateFormatter.daysSince(item.importDate);
        final ageLabel = age == null ? 'Tồn chưa rõ' : 'Tồn $age ngày';
        final accentColor = AppColors.statusColorOf(context, statusTone);

        return Container(
          key: const Key('fifo-serial-result-card'),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(12),
          ),
          foregroundDecoration: BoxDecoration(
            border: Border.all(color: AppColors.subtleBorderOf(context)),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: compact ? 7 : 8,
                    child: ColoredBox(color: accentColor),
                  ),
                  Expanded(
                    child: Padding(
                      padding: compact
                          ? const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            )
                          : const EdgeInsets.all(23),
                      child: compact
                          ? _CompactSerialResultBody(
                              item: item,
                              ageLabel: ageLabel,
                              statusLabel: statusLabel,
                              statusTone: statusTone,
                              isBusy: isBusy,
                              onCopy: (field, fieldLabel, value) =>
                                  _copyMetadata(
                                    context,
                                    field: field,
                                    fieldLabel: fieldLabel,
                                    value: value,
                                  ),
                              onExportChanged: onExportChanged,
                            )
                          : _DesktopSerialResultBody(
                              item: item,
                              ageLabel: ageLabel,
                              statusLabel: statusLabel,
                              statusTone: statusTone,
                              isBusy: isBusy,
                              onCopy: (field, fieldLabel, value) =>
                                  _copyMetadata(
                                    context,
                                    field: field,
                                    fieldLabel: fieldLabel,
                                    value: value,
                                  ),
                              onExportChanged: onExportChanged,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SerialWrongOrderResult extends StatelessWidget {
  final FifoCheckResult result;
  final FifoInventoryItem item;
  final bool isBusy;
  final Future<void> Function(FifoInventoryItem item, bool exported)
  onExportChanged;

  const _SerialWrongOrderResult({
    required this.result,
    required this.item,
    required this.isBusy,
    required this.onExportChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _SerialCorrectResult(
      result: result,
      item: item,
      isBusy: isBusy,
      onExportChanged: onExportChanged,
      statusLabel: 'Sai FIFO',
      statusTone: 'error',
    );
  }
}

typedef _CopyMetadata =
    Future<void> Function(String field, String fieldLabel, String value);

class _CompactSerialResultBody extends StatelessWidget {
  final FifoInventoryItem item;
  final String ageLabel;
  final String statusLabel;
  final String statusTone;
  final bool isBusy;
  final _CopyMetadata onCopy;
  final Future<void> Function(FifoInventoryItem item, bool exported)
  onExportChanged;

  const _CompactSerialResultBody({
    required this.item,
    required this.ageLabel,
    required this.statusLabel,
    required this.statusTone,
    required this.isBusy,
    required this.onCopy,
    required this.onExportChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          key: const Key('fifo-mobile-product-title'),
          item.skuName.isEmpty ? item.sku : item.skuName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.labelM.copyWith(height: 26 / 14),
        ),
        const SizedBox(height: 4),
        _FifoBadge(
          key: const Key('fifo-mobile-status-pill'),
          label: statusLabel,
          tone: statusTone,
          mobileDensity: true,
        ),
        const SizedBox(height: 4),
        SizedBox(
          key: const Key('fifo-mobile-metadata-rows'),
          width: double.infinity,
          child: Wrap(
            spacing: 10,
            runSpacing: 0,
            children: [
              AppMetadataPill(
                key: ValueKey('fifo-copy-serial-${item.id}'),
                icon: PhosphorIconsRegular.qrCode,
                text: item.serialNumber,
                mobileDensity: true,
                tooltip: 'Sao chép serial',
                semanticsLabel: 'Sao chép serial ${item.serialNumber}',
                onTap: () =>
                    unawaited(onCopy('serial', 'serial', item.serialNumber)),
              ),
              AppMetadataPill(
                key: ValueKey('fifo-copy-sku-${item.id}'),
                icon: PhosphorIconsRegular.package,
                text: item.sku,
                mobileDensity: true,
                tooltip: 'Sao chép SKU',
                semanticsLabel: 'Sao chép SKU ${item.sku}',
                onTap: () => unawaited(onCopy('sku', 'SKU', item.sku)),
              ),
              AppMetadataPill(
                key: const Key('fifo-import-date-pill'),
                icon: PhosphorIconsRegular.calendarBlank,
                text: DateFormatter.format(item.importDate),
                mobileDensity: true,
              ),
              AppMetadataPill(
                key: const Key('fifo-age-pill'),
                icon: PhosphorIconsRegular.clock,
                text: ageLabel,
                mobileDensity: true,
              ),
              AppMetadataPill(
                key: ValueKey('fifo-copy-location-${item.id}'),
                icon: PhosphorIconsRegular.mapPin,
                text: item.bin,
                mobileDensity: true,
                tooltip: 'Sao chép vị trí',
                semanticsLabel: 'Sao chép vị trí ${item.bin}',
                onTap: () => unawaited(onCopy('location', 'vị trí', item.bin)),
              ),
              AppMetadataPill(
                key: const Key('fifo-bin-type-pill'),
                icon: PhosphorIconsRegular.mapTrifold,
                text: item.binType,
                mobileDensity: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        _FifoExportRow(
          item: item,
          isBusy: isBusy,
          compact: true,
          onExportChanged: onExportChanged,
        ),
      ],
    );
  }
}

class _DesktopSerialResultBody extends StatelessWidget {
  final FifoInventoryItem item;
  final String ageLabel;
  final String statusLabel;
  final String statusTone;
  final bool isBusy;
  final _CopyMetadata onCopy;
  final Future<void> Function(FifoInventoryItem item, bool exported)
  onExportChanged;

  const _DesktopSerialResultBody({
    required this.item,
    required this.ageLabel,
    required this.statusLabel,
    required this.statusTone,
    required this.isBusy,
    required this.onCopy,
    required this.onExportChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 28,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Text(
                  item.skuName.isEmpty ? item.sku : item.skuName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.headingM,
                ),
              ),
              _FifoBadge(label: statusLabel, tone: statusTone),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          key: const Key('fifo-desktop-metadata-wrap'),
          width: double.infinity,
          height: 92,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              AppMetadataPill(
                key: ValueKey('fifo-copy-serial-${item.id}'),
                icon: PhosphorIconsRegular.qrCode,
                text: item.serialNumber,
                mobileDensity: false,
                tooltip: 'Sao chép serial',
                onTap: () =>
                    unawaited(onCopy('serial', 'serial', item.serialNumber)),
              ),
              AppMetadataPill(
                key: ValueKey('fifo-copy-sku-${item.id}'),
                icon: PhosphorIconsRegular.package,
                text: item.sku,
                mobileDensity: false,
                tooltip: 'Sao chép SKU',
                onTap: () => unawaited(onCopy('sku', 'SKU', item.sku)),
              ),
              AppMetadataPill(
                icon: PhosphorIconsRegular.calendarBlank,
                text: DateFormatter.format(item.importDate),
                mobileDensity: false,
              ),
              AppMetadataPill(
                icon: PhosphorIconsRegular.clock,
                text: ageLabel,
                mobileDensity: false,
              ),
              AppMetadataPill(
                key: ValueKey('fifo-copy-location-${item.id}'),
                icon: PhosphorIconsRegular.mapPin,
                text: item.bin,
                mobileDensity: false,
                tooltip: 'Sao chép vị trí',
                onTap: () => unawaited(onCopy('location', 'vị trí', item.bin)),
              ),
              AppMetadataPill(
                icon: PhosphorIconsRegular.mapTrifold,
                text: item.binType,
                mobileDensity: false,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _FifoExportRow(
          item: item,
          isBusy: isBusy,
          compact: false,
          onExportChanged: onExportChanged,
        ),
      ],
    );
  }
}

class _FifoExportRow extends StatelessWidget {
  final FifoInventoryItem item;
  final bool isBusy;
  final bool compact;
  final Future<void> Function(FifoInventoryItem item, bool exported)
  onExportChanged;

  const _FifoExportRow({
    required this.item,
    required this.isBusy,
    required this.compact,
    required this.onExportChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('fifo-export-control'),
      height: compact ? 40 : 48,
      child: InkWell(
        onTap: isBusy
            ? null
            : () => unawaited(onExportChanged(item, !item.exported)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: compact ? 40 : 48,
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: Checkbox(
                    value: item.exported,
                    onChanged: isBusy
                        ? null
                        : (value) =>
                              unawaited(onExportChanged(item, value ?? false)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ),
            SizedBox(width: compact ? 8 : 12),
            Flexible(
              child: Text(
                item.exported ? 'Bỏ đánh dấu xuất kho' : 'Đánh dấu xuất kho',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelM.copyWith(
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SerialNotFoundResult extends StatelessWidget {
  const _SerialNotFoundResult();

  @override
  Widget build(BuildContext context) {
    return const AppStatePanel.empty(
      title: 'Không tìm thấy kết quả',
      message: 'Hãy đổi từ khóa hoặc bật hiển thị đã xuất kho để thử lại.',
      icon: PhosphorIconsRegular.magnifyingGlass,
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
    // Approved R1 serial frames cover the result status variants below. Keep
    // the provider's existing fallback path for unexpected status values.
    if (result.status == 'correct' && result.item != null) {
      return _SerialCorrectResult(
        result: result,
        item: result.item!,
        isBusy: exportingIds.contains(result.item!.id),
        onExportChanged: onExportChanged,
      );
    }
    if (result.status == 'wrong' && result.item != null) {
      return _SerialWrongOrderResult(
        result: result,
        item: result.item!,
        isBusy: exportingIds.contains(result.item!.id),
        onExportChanged: onExportChanged,
      );
    }
    if (result.status == 'exported' && result.item != null) {
      return _SerialCorrectResult(
        result: result,
        item: result.item!,
        isBusy: exportingIds.contains(result.item!.id),
        onExportChanged: onExportChanged,
        statusLabel: 'Đã xuất kho',
        statusTone: 'info',
      );
    }
    if (result.status == 'display_reserved' && result.item != null) {
      return _SerialCorrectResult(
        result: result,
        item: result.item!,
        isBusy: exportingIds.contains(result.item!.id),
        onExportChanged: onExportChanged,
        statusLabel: 'Hàng trưng bày chỉ định',
        statusTone: 'warning',
        itemBadgeLabel: 'Trưng bày',
        itemBadgeTone: 'warning',
      );
    }
    if (result.status == 'not_found') {
      return const _SerialNotFoundResult();
    }

    final statusColor = switch (result.status) {
      'correct' => AppColors.successOf(context),
      'wrong' => AppColors.errorOf(context),
      'exported' => AppColors.neutral500Of(context),
      'display_reserved' => AppColors.warningOf(context),
      _ => AppColors.warningOf(context),
    };

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
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
      'correct' => PhosphorIconsRegular.checkCircle,
      'wrong' => PhosphorIconsRegular.xCircle,
      'display_reserved' => PhosphorIconsRegular.storefront,
      'exported' => PhosphorIconsRegular.package,
      _ => PhosphorIconsRegular.magnifyingGlass,
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

  Future<void> _copyMetadata(
    BuildContext context, {
    required String field,
    required String fieldLabel,
    required String value,
  }) async {
    final startedAt = DateTime.now();
    final logContext = <String, Object?>{
      'field': field,
      'inventoryId': item.id,
      'valueLength': value.length,
    };
    await AppLogger.instance.info(
      'FIFO',
      'FIFO item metadata copy started',
      context: logContext,
    );
    try {
      await Clipboard.setData(ClipboardData(text: value));
      await AppLogger.instance.info(
        'FIFO',
        'FIFO item metadata copy succeeded',
        context: {
          ...logContext,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (!context.mounted) return;
      AppToast.show(
        context,
        SnackBar(content: Text('Đã sao chép $fieldLabel.')),
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'FIFO',
        'FIFO item metadata copy failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          ...logContext,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (!context.mounted) return;
      AppToast.show(
        context,
        SnackBar(
          content: Text('Chưa sao chép được $fieldLabel. Vui lòng thử lại.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = item.exported
        ? AppColors.neutral500Of(context)
        : _fifoColor(context, rank, total);
    final ageLabel = DateFormatter.inventoryAgeLabel(item.importDate);
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
                        AppInfoChip(
                          PhosphorIconsRegular.qrCode,
                          item.serialNumber,
                          key: ValueKey('fifo-copy-serial-${item.id}'),
                          tooltip: 'Sao chép serial',
                          semanticsLabel: 'Serial ${item.serialNumber}',
                          onTap: () => unawaited(
                            _copyMetadata(
                              context,
                              field: 'serial',
                              fieldLabel: 'serial',
                              value: item.serialNumber,
                            ),
                          ),
                        ),
                        AppInfoChip(PhosphorIconsRegular.package, item.sku),
                        AppInfoChip(
                          PhosphorIconsRegular.calendar,
                          item.importDate,
                        ),
                        if (ageLabel != null)
                          AppInfoChip(PhosphorIconsRegular.timer, ageLabel),
                        if (item.bin.isNotEmpty)
                          AppInfoChip(
                            PhosphorIconsRegular.mapPin,
                            item.bin,
                            key: ValueKey('fifo-copy-location-${item.id}'),
                            tooltip: 'Sao chép vị trí',
                            semanticsLabel: 'Vị trí ${item.bin}',
                            onTap: () => unawaited(
                              _copyMetadata(
                                context,
                                field: 'location',
                                fieldLabel: 'vị trí',
                                value: item.bin,
                              ),
                            ),
                          ),
                        if (item.zone.isNotEmpty)
                          AppInfoChip(
                            PhosphorIconsRegular.mapTrifold,
                            item.zone,
                          ),
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

  Color _fifoColor(BuildContext context, int rank, int total) {
    if (total <= 1) return AppColors.successOf(context);
    final t = rank / (total - 1);
    return Color.lerp(
          AppColors.successOf(context),
          AppColors.errorOf(context),
          t,
        ) ??
        AppColors.errorOf(context);
  }
}
