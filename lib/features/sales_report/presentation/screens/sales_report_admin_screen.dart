import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/gradient_header.dart';
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
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
                child: AppActionRow(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _reportType,
                      decoration: const InputDecoration(
                        labelText: 'Loại báo cáo',
                        prefixIcon: Icon(Icons.filter_alt_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'ALL', child: Text('Tất cả')),
                        DropdownMenuItem(
                          value: 'PURCHASED',
                          child: Text('Mua hàng'),
                        ),
                        DropdownMenuItem(
                          value: 'NOT_PURCHASED',
                          child: Text('Chưa mua hàng'),
                        ),
                      ],
                      onChanged: provider.isLoadingAdminList
                          ? null
                          : (value) {
                              if (value == null) return;
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
    final installmentLabel = item['installmentStatusLabel']?.toString() ?? '';
    final installmentFailureReason =
        item['installmentFailureReason']?.toString() ?? '';
    final installmentPartnerLabels = item['installmentPartnerLabels'] is List
        ? (item['installmentPartnerLabels'] as List)
              .map((label) => label.toString())
              .where((label) => label.trim().isNotEmpty)
              .join(', ')
        : '';
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
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
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
                    style: const TextStyle(color: AppColors.neutral600),
                  ),
                  if (submittedAt.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      submittedAt,
                      style: const TextStyle(
                        color: AppColors.neutral500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (installmentLabel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      [
                        installmentLabel,
                        if (installmentPartnerLabels.isNotEmpty)
                          installmentPartnerLabels,
                        if (installmentFailureReason.isNotEmpty)
                          installmentFailureReason,
                      ].join(' - '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.neutral600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
