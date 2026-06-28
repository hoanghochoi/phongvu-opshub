import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_feature_grid.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/sales_report.dart';
import '../providers/sales_report_provider.dart';

const _typePurchased = 'PURCHASED';
const _typeNotPurchased = 'NOT_PURCHASED';

const _consultedOptions = {
  'YES': 'Có',
  'CUSTOMER_BUSY_OR_NO_NEED':
      'Không - KH vội/không có nhu cầu/không muốn tư vấn/chỉ tham quan',
  'OUT_OF_STOCK_OR_NO_EQUIVALENT': 'Không - Hết hàng/không có SP tương đương',
  'PRODUCT_NOT_SOLD_OR_NOT_IN_STORE':
      'Không - SP KH cần không kinh doanh/không có tại CH',
  'PRICE_HIGH': 'Không - SP giá cao',
  'SALES_FORGOT': 'Không - Sales quên tư vấn',
  'OTHER': 'Không - Lý do khác',
};

const _experienceOptions = {
  'YES': 'Có',
  'CUSTOMER_BUSY_OR_NO_NEED':
      'Không - KH vội/không có nhu cầu/không muốn tư vấn/chỉ tham quan',
  'PRODUCT_NOT_SOLD_OR_NOT_IN_STORE':
      'Không - SP KH cần không kinh doanh/không có tại CH',
  'SALES_FORGOT': 'Không - Sales quên tư vấn',
  'OTHER': 'Không - Lý do khác',
};

const _zaloOptions = {
  'YES': 'Có',
  'CUSTOMER_BUSY_OR_NO_NEED':
      'Không - KH vội/không có nhu cầu/không muốn tư vấn/chỉ tham quan',
  'ALREADY_FOLLOWED_ZALO': 'Không - KH đã quét Zalo OA rồi',
  'NO_SMARTPHONE_OR_NO_ZALO':
      'Không - KH không dùng smartphone/không mang điện thoại/không dùng Zalo',
  'SALES_FORGOT': 'Không - Sales quên tư vấn',
  'OTHER': 'Không - Lý do khác',
};

const _appOptions = {
  'YES': 'Có',
  'CUSTOMER_BUSY_OR_NO_NEED':
      'Không - KH vội/không có nhu cầu/không muốn tư vấn/chỉ tham quan',
  'ALREADY_INSTALLED_APP': 'Không - KH đã tải App rồi',
  'NO_SMARTPHONE_OR_NO_APP':
      'Không - KH không dùng smartphone/không mang điện thoại/không dùng App',
  'SALES_FORGOT': 'Không - Sales quên tư vấn',
  'OTHER': 'Không - Lý do khác',
};

const _notPurchasedOptions = {
  'NOT_SOLD': 'Chưa kinh doanh',
  'SERVICE': 'Dịch vụ',
  'CUSTOMER_BROWSING': 'KH tham khảo',
  'NO_DEMO_STOCK': 'Không có hàng trải nghiệm',
  'NO_AVAILABLE_STOCK': 'Không có sẵn hàng',
  'PRICE_HESITATION': 'Phân vân giá',
  'COMPARE_COMPETITOR': 'So sánh đối thủ',
  'SPEC_NOT_COMPATIBLE': 'Thông số kỹ thuật chưa tương thích',
  'OTHER': 'Khác',
};

class SalesReportScreen extends StatefulWidget {
  const SalesReportScreen({super.key});

  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  bool _logged = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_logged) return;
    _logged = true;
    final user = context.read<AuthProvider>().user;
    unawaited(
      AppLogger.instance.info(
        'SalesReport',
        'Sales report hub opened',
        context: {
          'userId': user?.id,
          'storeId': user?.storeId,
          'hasSalesReport': user?.canUseFeature('SALES_REPORT') == true,
          'hasAdminSalesReports':
              user?.canUseFeature('ADMIN_SALES_REPORTS') == true,
        },
      ),
    );
  }

  Future<void> _openReport(String route, String reportType) async {
    final user = context.read<AuthProvider>().user;
    await AppLogger.instance.info(
      'SalesReport',
      'Sales report hub action selected',
      context: {
        'route': route,
        'reportType': reportType,
        'userId': user?.id,
        'storeId': user?.storeId,
      },
    );
    if (!mounted) return;
    context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientHeader(title: 'Báo cáo', showBack: true),
      body: AppResponsiveScrollView(
        maxWidth: AppLayoutTokens.pageMaxWidth,
        child: AppFeatureSection(
          actions: [
            AppFeatureAction(
              icon: Icons.receipt_long_outlined,
              title: 'Mua hàng',
              description: 'Báo cáo đơn đã phát sinh mua hàng.',
              color: AppColors.info,
              onTap: () =>
                  _openReport('/sales-reports/purchased', _typePurchased),
            ),
            AppFeatureAction(
              icon: Icons.person_search_outlined,
              title: 'Chưa mua hàng',
              description: 'Ghi nhận nhu cầu và lý do khách chưa mua.',
              color: AppColors.warning,
              onTap: () => _openReport(
                '/sales-reports/not-purchased',
                _typeNotPurchased,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SalesReportFormScreen extends StatefulWidget {
  final String reportType;

  const SalesReportFormScreen.purchased({super.key})
    : reportType = _typePurchased;

  const SalesReportFormScreen.notPurchased({super.key})
    : reportType = _typeNotPurchased;

  @override
  State<SalesReportFormScreen> createState() => _SalesReportFormScreenState();
}

class _SalesReportFormScreenState extends State<SalesReportFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _orderController = TextEditingController();
  final _phoneController = TextEditingController();
  final _needController = TextEditingController();
  final _consultedOtherController = TextEditingController();
  final _experiencedOtherController = TextEditingController();
  final _zaloOtherController = TextEditingController();
  final _appOtherController = TextEditingController();
  final _notPurchasedOtherController = TextEditingController();

  late String _reportType;
  String? _categoryGroupId;
  var _consultedAnswer = 'YES';
  var _experiencedAnswer = 'YES';
  var _zaloAnswer = 'YES';
  var _appDownloadAnswer = 'YES';
  String? _notPurchasedReason;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _reportType = widget.reportType == _typeNotPurchased
        ? _typeNotPurchased
        : _typePurchased;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final user = context.read<AuthProvider>().user;
    unawaited(context.read<SalesReportProvider>().initialize(user));
  }

  @override
  void dispose() {
    _orderController.dispose();
    _phoneController.dispose();
    _needController.dispose();
    _consultedOtherController.dispose();
    _experiencedOtherController.dispose();
    _zaloOtherController.dispose();
    _appOtherController.dispose();
    _notPurchasedOtherController.dispose();
    super.dispose();
  }

  bool get _isPurchased => _reportType == _typePurchased;

  Future<void> _checkOrder() async {
    final orderCode = _orderController.text.trim();
    if (orderCode.isEmpty) {
      _showSnack('Vui lòng nhập mã đơn hàng.', AppColors.warning);
      return;
    }
    final result = await context.read<SalesReportProvider>().checkOrder(
      orderCode,
    );
    if (!mounted || result == null) return;
    setState(() {
      _orderController.text = result.orderCode;
      if ((result.customerNeed ?? '').trim().isNotEmpty) {
        _needController.text = result.customerNeed!.trim();
      }
      if (result.categoryGroup != null) {
        _categoryGroupId = result.categoryGroup!.id;
      }
    });
    _showSnack('Đã kiểm tra đơn hàng.', AppColors.success);
  }

  Future<void> _submit() async {
    final provider = context.read<SalesReportProvider>();
    if (_isPurchased && provider.checkedOrder == null) {
      _showSnack(
        'Vui lòng kiểm tra đơn hàng trước khi gửi.',
        AppColors.warning,
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final input = SalesReportInput(
      reportType: _reportType,
      orderCode: _isPurchased ? _orderController.text : null,
      customerPhone: _phoneController.text,
      categoryGroupId: _categoryGroupId ?? '',
      customerNeed: _needController.text,
      consultedSolutionAnswer: _consultedAnswer,
      consultedSolutionOtherReason: _consultedOtherController.text,
      experiencedAnswer: _experiencedAnswer,
      experiencedOtherReason: _experiencedOtherController.text,
      zaloAnswer: _zaloAnswer,
      zaloOtherReason: _zaloOtherController.text,
      appDownloadAnswer: _appDownloadAnswer,
      appDownloadOtherReason: _appOtherController.text,
      notPurchasedReason: _isPurchased ? null : _notPurchasedReason,
      notPurchasedOtherReason: _notPurchasedOtherController.text,
    );
    final ok = await provider.submit(input, context.read<AuthProvider>().user);
    if (!mounted) return;
    if (ok) {
      _showSnack('Đã gửi báo cáo.', AppColors.success);
      _resetFormAfterSubmit();
    } else {
      _showSnack(
        provider.errorMessage ?? 'Chưa gửi được báo cáo.',
        AppColors.error,
      );
    }
  }

  void _resetFormAfterSubmit() {
    context.read<SalesReportProvider>().clearCheckedOrder();
    _formKey.currentState?.reset();
    setState(() {
      _orderController.clear();
      _phoneController.clear();
      _needController.clear();
      _consultedOtherController.clear();
      _experiencedOtherController.clear();
      _zaloOtherController.clear();
      _appOtherController.clear();
      _notPurchasedOtherController.clear();
      _reportType = widget.reportType == _typeNotPurchased
          ? _typeNotPurchased
          : _typePurchased;
      _categoryGroupId = null;
      _consultedAnswer = 'YES';
      _experiencedAnswer = 'YES';
      _zaloAnswer = 'YES';
      _appDownloadAnswer = 'YES';
      _notPurchasedReason = null;
    });
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SalesReportProvider>();
    final canEditReportBody = !_isPurchased || provider.checkedOrder != null;
    final title = _isPurchased ? 'Báo cáo mua hàng' : 'Báo cáo chưa mua hàng';

    return Scaffold(
      appBar: GradientHeader(title: title, showBack: true),
      body: Form(
        key: _formKey,
        child: AppResponsiveScrollView(
          maxWidth: AppLayoutTokens.formMaxWidth,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: AppFormColumn(
            spacing: AppLayoutTokens.formSectionGap,
            children: [
              if (_isPurchased) _OrderCheckCard(onCheck: _checkOrder),
              if (provider.errorMessage != null)
                AppStatusBanner(
                  icon: Icons.error_outline_rounded,
                  title: 'Chưa thực hiện được',
                  message: provider.errorMessage!,
                  tone: AppStateTone.error,
                ),
              if (_isPurchased && provider.checkedOrder != null)
                _OrderSummaryCard(check: provider.checkedOrder!),
              AbsorbPointer(
                absorbing: !canEditReportBody || provider.isSubmitting,
                child: Opacity(
                  opacity: canEditReportBody ? 1 : 0.55,
                  child: Column(
                    children: [
                      _CustomerSection(
                        phoneController: _phoneController,
                        needController: _needController,
                        categories: provider.categories,
                        categoryGroupId: _categoryGroupId,
                        loadingCategories: provider.isLoadingCategories,
                        onCategoryChanged: (value) =>
                            setState(() => _categoryGroupId = value),
                      ),
                      const SizedBox(height: AppLayoutTokens.formSectionGap),
                      _BehaviorSection(
                        consultedAnswer: _consultedAnswer,
                        experiencedAnswer: _experiencedAnswer,
                        zaloAnswer: _zaloAnswer,
                        appDownloadAnswer: _appDownloadAnswer,
                        consultedOtherController: _consultedOtherController,
                        experiencedOtherController: _experiencedOtherController,
                        zaloOtherController: _zaloOtherController,
                        appOtherController: _appOtherController,
                        onConsultedChanged: (value) =>
                            setState(() => _consultedAnswer = value),
                        onExperiencedChanged: (value) =>
                            setState(() => _experiencedAnswer = value),
                        onZaloChanged: (value) =>
                            setState(() => _zaloAnswer = value),
                        onAppChanged: (value) =>
                            setState(() => _appDownloadAnswer = value),
                      ),
                      if (!_isPurchased) ...[
                        const SizedBox(height: AppLayoutTokens.formSectionGap),
                        _NotPurchasedSection(
                          reason: _notPurchasedReason,
                          otherController: _notPurchasedOtherController,
                          onChanged: (value) =>
                              setState(() => _notPurchasedReason = value),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              AppPrimaryButton(
                onPressed:
                    provider.isSubmitting ||
                        provider.isCheckingOrder ||
                        !canEditReportBody
                    ? null
                    : _submit,
                icon: Icons.send_rounded,
                label: 'Gửi báo cáo',
                isLoading: provider.isSubmitting,
                loadingLabel: 'Đang gửi...',
              ),
              const SizedBox(height: AppLayoutTokens.formInlineGap),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderCheckCard extends StatelessWidget {
  final VoidCallback onCheck;

  const _OrderCheckCard({required this.onCheck});

  @override
  Widget build(BuildContext context) {
    final state = context
        .findAncestorStateOfType<_SalesReportFormScreenState>()!;
    final provider = context.watch<SalesReportProvider>();
    final checked = provider.checkedOrder != null;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const ValueKey('sales-report-order-code-field'),
              controller: state._orderController,
              enabled: !provider.isCheckingOrder && !checked,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Mã đơn hàng',
                prefixIcon: Icon(Icons.receipt_long_outlined),
              ),
              validator: (_) {
                if (!state._isPurchased) return null;
                if (state._orderController.text.trim().isEmpty) {
                  return 'Vui lòng nhập mã đơn hàng';
                }
                return null;
              },
            ),
            const SizedBox(height: AppLayoutTokens.formInlineGap),
            AppSecondaryButton(
              onPressed: checked || provider.isCheckingOrder ? null : onCheck,
              icon: checked
                  ? Icons.verified_outlined
                  : Icons.fact_check_outlined,
              label: checked ? 'Đã kiểm tra' : 'Kiểm tra đơn hàng',
              isLoading: provider.isCheckingOrder,
              loadingLabel: 'Đang kiểm tra...',
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderSummaryCard extends StatelessWidget {
  final SalesReportOrderCheck check;

  const _OrderSummaryCard({required this.check});

  @override
  Widget build(BuildContext context) {
    final order = check.order;
    String text(String key) => order[key]?.toString() ?? '';
    return Card(
      elevation: 0,
      color: AppColors.success.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.verified_outlined, color: AppColors.success),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Đơn hàng đã kiểm tra',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Mã đơn: ${check.orderCode}'),
            if (text('grandTotal').isNotEmpty)
              Text('Tổng tiền: ${text('grandTotal')}'),
            if (text('paymentStatus').isNotEmpty)
              Text('Thanh toán: ${text('paymentStatus')}'),
            if (text('terminalName').isNotEmpty)
              Text('Showroom ERP: ${text('terminalName')}'),
            if (check.items.isNotEmpty)
              Text('Số dòng hàng: ${check.items.length}'),
          ],
        ),
      ),
    );
  }
}

class _CustomerSection extends StatelessWidget {
  final TextEditingController phoneController;
  final TextEditingController needController;
  final List<SalesReportCategoryGroup> categories;
  final String? categoryGroupId;
  final bool loadingCategories;
  final ValueChanged<String?> onCategoryChanged;

  const _CustomerSection({
    required this.phoneController,
    required this.needController,
    required this.categories,
    required this.categoryGroupId,
    required this.loadingCategories,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
        child: Column(
          children: [
            TextFormField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              maxLength: 30,
              decoration: const InputDecoration(
                labelText: 'Số điện thoại khách hàng',
                prefixIcon: Icon(Icons.phone_outlined),
                counterText: '',
              ),
            ),
            const SizedBox(height: AppLayoutTokens.formInlineGap),
            DropdownButtonFormField<String>(
              key: ValueKey(
                'sales-report-category-${categoryGroupId ?? 'none'}-${categories.length}',
              ),
              initialValue: categories.any((item) => item.id == categoryGroupId)
                  ? categoryGroupId
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Ngành hàng',
                prefixIcon: loadingCategories
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.category_outlined),
              ),
              items: categories
                  .map(
                    (category) => DropdownMenuItem(
                      value: category.id,
                      child: Text(
                        category.catGroupNameVi,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: loadingCategories ? null : onCategoryChanged,
              validator: (value) =>
                  value == null ? 'Vui lòng chọn ngành hàng' : null,
            ),
            const SizedBox(height: AppLayoutTokens.formInlineGap),
            TextFormField(
              controller: needController,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Khách hàng tìm sản phẩm gì?',
                prefixIcon: Icon(Icons.search_outlined),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BehaviorSection extends StatelessWidget {
  final String consultedAnswer;
  final String experiencedAnswer;
  final String zaloAnswer;
  final String appDownloadAnswer;
  final TextEditingController consultedOtherController;
  final TextEditingController experiencedOtherController;
  final TextEditingController zaloOtherController;
  final TextEditingController appOtherController;
  final ValueChanged<String> onConsultedChanged;
  final ValueChanged<String> onExperiencedChanged;
  final ValueChanged<String> onZaloChanged;
  final ValueChanged<String> onAppChanged;

  const _BehaviorSection({
    required this.consultedAnswer,
    required this.experiencedAnswer,
    required this.zaloAnswer,
    required this.appDownloadAnswer,
    required this.consultedOtherController,
    required this.experiencedOtherController,
    required this.zaloOtherController,
    required this.appOtherController,
    required this.onConsultedChanged,
    required this.onExperiencedChanged,
    required this.onZaloChanged,
    required this.onAppChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
        child: Column(
          children: [
            _AnswerDropdown(
              label: 'Tư vấn 3 giải pháp',
              value: consultedAnswer,
              options: _consultedOptions,
              onChanged: onConsultedChanged,
              otherController: consultedOtherController,
              otherLabel: 'Lý do khác không tư vấn',
            ),
            const SizedBox(height: AppLayoutTokens.formInlineGap),
            _AnswerDropdown(
              label: 'KH đã được trải nghiệm',
              value: experiencedAnswer,
              options: _experienceOptions,
              onChanged: onExperiencedChanged,
              otherController: experiencedOtherController,
              otherLabel: 'Lý do khác không trải nghiệm',
            ),
            const SizedBox(height: AppLayoutTokens.formInlineGap),
            _AnswerDropdown(
              label: 'KH quét Zalo',
              value: zaloAnswer,
              options: _zaloOptions,
              onChanged: onZaloChanged,
              otherController: zaloOtherController,
              otherLabel: 'Lý do khác không quét Zalo',
            ),
            const SizedBox(height: AppLayoutTokens.formInlineGap),
            _AnswerDropdown(
              label: 'KH tải App PV',
              value: appDownloadAnswer,
              options: _appOptions,
              onChanged: onAppChanged,
              otherController: appOtherController,
              otherLabel: 'Lý do khác không tải App PV',
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerDropdown extends StatelessWidget {
  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  final TextEditingController otherController;
  final String otherLabel;

  const _AnswerDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.otherController,
    required this.otherLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('sales-report-answer-$label-$value'),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: options.entries
              .map(
                (entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
          validator: (value) =>
              value == null ? 'Vui lòng chọn thông tin' : null,
        ),
        if (value == 'OTHER') ...[
          const SizedBox(height: AppLayoutTokens.formInlineGap),
          TextFormField(
            controller: otherController,
            maxLength: 500,
            decoration: InputDecoration(labelText: otherLabel),
            validator: (text) =>
                (text ?? '').trim().isEmpty ? 'Vui lòng nhập lý do khác' : null,
          ),
        ],
      ],
    );
  }
}

class _NotPurchasedSection extends StatelessWidget {
  final String? reason;
  final TextEditingController otherController;
  final ValueChanged<String?> onChanged;

  const _NotPurchasedSection({
    required this.reason,
    required this.otherController,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey(
                'sales-report-not-purchased-reason-${reason ?? 'none'}',
              ),
              initialValue: reason,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Lý do KH không mua hàng',
                prefixIcon: Icon(Icons.help_outline_rounded),
              ),
              items: _notPurchasedOptions.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
              validator: (value) =>
                  value == null ? 'Vui lòng chọn lý do không mua' : null,
            ),
            if (reason == 'OTHER') ...[
              const SizedBox(height: AppLayoutTokens.formInlineGap),
              TextFormField(
                controller: otherController,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Lý do khác'),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Vui lòng nhập lý do khác'
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
