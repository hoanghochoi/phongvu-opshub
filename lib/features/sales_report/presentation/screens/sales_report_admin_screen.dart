import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/formatting/money_formatters.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/sales_report.dart';
import '../providers/sales_report_provider.dart';

class SalesReportAdminScreen extends StatefulWidget {
  const SalesReportAdminScreen({super.key});

  @override
  State<SalesReportAdminScreen> createState() => _SalesReportAdminScreenState();
}

class _SalesReportAdminScreenState extends State<SalesReportAdminScreen> {
  bool _initialized = false;
  String _reportType = 'ALL';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final user = context.read<AuthProvider>().user;
    unawaited(
      context.read<SalesReportProvider>().initialize(user, admin: true),
    );
  }

  Future<void> _reload() {
    return context.read<SalesReportProvider>().loadAdminList(
      query: SalesReportQuery(reportType: _reportType),
    );
  }

  Future<void> _export() {
    return context.read<SalesReportProvider>().exportCsv(
      query: SalesReportQuery(reportType: _reportType),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SalesReportProvider>();
    return Scaffold(
      appBar: const GradientHeader(title: 'Báo cáo sale', showBack: true),
      body: AppResponsiveScrollView(
        maxWidth: AppLayoutTokens.pageMaxWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSurfaceCard(
              child: AppActionRow(
                children: [
                  _ReportTypeFilter(
                    value: _reportType,
                    enabled: !provider.isLoadingAdminList,
                    onChanged: (value) {
                      setState(() => _reportType = value);
                      unawaited(_reload());
                    },
                  ),
                  AppSecondaryButton(
                    onPressed: provider.isLoadingAdminList ? null : _reload,
                    icon: Icons.refresh_rounded,
                    label: 'Tải lại',
                    isLoading: provider.isLoadingAdminList,
                  ),
                  AppSecondaryButton(
                    onPressed: provider.isExporting ? null : _export,
                    icon: Icons.download_rounded,
                    label: 'Xuất CSV',
                    isLoading: provider.isExporting,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppLayoutTokens.cardGap),
            if (provider.errorMessage != null)
              AppStatusBanner(
                icon: Icons.error_outline_rounded,
                title: 'Chưa tải được dữ liệu',
                message: provider.errorMessage!,
                tone: AppStateTone.error,
              ),
            if (provider.isLoadingAdminList && provider.adminItems.isEmpty)
              const AppListSkeleton(itemCount: 5)
            else if (provider.adminItems.isEmpty)
              const AppStatePanel.empty(
                title: 'Chưa có báo cáo',
                message: 'Dữ liệu sẽ xuất hiện sau khi sale gửi báo cáo.',
              )
            else
              Column(
                children: [
                  for (final item in provider.adminItems) ...[
                    _SalesReportAdminTile(item: item),
                    const SizedBox(height: AppLayoutTokens.cardGap),
                  ],
                ],
              ),
            AppActionRow(
              children: [
                AppSecondaryButton(
                  onPressed: provider.canGoPrevious
                      ? provider.previousPage
                      : null,
                  icon: Icons.chevron_left_rounded,
                  label: 'Trang trước',
                ),
                AppSecondaryButton(
                  onPressed: provider.canGoNext ? provider.nextPage : null,
                  icon: Icons.chevron_right_rounded,
                  label: 'Trang sau',
                ),
              ],
            ),
            const SizedBox(height: AppLayoutTokens.formInlineGap),
          ],
        ),
      ),
    );
  }
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
    const options = {
      'ALL': 'Tất cả',
      'PURCHASED': 'Mua hàng',
      'NOT_PURCHASED': 'Chưa mua hàng',
    };
    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Loại báo cáo',
            style: AppTextStyles.labelS.copyWith(color: AppColors.neutral600),
          ),
          const SizedBox(height: 4),
          for (final entry in options.entries)
            CheckboxListTile(
              key: ValueKey('sales-report-admin-type-${entry.key}'),
              value: value == entry.key,
              onChanged: !enabled
                  ? null
                  : (checked) {
                      if (checked == true) onChanged(entry.key);
                    },
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: Text(entry.value),
            ),
        ],
      ),
    );
  }
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
