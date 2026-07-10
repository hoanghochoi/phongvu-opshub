import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_combobox.dart';
import '../../../../app/widgets/app_filter_dropdowns.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_pagination.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/formatting/money_formatters.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/domain/entities/store_branch.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/sales_report.dart';
import '../providers/sales_report_provider.dart';
import '../widgets/sales_report_export_menu.dart';
import '../widgets/sales_report_workspace_header.dart';

class SalesReportAdminScreen extends StatefulWidget {
  final AuthRepository? authRepository;

  const SalesReportAdminScreen({super.key, this.authRepository});

  @override
  State<SalesReportAdminScreen> createState() => _SalesReportAdminScreenState();
}

class _SalesReportAdminScreenState extends State<SalesReportAdminScreen> {
  late final AuthRepository _authRepository =
      widget.authRepository ?? AuthRepository(ApiClient());
  final List<StoreBranch> _superAdminStores = [];
  bool _initialized = false;
  bool _isLoadingStoreOptions = false;
  String _reportType = 'ALL';
  String? _storeCode;
  String? _storeOptionsSessionKey;
  String? _storeOptionsErrorMessage;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final user = context.read<AuthProvider>().user;
    final provider = context.read<SalesReportProvider>();
    final today = provider.currentDate;
    _startDate = today;
    _endDate = today;
    unawaited(provider.initialize(user, admin: true, adminQuery: _query()));
  }

  SalesReportQuery _query({int page = 0, int limit = 20, String? exportType}) {
    return SalesReportQuery(
      reportType: _reportType,
      exportType: exportType,
      startDate: _startDate,
      endDate: _endDate,
      storeIds: _storeCode == null ? const [] : [_storeCode!],
      page: page,
      limit: limit,
    );
  }

  Future<void> _reload({int page = 0}) {
    final provider = context.read<SalesReportProvider>();
    return context.read<SalesReportProvider>().loadAdminList(
      query: _query(page: page, limit: provider.adminLimit),
    );
  }

  Future<void> _export(String exportType) {
    final provider = context.read<SalesReportProvider>();
    return context.read<SalesReportProvider>().exportXlsx(
      query: _query(limit: provider.adminLimit, exportType: exportType),
    );
  }

  void _setDateRange(DateTime? start, DateTime? end) {
    setState(() {
      _startDate = start;
      _endDate = end;
    });
    unawaited(_reload());
  }

  void _setStoreCode(String? value) {
    setState(() => _storeCode = _normalizeStoreCode(value));
    unawaited(_reload());
  }

  void _scheduleSuperAdminStoreOptionsLoad(User? user) {
    if (user?.isSuperAdmin != true) return;
    final key = user?.id?.trim().isNotEmpty == true
        ? user!.id!.trim()
        : user?.email.trim() ?? 'super-admin';
    if (_storeOptionsSessionKey == key || _isLoadingStoreOptions) return;
    _storeOptionsSessionKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadSuperAdminStoreOptions(user));
    });
  }

  Future<void> _loadSuperAdminStoreOptions(User? user) async {
    if (user?.isSuperAdmin != true) return;
    setState(() {
      _isLoadingStoreOptions = true;
      _storeOptionsErrorMessage = null;
    });
    final startedAt = DateTime.now();
    try {
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report admin SR filter load started',
        context: {
          'userId': user?.id,
          'role': user?.role,
          'assignedStoreCount': user?.assignedStores.length,
        },
      );
      final stores = await _authRepository.getStores();
      if (!mounted) return;
      setState(() {
        _superAdminStores
          ..clear()
          ..addAll(stores);
        _isLoadingStoreOptions = false;
      });
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report admin SR filter load succeeded',
        context: {
          'loadedStoreCount': stores.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingStoreOptions = false;
        _storeOptionsErrorMessage =
            'Chưa tải được danh sách showroom. Vui lòng tải lại.';
      });
      await AppLogger.instance.error(
        'SalesReport',
        'Sales report admin SR filter load failed',
        error: error,
        context: {
          'role': user?.role,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SalesReportProvider>();
    final user = context.watch<AuthProvider>().user;
    _scheduleSuperAdminStoreOptionsLoad(user);
    final storeOptions = _adminStoreOptionsFor(
      user,
      user?.isSuperAdmin == true ? _superAdminStores : const <StoreBranch>[],
    );
    final showStoreFilter =
        storeOptions.isNotEmpty ||
        user?.isSuperAdmin == true ||
        _isLoadingStoreOptions ||
        _storeOptionsErrorMessage != null;
    return AppResponsiveContent(
      maxWidth: AppLayoutTokens.pageMaxWidth,
      onRefresh: () => _reload(page: provider.adminPage),
      refreshLogSource: 'SalesReport',
      refreshLogContext: () => {
        'screen': 'admin',
        'page': provider.adminPage,
        'itemCount': provider.adminItems.length,
        'reportType': _reportType,
        'hasStoreFilter': _storeCode != null,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SalesReportWorkspaceHeader(
            key: const Key('sales-report-admin-workspace-header'),
            title: 'Báo cáo bán hàng',
            subtitle: '',
            icon: Icons.assignment_outlined,
            chips: [
              AppStatusChip(
                label: '${provider.adminTotal} báo cáo',
                color: AppColors.primary,
              ),
              AppStatusChip(
                label: 'Trang ${provider.adminPage + 1}',
                color: AppColors.neutral600,
              ),
              AppStatusChip(
                label: _reportTypeLabel(_reportType),
                color: AppColors.success,
              ),
              if (showStoreFilter)
                AppStatusChip(
                  label:
                      'Showroom: ${_storeFilterLabel(_storeCode, storeOptions)}',
                  color: AppColors.neutral600,
                ),
            ],
          ),
          const SizedBox(height: AppLayoutTokens.formInlineGap),
          _SalesReportAdminToolbar(
            reportType: _reportType,
            selectedStoreCode: _storeCode,
            storeOptions: storeOptions,
            showStoreFilter: showStoreFilter,
            isLoading: provider.isLoadingAdminList,
            isLoadingStores: _isLoadingStoreOptions,
            isExporting: provider.isExporting,
            storeOptionsErrorMessage: _storeOptionsErrorMessage,
            startDate: _startDate,
            endDate: _endDate,
            now: () => provider.currentDate,
            onReportTypeChanged: (value) {
              setState(() => _reportType = value);
              unawaited(_reload());
            },
            onStoreChanged: _setStoreCode,
            onDateRangeChanged: _setDateRange,
            onReload: () => _reload(),
            onReloadStores: () => _loadSuperAdminStoreOptions(user),
            onExport: _export,
          ),
          const SizedBox(height: AppLayoutTokens.cardGap),
          if (provider.errorMessage != null) ...[
            AppStatusBanner(
              icon: Icons.error_outline_rounded,
              title: 'Chưa tải được dữ liệu',
              message: provider.errorMessage!,
              tone: AppStateTone.error,
            ),
            const SizedBox(height: AppLayoutTokens.cardGap),
          ],
          Expanded(
            child: provider.isLoadingAdminList && provider.adminItems.isEmpty
                ? const AppListSkeleton(itemCount: 5)
                : provider.adminItems.isEmpty
                ? const AppStatePanel.empty(
                    title: 'Chưa có báo cáo',
                    message:
                        'Dữ liệu sẽ xuất hiện sau khi nhân viên bán hàng gửi báo cáo.',
                  )
                : ListView.separated(
                    key: const Key('sales-report-admin-list'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    primary: false,
                    padding: const EdgeInsets.only(
                      bottom: AppLayoutTokens.cardGap,
                    ),
                    itemCount: provider.adminItems.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppLayoutTokens.cardGap),
                    itemBuilder: (context, index) {
                      return _SalesReportAdminTile(
                        item: provider.adminItems[index],
                      );
                    },
                  ),
          ),
          const SizedBox(height: AppLayoutTokens.formInlineGap),
          SafeArea(
            top: false,
            child: AppPaginationControls(
              pageIndex: provider.adminPage,
              totalItems: provider.adminTotal,
              itemLabel: 'báo cáo',
              onPrevious: provider.canGoPrevious
                  ? () => _reload(page: provider.adminPage - 1)
                  : null,
              onNext: provider.canGoNext
                  ? () => _reload(page: provider.adminPage + 1)
                  : null,
              onRefresh: () => _reload(page: provider.adminPage),
              isRefreshing: provider.isLoadingAdminList,
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesReportAdminToolbar extends StatelessWidget {
  final String reportType;
  final String? selectedStoreCode;
  final List<AppComboboxOption<String>> storeOptions;
  final bool showStoreFilter;
  final bool isLoading;
  final bool isLoadingStores;
  final bool isExporting;
  final String? storeOptionsErrorMessage;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime Function() now;
  final ValueChanged<String> onReportTypeChanged;
  final ValueChanged<String?> onStoreChanged;
  final void Function(DateTime? start, DateTime? end) onDateRangeChanged;
  final Future<void> Function() onReload;
  final Future<void> Function() onReloadStores;
  final SalesReportExportCallback onExport;

  const _SalesReportAdminToolbar({
    required this.reportType,
    required this.selectedStoreCode,
    required this.storeOptions,
    required this.showStoreFilter,
    required this.isLoading,
    required this.isLoadingStores,
    required this.isExporting,
    required this.storeOptionsErrorMessage,
    required this.startDate,
    required this.endDate,
    required this.now,
    required this.onReportTypeChanged,
    required this.onStoreChanged,
    required this.onDateRangeChanged,
    required this.onReload,
    required this.onReloadStores,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < AppLayoutTokens.compactBreakpoint;
          final filters = <Widget>[
            _ToolbarSlot(
              width: 168,
              expand: compact,
              child: _ReportTypeFilter(
                value: reportType,
                enabled: !isLoading,
                onChanged: onReportTypeChanged,
              ),
            ),
            if (showStoreFilter)
              _ToolbarSlot(
                width: 180,
                expand: compact,
                child: _StoreFilter(
                  value: selectedStoreCode,
                  enabled:
                      !isLoading && !isLoadingStores && storeOptions.isNotEmpty,
                  isLoading: isLoadingStores,
                  errorMessage: storeOptionsErrorMessage,
                  options: storeOptions,
                  onChanged: onStoreChanged,
                  onRetry: onReloadStores,
                ),
              ),
            _ToolbarSlot(
              width: 220,
              expand: compact,
              child: AppDateRangeDropdown(
                label: 'Ngày',
                start: startDate,
                end: endDate,
                onChanged: onDateRangeChanged,
                now: now,
                showEmptyRangeHelperText: false,
              ),
            ),
          ];
          final actions = [
            SizedBox(
              width: compact ? double.infinity : 120,
              child: AppSecondaryButton(
                onPressed: isLoading ? null : onReload,
                icon: Icons.refresh_rounded,
                label: 'Tải lại',
                isLoading: isLoading,
              ),
            ),
            SizedBox(
              width: compact ? double.infinity : 132,
              child: SalesReportExportMenuButton(
                isExporting: isExporting,
                onExport: onExport,
              ),
            ),
          ];

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < filters.length; index++) ...[
                  if (index > 0)
                    const SizedBox(height: AppLayoutTokens.formInlineGap),
                  filters[index],
                ],
                const SizedBox(height: AppLayoutTokens.formInlineGap),
                AppActionRow(children: actions),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppLayoutTokens.formInlineGap,
                  runSpacing: AppLayoutTokens.formInlineGap,
                  children: filters,
                ),
              ),
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  actions.first,
                  const SizedBox(width: AppLayoutTokens.formInlineGap),
                  actions.last,
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ToolbarSlot extends StatelessWidget {
  final double width;
  final bool expand;
  final Widget child;

  const _ToolbarSlot({
    required this.width,
    required this.expand,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: expand ? double.infinity : width, child: child);
  }
}

String _reportTypeLabel(String value) {
  return switch (value) {
    'PURCHASED' => 'Mua hàng',
    'NOT_PURCHASED' => 'Chưa mua hàng',
    _ => 'Tất cả',
  };
}

class _ReportTypeFilter extends StatelessWidget {
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _ReportTypeFilter({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: !enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: AppCombobox<String>.single(
          label: 'Loại',
          value: value == 'ALL' ? null : value,
          emptyLabel: 'Tất cả',
          icon: Icons.tune_rounded,
          options: const [
            AppComboboxOption(value: 'PURCHASED', label: 'Mua hàng'),
            AppComboboxOption(value: 'NOT_PURCHASED', label: 'Chưa mua hàng'),
          ],
          onChanged: (next) => onChanged(next ?? 'ALL'),
        ),
      ),
    );
  }
}

class _StoreFilter extends StatelessWidget {
  final String? value;
  final bool enabled;
  final bool isLoading;
  final String? errorMessage;
  final List<AppComboboxOption<String>> options;
  final ValueChanged<String?> onChanged;
  final Future<void> Function() onRetry;

  const _StoreFilter({
    required this.value,
    required this.enabled,
    required this.isLoading,
    required this.errorMessage,
    required this.options,
    required this.onChanged,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final helperText =
        errorMessage ?? (isLoading ? 'Đang tải danh sách showroom' : null);
    final field = AppCombobox<String>.single(
      label: 'Showroom',
      value: value,
      emptyLabel: isLoading ? 'Đang tải showroom' : 'Tất cả showroom',
      icon: Icons.storefront_outlined,
      helperText: helperText,
      enabled: enabled,
      options: options,
      onChanged: onChanged,
    );
    if (errorMessage == null) return field;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: field),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Tải lại danh sách showroom',
          child: IconButton.outlined(
            onPressed: isLoading ? null : () => unawaited(onRetry()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
      ],
    );
  }
}

List<AppComboboxOption<String>> _adminStoreOptionsFor(
  User? user,
  List<StoreBranch> remoteStores,
) {
  final seen = <String>{};
  final options = <AppComboboxOption<String>>[];

  void addStore(String? rawCode, String? rawName) {
    final storeCode = _normalizeStoreCode(rawCode);
    if (storeCode == null || seen.contains(storeCode)) return;
    seen.add(storeCode);
    final storeName = rawName?.trim() ?? '';
    options.add(
      AppComboboxOption<String>(
        value: storeCode,
        label: _storeOptionLabel(storeCode, storeName),
        subtitle: storeName.isEmpty || storeName.toUpperCase() == storeCode
            ? null
            : storeName,
        searchKeywords: [storeCode, storeName],
      ),
    );
  }

  for (final store in user?.assignedStores ?? const <StoreBranch>[]) {
    addStore(store.storeId, store.storeName);
  }
  for (final store in remoteStores) {
    addStore(store.storeId, store.storeName);
  }
  addStore(user?.storeId, user?.storeName);
  options.sort((a, b) => a.value.compareTo(b.value));
  return options;
}

String? _normalizeStoreCode(String? value) {
  final text = value?.trim().toUpperCase();
  return text == null || text.isEmpty ? null : text;
}

String _storeOptionLabel(String storeCode, String storeName) {
  if (storeName.isEmpty || storeName.toUpperCase() == storeCode) {
    return storeCode;
  }
  return '$storeCode - $storeName';
}

String _storeFilterLabel(
  String? selectedStoreCode,
  List<AppComboboxOption<String>> options,
) {
  final selected = _normalizeStoreCode(selectedStoreCode);
  if (selected == null) return 'Tất cả showroom';
  for (final option in options) {
    if (option.value == selected) return option.label;
  }
  return selected;
}

class _SalesReportAdminTile extends StatelessWidget {
  final Map<String, dynamic> item;

  const _SalesReportAdminTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final reportType = item['reportType']?.toString() == 'PURCHASED'
        ? 'Mua hàng'
        : 'Chưa mua hàng';
    final categoryGroups = item['categoryGroups'] is List
        ? (item['categoryGroups'] as List)
              .whereType<Map>()
              .map((category) => category['catGroupNameVi']?.toString() ?? '')
              .where((label) => label.trim().isNotEmpty)
              .join(', ')
        : '';
    final category = categoryGroups.isNotEmpty
        ? categoryGroups
        : item['categoryGroupNameVi']?.toString() ?? '';
    final orderCode = item['orderCode']?.toString();
    final reporter =
        item['createdByName']?.toString() ??
        item['createdByEmail']?.toString() ??
        '';
    final storeCode = item['storeCode']?.toString() ?? '';
    final submittedAt = item['submittedAt']?.toString() ?? '';
    final customerTypeLabel = item['customerTypeLabel']?.toString() ?? '';
    final isStudent = item['customerIsStudent'] == true;
    final promotionLabels = item['promotionLabels'] is List
        ? (item['promotionLabels'] as List)
              .map((label) => label.toString())
              .where((label) => label.trim().isNotEmpty)
              .join(', ')
        : '';
    final installmentNeed = item['installmentNeed'] == true;
    final installmentApproved = item['installmentApproved'] == true
        ? 'Duyệt'
        : item['installmentApproved'] == false
        ? 'Không duyệt'
        : '';
    final loanAmount = formatVndAmount(item['installmentLoanAmount']);
    final noInstallmentReason =
        item['installmentNoInstallmentReasonLabel']?.toString() ?? '';
    final installmentLabel = item['installmentStatusLabel']?.toString() ?? '';
    final installmentFailureReason =
        item['installmentFailureReason']?.toString() ?? '';
    final installmentPartnerLabels = item['installmentPartnerLabels'] is List
        ? (item['installmentPartnerLabels'] as List)
              .map((label) => label.toString())
              .where((label) => label.trim().isNotEmpty)
              .join(', ')
        : '';
    return AppSurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            orderCode == null || orderCode.isEmpty
                ? Icons.person_search_outlined
                : Icons.receipt_long_outlined,
            color: orderCode == null || orderCode.isEmpty
                ? AppColors.warning
                : AppColors.success,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$reportType${orderCode?.isNotEmpty == true ? ' - $orderCode' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelM,
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    category,
                    storeCode,
                    reporter,
                  ].where((part) => part.trim().isNotEmpty).join(' • '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyM.copyWith(
                    color: AppColors.neutral600,
                  ),
                ),
                if (submittedAt.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    submittedAt,
                    style: AppTextStyles.labelS.copyWith(
                      color: AppColors.neutral500,
                    ),
                  ),
                ],
                if (customerTypeLabel.isNotEmpty ||
                    isStudent ||
                    promotionLabels.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (customerTypeLabel.isNotEmpty) customerTypeLabel,
                      if (isStudent) 'Học sinh - Sinh viên',
                      if (promotionLabels.isNotEmpty) promotionLabels,
                    ].join(' - '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelS.copyWith(
                      color: AppColors.neutral600,
                    ),
                  ),
                ],
                if (installmentNeed || installmentLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (installmentNeed) 'Có nhu cầu trả góp',
                      if (installmentApproved.isNotEmpty) installmentApproved,
                      if (loanAmount.isNotEmpty) 'Vay $loanAmount',
                      installmentLabel,
                      if (installmentPartnerLabels.isNotEmpty)
                        installmentPartnerLabels,
                      if (noInstallmentReason.isNotEmpty) noInstallmentReason,
                      if (installmentFailureReason.isNotEmpty)
                        installmentFailureReason,
                    ].where((part) => part.trim().isNotEmpty).join(' - '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelS.copyWith(
                      color: AppColors.neutral600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
