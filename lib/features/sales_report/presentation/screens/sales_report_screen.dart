import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_feature_grid.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../fifo_check/presentation/widgets/barcode_scanner_screen.dart';
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

const _installmentPartnerOptions = {
  'VNPAY_POS': 'VNPAY - POS',
  'PAYOO_POS': 'PAYOO - POS',
  'HOMECREDIT_CTTC': 'HomeCredit - CTTC',
  'SHINHAN_CTTC': 'Shinhan - CTTC',
  'HDSAISON_CTTC': 'HDSaison - CTTC',
  'AEON_FINANCE_CTTC': 'AEON Finance - CTTC',
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

  Future<void> _openAdminReports() async {
    final user = context.read<AuthProvider>().user;
    await AppLogger.instance.info(
      'SalesReport',
      'Sales report admin list action selected',
      context: {
        'route': '/admin/sales-reports',
        'userId': user?.id,
        'storeId': user?.storeId,
        'hasAdminSalesReports':
            user?.canUseFeature('ADMIN_SALES_REPORTS') == true,
      },
    );
    if (!mounted) return;
    context.push('/admin/sales-reports');
  }

  @override
  Widget build(BuildContext context) {
    final canSubmitReports = context.select<AuthProvider, bool>(
      (auth) => auth.user?.canUseFeature('SALES_REPORT') == true,
    );
    final canViewAdminReports = context.select<AuthProvider, bool>(
      (auth) => auth.user?.canUseFeature('ADMIN_SALES_REPORTS') == true,
    );
    return Scaffold(
      appBar: const GradientHeader(title: 'Báo cáo', showBack: true),
      body: AppResponsiveScrollView(
        maxWidth: AppLayoutTokens.pageMaxWidth,
        child: AppFeatureSection(
          actions: [
            if (canSubmitReports)
              AppFeatureAction(
                icon: Icons.receipt_long_outlined,
                title: 'Mua hàng',
                description: 'Báo cáo đơn đã phát sinh mua hàng.',
                color: AppColors.info,
                onTap: () =>
                    _openReport('/sales-reports/purchased', _typePurchased),
              ),
            if (canSubmitReports)
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
            if (canViewAdminReports)
              AppFeatureAction(
                icon: Icons.assignment_outlined,
                title: 'Báo cáo sale',
                description: 'Danh sách & xuất file',
                color: AppColors.info,
                onTap: _openAdminReports,
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
  final _installmentFailureController = TextEditingController();

  late String _reportType;
  final List<String> _categoryGroupIds = [];
  String? _consultedAnswer;
  String? _experiencedAnswer;
  String? _zaloAnswer;
  String? _appDownloadAnswer;
  String? _notPurchasedReason;
  bool _installmentSelected = false;
  final List<String> _installmentPartnerCodes = [];
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
    _installmentFailureController.dispose();
    super.dispose();
  }

  bool get _isPurchased => _reportType == _typePurchased;

  String get _primaryCategoryGroupId =>
      _categoryGroupIds.isEmpty ? '' : _categoryGroupIds.first;

  String _normalizeOrderCode(String value) {
    return value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }

  Future<void> _scanOrderCode() async {
    final user = context.read<AuthProvider>().user;
    try {
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report order scanner opened',
        context: {'userId': user?.id, 'storeId': user?.storeId},
      );
      if (!mounted) return;
      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => const BarcodeScannerScreen(
            title: 'Quét mã đơn hàng',
            instruction: 'Hướng camera vào QR hoặc barcode mã đơn hàng',
            helperText: 'Có thể nhập tay nếu camera chưa sẵn sàng',
            parsePhongVuSku: false,
          ),
        ),
      );
      if (!mounted) return;
      final orderCode = _normalizeOrderCode(result ?? '');
      if (orderCode.isEmpty) {
        await AppLogger.instance.info(
          'SalesReport',
          'Sales report order scanner cancelled',
          context: {'userId': user?.id, 'storeId': user?.storeId},
        );
        return;
      }
      setState(() => _orderController.text = orderCode);
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report order scanner succeeded',
        context: {
          'userId': user?.id,
          'storeId': user?.storeId,
          'orderLength': orderCode.length,
        },
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'SalesReport',
        'Sales report order scanner failed',
        error: error,
        stackTrace: stackTrace,
        context: {'userId': user?.id, 'storeId': user?.storeId},
      );
      if (mounted) {
        _showSnack('Chưa quét được mã. Vui lòng thử lại.', AppColors.error);
      }
    }
  }

  Future<void> _checkOrder() async {
    final orderCode = _normalizeOrderCode(_orderController.text);
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
      _categoryGroupIds
        ..clear()
        ..addAll(result.categoryGroups.map((category) => category.id));
    });
    _showSnack('Đã kiểm tra đơn hàng.', AppColors.success);
  }

  void _checkAnotherOrder() {
    final user = context.read<AuthProvider>().user;
    context.read<SalesReportProvider>().clearCheckedOrder();
    setState(() {
      _orderController.clear();
      _phoneController.clear();
      _needController.clear();
      _consultedOtherController.clear();
      _experiencedOtherController.clear();
      _zaloOtherController.clear();
      _appOtherController.clear();
      _notPurchasedOtherController.clear();
      _installmentFailureController.clear();
      _categoryGroupIds.clear();
      _consultedAnswer = null;
      _experiencedAnswer = null;
      _zaloAnswer = null;
      _appDownloadAnswer = null;
      _notPurchasedReason = null;
      _installmentSelected = false;
      _installmentPartnerCodes.clear();
    });
    unawaited(
      AppLogger.instance.info(
        'SalesReport',
        'Sales report check another order selected',
        context: {'userId': user?.id, 'storeId': user?.storeId},
      ),
    );
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
    if (!_formKey.currentState!.validate()) {
      unawaited(
        AppLogger.instance.warn(
          'SalesReport',
          'Sales report form validation blocked',
          context: {
            'reportType': _reportType,
            'categoryGroupCount': _categoryGroupIds.length,
            'hasCustomerNeed': _needController.text.trim().isNotEmpty,
            'hasConsultedAnswer': _consultedAnswer != null,
            'hasExperiencedAnswer': _experiencedAnswer != null,
            'hasZaloAnswer': _zaloAnswer != null,
            'hasAppDownloadAnswer': _appDownloadAnswer != null,
            'hasNotPurchasedReason': _notPurchasedReason != null,
            'installmentSelected': _installmentSelected,
            'installmentPartnerCount': _installmentPartnerCodes.length,
            'hasInstallmentFailureReason': _installmentFailureController.text
                .trim()
                .isNotEmpty,
          },
        ),
      );
      return;
    }
    final consultedAnswer = _consultedAnswer!;
    final experiencedAnswer = _experiencedAnswer!;
    final zaloAnswer = _zaloAnswer!;
    final appDownloadAnswer = _appDownloadAnswer!;
    final input = SalesReportInput(
      reportType: _reportType,
      orderCode: _isPurchased ? _orderController.text : null,
      customerPhone: _phoneController.text,
      categoryGroupId: _primaryCategoryGroupId,
      categoryGroupIds: List.unmodifiable(_categoryGroupIds),
      customerNeed: _needController.text,
      consultedSolutionAnswer: consultedAnswer,
      consultedSolutionOtherReason: _consultedOtherController.text,
      experiencedAnswer: experiencedAnswer,
      experiencedOtherReason: _experiencedOtherController.text,
      zaloAnswer: zaloAnswer,
      zaloOtherReason: _zaloOtherController.text,
      appDownloadAnswer: appDownloadAnswer,
      appDownloadOtherReason: _appOtherController.text,
      notPurchasedReason: _isPurchased ? null : _notPurchasedReason,
      notPurchasedOtherReason: _notPurchasedOtherController.text,
      installmentStatus: _installmentSelected
          ? (_isPurchased ? 'SUCCESS' : 'FAILED')
          : null,
      installmentFailureReason: !_isPurchased && _installmentSelected
          ? _installmentFailureController.text
          : null,
      installmentPartnerCodes: _installmentSelected
          ? List.unmodifiable(_installmentPartnerCodes)
          : const [],
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
      _installmentFailureController.clear();
      _reportType = widget.reportType == _typeNotPurchased
          ? _typeNotPurchased
          : _typePurchased;
      _categoryGroupIds.clear();
      _consultedAnswer = null;
      _experiencedAnswer = null;
      _zaloAnswer = null;
      _appDownloadAnswer = null;
      _notPurchasedReason = null;
      _installmentSelected = false;
      _installmentPartnerCodes.clear();
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
              if (_isPurchased)
                _OrderCheckCard(
                  onCheck: _checkOrder,
                  onScan: _scanOrderCode,
                  onCheckAnother: _checkAnotherOrder,
                ),
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
                        categoryGroupIds: _categoryGroupIds,
                        loadingCategories: provider.isLoadingCategories,
                        onCategoryChanged: (value) {
                          setState(() {
                            _categoryGroupIds
                              ..clear()
                              ..addAll(value);
                          });
                        },
                      ),
                      const SizedBox(height: AppLayoutTokens.formSectionGap),
                      _InstallmentSection(
                        isPurchased: _isPurchased,
                        selected: _installmentSelected,
                        selectedPartnerCodes: _installmentPartnerCodes,
                        failureController: _installmentFailureController,
                        onChanged: (value) {
                          setState(() {
                            _installmentSelected = value ?? false;
                            if (!_installmentSelected) {
                              _installmentFailureController.clear();
                              _installmentPartnerCodes.clear();
                            }
                          });
                        },
                        onPartnersChanged: (value) {
                          setState(() {
                            _installmentPartnerCodes
                              ..clear()
                              ..addAll(value);
                          });
                        },
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
  final VoidCallback onScan;
  final VoidCallback onCheckAnother;

  const _OrderCheckCard({
    required this.onCheck,
    required this.onScan,
    required this.onCheckAnother,
  });

  @override
  Widget build(BuildContext context) {
    final state = context
        .findAncestorStateOfType<_SalesReportFormScreenState>()!;
    final provider = context.watch<SalesReportProvider>();
    final checked = provider.checkedOrder != null;
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppFormTextInput(
            key: const ValueKey('sales-report-order-code-field'),
            controller: state._orderController,
            enabled: !provider.isCheckingOrder && !checked,
            label: 'Mã đơn hàng',
            icon: Icons.receipt_long_outlined,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.characters,
            onFieldSubmitted: (_) {
              if (!checked && !provider.isCheckingOrder) onCheck();
            },
            suffixIcon: AppIconAction(
              icon: Icons.qr_code_scanner_rounded,
              onPressed: checked || provider.isCheckingOrder ? null : onScan,
              tooltip: 'Quét mã đơn hàng',
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
          AppActionRow(
            desktopAlignment: MainAxisAlignment.start,
            children: [
              AppSecondaryButton(
                onPressed: checked || provider.isCheckingOrder ? null : onCheck,
                icon: checked
                    ? Icons.verified_outlined
                    : Icons.fact_check_outlined,
                label: checked ? 'Đã kiểm tra' : 'Kiểm tra đơn hàng',
                isLoading: provider.isCheckingOrder,
                loadingLabel: 'Đang kiểm tra...',
              ),
              if (checked)
                AppSecondaryButton(
                  onPressed: provider.isCheckingOrder ? null : onCheckAnother,
                  icon: Icons.restart_alt_rounded,
                  label: 'Kiểm tra đơn khác',
                ),
            ],
          ),
        ],
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
    return AppSurfaceCard(
      backgroundColor: AppColors.success.withValues(alpha: 0.08),
      borderColor: AppColors.success.withValues(alpha: 0.20),
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
                  style: AppTextStyles.labelM,
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
    );
  }
}

class _CustomerSection extends StatelessWidget {
  final TextEditingController phoneController;
  final TextEditingController needController;
  final List<SalesReportCategoryGroup> categories;
  final List<String> categoryGroupIds;
  final bool loadingCategories;
  final ValueChanged<List<String>> onCategoryChanged;

  const _CustomerSection({
    required this.phoneController,
    required this.needController,
    required this.categories,
    required this.categoryGroupIds,
    required this.loadingCategories,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        children: [
          AppFormTextInput(
            controller: phoneController,
            label: 'Số điện thoại khách hàng',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            maxLength: 30,
            counterText: '',
          ),
          const SizedBox(height: AppLayoutTokens.formInlineGap),
          _CategoryMultiPicker(
            categories: categories,
            selectedIds: categoryGroupIds,
            isLoading: loadingCategories,
            onChanged: onCategoryChanged,
          ),
          const SizedBox(height: AppLayoutTokens.formInlineGap),
          AppFormTextInput(
            controller: needController,
            label: 'Khách hàng tìm sản phẩm gì?',
            icon: Icons.search_outlined,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            alignLabelWithHint: true,
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'Vui lòng nhập nhu cầu khách hàng'
                : null,
          ),
        ],
      ),
    );
  }
}

class _CategoryMultiPicker extends StatelessWidget {
  final List<SalesReportCategoryGroup> categories;
  final List<String> selectedIds;
  final bool isLoading;
  final ValueChanged<List<String>> onChanged;

  const _CategoryMultiPicker({
    required this.categories,
    required this.selectedIds,
    required this.isLoading,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FormField<List<String>>(
      key: ValueKey(
        'sales-report-categories-${selectedIds.join(',')}-${categories.length}',
      ),
      initialValue: selectedIds,
      validator: (_) =>
          selectedIds.isEmpty ? 'Vui lòng chọn ít nhất một ngành hàng' : null,
      builder: (field) {
        final errorText = field.errorText;
        return InputDecorator(
          decoration:
              appInputDecoration(
                label: 'Ngành hàng',
                icon: isLoading ? null : Icons.category_outlined,
                errorText: errorText,
              ).copyWith(
                alignLabelWithHint: true,
                prefixIcon: isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.category_outlined),
              ),
          child: categories.isEmpty
              ? Text(
                  isLoading
                      ? 'Đang tải danh sách ngành hàng...'
                      : 'Chưa có danh sách ngành hàng.',
                  style: AppTextStyles.bodyM.copyWith(
                    color: AppColors.neutral600,
                  ),
                )
              : Column(
                  children: [
                    for (final category in categories)
                      CheckboxListTile(
                        key: ValueKey('sales-report-category-${category.id}'),
                        value: selectedIds.contains(category.id),
                        onChanged: isLoading
                            ? null
                            : (checked) {
                                final next = [...selectedIds];
                                if (checked == true) {
                                  if (!next.contains(category.id)) {
                                    next.add(category.id);
                                  }
                                } else {
                                  next.remove(category.id);
                                }
                                field.didChange(next);
                                onChanged(next);
                              },
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          category.catGroupNameVi,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _InstallmentSection extends StatelessWidget {
  final bool isPurchased;
  final bool selected;
  final List<String> selectedPartnerCodes;
  final TextEditingController failureController;
  final ValueChanged<bool?> onChanged;
  final ValueChanged<List<String>> onPartnersChanged;

  const _InstallmentSection({
    required this.isPurchased,
    required this.selected,
    required this.selectedPartnerCodes,
    required this.failureController,
    required this.onChanged,
    required this.onPartnersChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            key: const ValueKey('sales-report-installment-checkbox'),
            value: selected,
            onChanged: onChanged,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Trả góp'),
            subtitle: Text(
              isPurchased
                  ? 'Đơn này trả góp thành công.'
                  : 'Khách có nhu cầu trả góp nhưng chưa hoàn tất.',
            ),
          ),
          if (selected) ...[
            const SizedBox(height: AppLayoutTokens.formInlineGap),
            _InstallmentPartnerPicker(
              selectedCodes: selectedPartnerCodes,
              onChanged: onPartnersChanged,
            ),
          ],
          if (!isPurchased && selected) ...[
            const SizedBox(height: AppLayoutTokens.formInlineGap),
            AppFormTextInput(
              key: const ValueKey('sales-report-installment-failure-reason'),
              controller: failureController,
              label: 'Lý do trả góp thất bại',
              icon: Icons.report_problem_outlined,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              alignLabelWithHint: true,
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Vui lòng nhập lý do trả góp thất bại'
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _InstallmentPartnerPicker extends StatelessWidget {
  final List<String> selectedCodes;
  final ValueChanged<List<String>> onChanged;

  const _InstallmentPartnerPicker({
    required this.selectedCodes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FormField<List<String>>(
      key: ValueKey(
        'sales-report-installment-partners-${selectedCodes.join(',')}',
      ),
      initialValue: selectedCodes,
      validator: (_) =>
          selectedCodes.isEmpty ? 'Vui lòng chọn đối tác trả góp' : null,
      builder: (field) {
        return InputDecorator(
          decoration: appInputDecoration(
            label: 'Đối tác trả góp',
            icon: Icons.account_balance_outlined,
            errorText: field.errorText,
          ).copyWith(alignLabelWithHint: true),
          child: Column(
            children: [
              for (final entry in _installmentPartnerOptions.entries)
                CheckboxListTile(
                  key: ValueKey('sales-report-installment-${entry.key}'),
                  value: selectedCodes.contains(entry.key),
                  onChanged: (checked) {
                    final next = [...selectedCodes];
                    if (checked == true) {
                      if (!next.contains(entry.key)) next.add(entry.key);
                    } else {
                      next.remove(entry.key);
                    }
                    field.didChange(next);
                    onChanged(next);
                  },
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    entry.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BehaviorSection extends StatelessWidget {
  final String? consultedAnswer;
  final String? experiencedAnswer;
  final String? zaloAnswer;
  final String? appDownloadAnswer;
  final TextEditingController consultedOtherController;
  final TextEditingController experiencedOtherController;
  final TextEditingController zaloOtherController;
  final TextEditingController appOtherController;
  final ValueChanged<String?> onConsultedChanged;
  final ValueChanged<String?> onExperiencedChanged;
  final ValueChanged<String?> onZaloChanged;
  final ValueChanged<String?> onAppChanged;

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
    return AppSurfaceCard(
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
    );
  }
}

class _AnswerDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final Map<String, String> options;
  final ValueChanged<String?> onChanged;
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
        AppSelectField<String>(
          key: ValueKey('sales-report-answer-$label-$value'),
          value: value,
          label: label,
          hintText: 'Chọn',
          items: options.entries
              .map(
                (entry) => DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(entry.value, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != 'OTHER') otherController.clear();
            onChanged(value);
          },
          validator: (value) => value == null ? 'Vui lòng chọn $label' : null,
        ),
        if (value == 'OTHER') ...[
          const SizedBox(height: AppLayoutTokens.formInlineGap),
          AppFormTextInput(
            controller: otherController,
            label: otherLabel,
            maxLength: 500,
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
    return AppSurfaceCard(
      child: Column(
        children: [
          AppSelectField<String>(
            key: ValueKey(
              'sales-report-not-purchased-reason-${reason ?? 'none'}',
            ),
            value: reason,
            label: 'Lý do KH không mua hàng',
            icon: Icons.help_outline_rounded,
            items: _notPurchasedOptions.entries
                .map(
                  (entry) => DropdownMenuItem<String>(
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
            AppFormTextInput(
              controller: otherController,
              label: 'Lý do khác',
              maxLength: 500,
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Vui lòng nhập lý do khác'
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}
