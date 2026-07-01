import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/formatting/money_formatters.dart';
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

const _customerTypeOptions = {
  'BUSINESS': 'Doanh nghiệp',
  'PERSONAL': 'Cá nhân',
};

const _promotionOptions = {
  'EXAM_SCORE_EXCHANGE': 'Đổi điểm thi',
  'STUDENT': 'Học sinh - Sinh viên',
  'OTHER': 'CTKM khác',
};

const _installmentPartnerOptions = {
  'VNPAY_POS': 'VNPAY - POS',
  'PAYOO_POS': 'PAYOO - POS',
  'HOMECREDIT_CTTC': 'HomeCredit - CTTC',
  'SHINHAN_CTTC': 'Shinhan - CTTC',
  'HDSAISON_CTTC': 'HDSaison - CTTC',
  'AEON_FINANCE_CTTC': 'AEON Finance - CTTC',
  'MIRAE_ASSET': 'Mirae Asset',
  'MPOS': 'MPOS',
};

const _installmentNoInstallmentReasonOptions = {
  'NORMAL_INSTALLMENT': 'Khách chốt trả góp bình thường (Không có lý do)',
  'BAD_CREDIT_HISTORY': 'Rớt hồ sơ: Tín dụng xấu (Nợ cũ, CIC...)',
  'APPRAISAL_OR_INFO_ERROR': 'Rớt hồ sơ: Lỗi thẩm định/Thông tin',
  'HIGH_INTEREST_OR_FEE': 'Khách từ chối: Lãi suất/Phí trả góp cao',
  'MISSING_DOCUMENT_OR_CARD': 'Khách từ chối: Không đủ điều kiện giấy tờ/thẻ',
  'PRICE_COMPETITOR_COMPARISON':
      'Khách từ chối: Giá cao/So sánh đối thủ (TGDĐ, FPT, CPS...)',
  'BROWSING_OR_COME_BACK_LATER': 'Khách từ chối: Chỉ tham khảo/Hẹn quay lại',
};

class SalesReportScreen extends StatefulWidget {
  const SalesReportScreen({super.key});

  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  bool _logged = false;
  bool _initialized = false;
  Timer? _refreshTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.read<AuthProvider>().user;
    if (!_logged) {
      _logged = true;
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
    if (_initialized) return;
    _initialized = true;
    unawaited(
      context.read<SalesReportProvider>().initialize(
        user,
        orders: true,
        categories: false,
      ),
    );
    _refreshTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      if (!mounted) return;
      unawaited(context.read<SalesReportProvider>().loadOrderCockpit());
    });
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

  Future<void> _openPurchasedDialog(SalesReportOrderCockpitItem order) async {
    final user = context.read<AuthProvider>().user;
    final provider = context.read<SalesReportProvider>();
    await AppLogger.instance.info(
      'SalesReport',
      'Sales report order selected from cockpit',
      context: {
        'orderLength': order.orderCode.length,
        'userId': user?.id,
        'storeId': user?.storeId,
      },
    );
    if (!mounted) return;
    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final size = MediaQuery.sizeOf(context);
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: size.width >= 960 ? 900 : size.width * 0.94,
            height: size.height * 0.90,
            child: ChangeNotifierProvider<SalesReportProvider>.value(
              value: provider,
              child: SalesReportFormScreen.purchased(
                initialOrderCode: order.orderCode,
                closeOnSuccess: true,
              ),
            ),
          ),
        );
      },
    );
    if (submitted == true && mounted) {
      unawaited(context.read<SalesReportProvider>().loadOrderCockpit());
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmitReports = context.select<AuthProvider, bool>(
      (auth) => auth.user?.canUseFeature('SALES_REPORT') == true,
    );
    final canViewAdminReports = context.select<AuthProvider, bool>(
      (auth) => auth.user?.canUseFeature('ADMIN_SALES_REPORTS') == true,
    );
    final provider = context.watch<SalesReportProvider>();
    return Scaffold(
      appBar: const GradientHeader(title: 'Báo cáo', showBack: true),
      body: AppResponsiveScrollView(
        maxWidth: AppLayoutTokens.pageMaxWidth,
        child: _SalesReportCockpit(
          provider: provider,
          canSubmitReports: canSubmitReports,
          canViewAdminReports: canViewAdminReports,
          onNotPurchased: canSubmitReports
              ? () => _openReport(
                  '/sales-reports/not-purchased',
                  _typeNotPurchased,
                )
              : null,
          onOpenAdmin: canViewAdminReports ? _openAdminReports : null,
          onReload: () => provider.loadOrderCockpit(),
          onExportHvtc: canViewAdminReports
              ? () => provider.exportCsv(
                  query: const SalesReportQuery(exportType: 'HVTC'),
                )
              : null,
          onExportRevenue: canViewAdminReports
              ? () => provider.exportCsv(
                  query: const SalesReportQuery(exportType: 'REVENUE'),
                )
              : null,
          onExportInstallment: canViewAdminReports
              ? () => provider.exportCsv(
                  query: const SalesReportQuery(exportType: 'INSTALLMENT'),
                )
              : null,
          onOrderTap: canSubmitReports ? _openPurchasedDialog : null,
        ),
      ),
    );
  }
}

class _SalesReportCockpit extends StatelessWidget {
  final SalesReportProvider provider;
  final bool canSubmitReports;
  final bool canViewAdminReports;
  final VoidCallback? onNotPurchased;
  final VoidCallback? onOpenAdmin;
  final VoidCallback onReload;
  final VoidCallback? onExportHvtc;
  final VoidCallback? onExportRevenue;
  final VoidCallback? onExportInstallment;
  final ValueChanged<SalesReportOrderCockpitItem>? onOrderTap;

  const _SalesReportCockpit({
    required this.provider,
    required this.canSubmitReports,
    required this.canViewAdminReports,
    required this.onNotPurchased,
    required this.onOpenAdmin,
    required this.onReload,
    required this.onExportHvtc,
    required this.onExportRevenue,
    required this.onExportInstallment,
    required this.onOrderTap,
  });

  @override
  Widget build(BuildContext context) {
    final cockpit = provider.orderCockpit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSurfaceCard(
          child: Wrap(
            spacing: AppLayoutTokens.formInlineGap,
            runSpacing: AppLayoutTokens.formInlineGap,
            alignment: WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (canSubmitReports)
                SizedBox(
                  width: 220,
                  child: AppPrimaryButton(
                    onPressed: onNotPurchased,
                    icon: Icons.person_search_outlined,
                    label: 'Báo cáo chưa mua',
                  ),
                ),
              SizedBox(
                width: 160,
                child: AppSecondaryButton(
                  onPressed: provider.isLoadingOrders ? null : onReload,
                  icon: Icons.refresh_rounded,
                  label: 'Tải lại',
                  isLoading: provider.isLoadingOrders,
                ),
              ),
              if (canViewAdminReports)
                SizedBox(
                  width: 180,
                  child: AppSecondaryButton(
                    onPressed: provider.isExporting ? null : onExportHvtc,
                    icon: Icons.download_rounded,
                    label: 'Xuất HVTC',
                    isLoading: provider.isExporting,
                  ),
                ),
              if (canViewAdminReports)
                SizedBox(
                  width: 190,
                  child: AppSecondaryButton(
                    onPressed: provider.isExporting ? null : onExportRevenue,
                    icon: Icons.download_rounded,
                    label: 'Xuất Doanh số',
                    isLoading: provider.isExporting,
                  ),
                ),
              if (canViewAdminReports)
                SizedBox(
                  width: 190,
                  child: AppSecondaryButton(
                    onPressed: provider.isExporting
                        ? null
                        : onExportInstallment,
                    icon: Icons.download_rounded,
                    label: 'Xuất Trả góp',
                    isLoading: provider.isExporting,
                  ),
                ),
              if (canViewAdminReports)
                SizedBox(
                  width: 170,
                  child: AppSecondaryButton(
                    onPressed: onOpenAdmin,
                    icon: Icons.assignment_outlined,
                    label: 'Danh sách',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppLayoutTokens.cardGap),
        if (provider.errorMessage != null)
          AppStatusBanner(
            icon: Icons.error_outline_rounded,
            title: 'Chưa tải đủ dữ liệu',
            message: provider.errorMessage!,
            tone: AppStateTone.error,
          ),
        if (provider.isLoadingOrders && cockpit == null)
          const AppListSkeleton(itemCount: 6)
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 760;
              final reported = _OrdersColumn(
                title: 'Đã báo cáo',
                count: provider.reportedOrders.length,
                emptyMessage: 'Chưa có đơn đã báo cáo.',
                orders: provider.reportedOrders,
                onTap: null,
              );
              final unreported = _OrdersColumn(
                title: 'Chưa báo cáo',
                count: provider.unreportedOrders.length,
                emptyMessage: 'Chưa có đơn chờ báo cáo.',
                orders: provider.unreportedOrders,
                onTap: onOrderTap,
              );
              if (!twoColumns) {
                return Column(
                  children: [
                    unreported,
                    const SizedBox(height: AppLayoutTokens.cardGap),
                    reported,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: unreported),
                  const SizedBox(width: AppLayoutTokens.cardGap),
                  Expanded(child: reported),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _OrdersColumn extends StatelessWidget {
  final String title;
  final int count;
  final String emptyMessage;
  final List<SalesReportOrderCockpitItem> orders;
  final ValueChanged<SalesReportOrderCockpitItem>? onTap;

  const _OrdersColumn({
    required this.title,
    required this.count,
    required this.emptyMessage,
    required this.orders,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: AppTextStyles.headingS)),
            Text(
              '$count',
              style: AppTextStyles.labelM.copyWith(color: AppColors.neutral600),
            ),
          ],
        ),
        const SizedBox(height: AppLayoutTokens.formInlineGap),
        if (orders.isEmpty)
          AppStatePanel.empty(title: title, message: emptyMessage)
        else
          for (final order in orders) ...[
            _OrderCockpitTile(order: order, onTap: onTap),
            const SizedBox(height: AppLayoutTokens.cardGap),
          ],
      ],
    );
  }
}

class _OrderCockpitTile extends StatelessWidget {
  final SalesReportOrderCockpitItem order;
  final ValueChanged<SalesReportOrderCockpitItem>? onTap;

  const _OrderCockpitTile({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final money = formatVndAmount(order.grandTotal);
    final reporter =
        order.consultantName ?? order.sellerName ?? order.consultantCustomId;
    final subtitle = [
      if ((order.storeCode ?? '').trim().isNotEmpty) order.storeCode,
      if ((order.terminalName ?? '').trim().isNotEmpty) order.terminalName,
      if ((reporter ?? '').trim().isNotEmpty) reporter,
    ].whereType<String>().join(' • ');
    final meta = [
      if (money.isNotEmpty) money,
      if ((order.paymentStatus ?? '').trim().isNotEmpty) order.paymentStatus,
      if (order.reportedAt != null)
        'Đã báo cáo ${_shortDate(order.reportedAt)}',
    ].whereType<String>().join(' • ');
    return AppSurfaceCard(
      onTap: onTap == null ? null : () => onTap!(order),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            order.isReported
                ? Icons.verified_outlined
                : Icons.receipt_long_outlined,
            color: order.isReported ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.orderCode,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelM,
                ),
                if ((order.customerName ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    order.customerName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyM,
                  ),
                ],
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyM.copyWith(
                      color: AppColors.neutral600,
                    ),
                  ),
                ],
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    meta,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelS.copyWith(
                      color: AppColors.neutral500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onTap != null)
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.neutral500,
            ),
        ],
      ),
    );
  }

  static String _shortDate(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class SalesReportFormScreen extends StatefulWidget {
  final String reportType;
  final String? initialOrderCode;
  final bool closeOnSuccess;

  const SalesReportFormScreen.purchased({
    super.key,
    this.initialOrderCode,
    this.closeOnSuccess = false,
  }) : reportType = _typePurchased;

  const SalesReportFormScreen.notPurchased({
    super.key,
    this.closeOnSuccess = false,
  }) : reportType = _typeNotPurchased,
       initialOrderCode = null;

  @override
  State<SalesReportFormScreen> createState() => _SalesReportFormScreenState();
}

class _SalesReportFormScreenState extends State<SalesReportFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _orderController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _needController = TextEditingController();
  final _consultedOtherController = TextEditingController();
  final _experiencedOtherController = TextEditingController();
  final _zaloOtherController = TextEditingController();
  final _appOtherController = TextEditingController();
  final _notPurchasedOtherController = TextEditingController();
  final _installmentLoanController = TextEditingController();

  late String _reportType;
  final List<String> _categoryGroupIds = [];
  String? _customerType;
  bool _customerIsStudent = false;
  final List<String> _promotionCodes = [];
  String? _consultedAnswer;
  String? _experiencedAnswer;
  String? _zaloAnswer;
  String? _appDownloadAnswer;
  String? _notPurchasedReason;
  bool _installmentSelected = false;
  bool? _installmentApproved;
  String? _installmentNoInstallmentReason;
  final List<String> _installmentPartnerCodes = [];
  bool _initialized = false;
  bool _autoCheckedInitialOrder = false;

  @override
  void initState() {
    super.initState();
    _reportType = widget.reportType == _typeNotPurchased
        ? _typeNotPurchased
        : _typePurchased;
    final initialOrderCode = _normalizeOrderCode(widget.initialOrderCode ?? '');
    if (_reportType == _typePurchased && initialOrderCode.isNotEmpty) {
      _orderController.text = initialOrderCode;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _autoCheckedInitialOrder) return;
        _autoCheckedInitialOrder = true;
        unawaited(_checkOrder());
      });
    }
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
    _scrollController.dispose();
    _orderController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _needController.dispose();
    _consultedOtherController.dispose();
    _experiencedOtherController.dispose();
    _zaloOtherController.dispose();
    _appOtherController.dispose();
    _notPurchasedOtherController.dispose();
    _installmentLoanController.dispose();
    super.dispose();
  }

  bool get _isPurchased => _reportType == _typePurchased;

  String get _primaryCategoryGroupId =>
      _categoryGroupIds.isEmpty ? '' : _categoryGroupIds.first;

  String _normalizeOrderCode(String value) {
    return value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }

  void _setCustomerType(String? value) {
    setState(() {
      _customerType = value;
      if (value != 'PERSONAL') {
        _customerIsStudent = false;
      }
    });
  }

  void _setCustomerIsStudent(bool value) {
    setState(() {
      _customerIsStudent = value;
      if (value) {
        _customerType = 'PERSONAL';
      }
    });
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
      if ((result.customerName ?? '').trim().isNotEmpty) {
        _nameController.text = result.customerName!.trim();
      }
      if ((result.customerNeed ?? '').trim().isNotEmpty) {
        _needController.text = result.customerNeed!.trim();
      }
      final nextCustomerType = result.customerType == 'BUSINESS'
          ? 'BUSINESS'
          : 'PERSONAL';
      _customerType = nextCustomerType;
      if (nextCustomerType != 'PERSONAL') {
        _customerIsStudent = false;
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
      _nameController.clear();
      _phoneController.clear();
      _needController.clear();
      _consultedOtherController.clear();
      _experiencedOtherController.clear();
      _zaloOtherController.clear();
      _appOtherController.clear();
      _notPurchasedOtherController.clear();
      _installmentLoanController.clear();
      _categoryGroupIds.clear();
      _customerType = null;
      _customerIsStudent = false;
      _promotionCodes.clear();
      _consultedAnswer = null;
      _experiencedAnswer = null;
      _zaloAnswer = null;
      _appDownloadAnswer = null;
      _notPurchasedReason = null;
      _installmentSelected = false;
      _installmentApproved = null;
      _installmentNoInstallmentReason = null;
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
            'hasCustomerName': _nameController.text.trim().isNotEmpty,
            'hasCustomerNeed': _needController.text.trim().isNotEmpty,
            'hasConsultedAnswer': _consultedAnswer != null,
            'hasExperiencedAnswer': _experiencedAnswer != null,
            'hasZaloAnswer': _zaloAnswer != null,
            'hasAppDownloadAnswer': _appDownloadAnswer != null,
            'hasNotPurchasedReason': _notPurchasedReason != null,
            'customerType': _customerType,
            'customerIsStudent': _customerIsStudent,
            'promotionCount': _promotionCodes.length,
            'installmentSelected': _installmentSelected,
            'installmentApproved': _installmentApproved,
            'installmentPartnerCount': _installmentPartnerCodes.length,
            'hasInstallmentNoReason': _installmentNoInstallmentReason != null,
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
      customerName: _nameController.text,
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
      customerType: _customerType,
      customerIsStudent: _customerIsStudent,
      promotionCodes: List.unmodifiable(_promotionCodes),
      installmentNeed: _installmentSelected,
      installmentApproved: _installmentSelected ? _installmentApproved : null,
      installmentLoanAmount: _installmentSelected
          ? parseMoneyAmount(_installmentLoanController.text)
          : null,
      installmentNoInstallmentReason: _installmentSelected
          ? _installmentNoInstallmentReason
          : null,
      installmentStatus: _installmentSelected
          ? (_installmentNoInstallmentReason == 'NORMAL_INSTALLMENT'
                ? 'SUCCESS'
                : 'FAILED')
          : null,
      installmentFailureReason: null,
      installmentPartnerCodes: _installmentSelected
          ? List.unmodifiable(_installmentPartnerCodes)
          : const [],
    );
    final ok = await provider.submit(input, context.read<AuthProvider>().user);
    if (!mounted) return;
    if (ok) {
      _showSnack('Đã gửi báo cáo.', AppColors.success);
      _resetFormAfterSubmit();
      await _scrollToTopAfterSubmit();
      if (widget.closeOnSuccess && mounted) {
        Navigator.of(context).pop(true);
      }
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
      _nameController.clear();
      _phoneController.clear();
      _needController.clear();
      _consultedOtherController.clear();
      _experiencedOtherController.clear();
      _zaloOtherController.clear();
      _appOtherController.clear();
      _notPurchasedOtherController.clear();
      _installmentLoanController.clear();
      _reportType = widget.reportType == _typeNotPurchased
          ? _typeNotPurchased
          : _typePurchased;
      _categoryGroupIds.clear();
      _customerType = null;
      _customerIsStudent = false;
      _promotionCodes.clear();
      _consultedAnswer = null;
      _experiencedAnswer = null;
      _zaloAnswer = null;
      _appDownloadAnswer = null;
      _notPurchasedReason = null;
      _installmentSelected = false;
      _installmentApproved = null;
      _installmentNoInstallmentReason = null;
      _installmentPartnerCodes.clear();
    });
  }

  Future<void> _scrollToTopAfterSubmit() async {
    final user = context.read<AuthProvider>().user;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final scrolledToTop = _scrollController.hasClients;
    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        _scrollController.position.minScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
    unawaited(
      AppLogger.instance.info(
        'SalesReport',
        'Sales report form reset after submit',
        context: {
          'reportType': _reportType,
          'userId': user?.id,
          'storeId': user?.storeId,
          'scrolledToTop': scrolledToTop,
        },
      ),
    );
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
          controller: _scrollController,
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
                        nameController: _nameController,
                        phoneController: _phoneController,
                        needController: _needController,
                        customerType: _customerType,
                        customerIsStudent: _customerIsStudent,
                        promotionCodes: _promotionCodes,
                        categories: provider.categories,
                        categoryGroupIds: _categoryGroupIds,
                        loadingCategories: provider.isLoadingCategories,
                        onCustomerTypeChanged: _setCustomerType,
                        onStudentChanged: _setCustomerIsStudent,
                        onPromotionsChanged: (value) {
                          setState(() {
                            _promotionCodes
                              ..clear()
                              ..addAll(value);
                          });
                        },
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
                        approved: _installmentApproved,
                        noInstallmentReason: _installmentNoInstallmentReason,
                        selectedPartnerCodes: _installmentPartnerCodes,
                        loanController: _installmentLoanController,
                        onChanged: (value) {
                          setState(() {
                            _installmentSelected = value ?? false;
                            if (!_installmentSelected) {
                              _installmentLoanController.clear();
                              _installmentApproved = null;
                              _installmentNoInstallmentReason = null;
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
                        onApprovedChanged: (value) =>
                            setState(() => _installmentApproved = value),
                        onNoInstallmentReasonChanged: (value) => setState(
                          () => _installmentNoInstallmentReason = value,
                        ),
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
    final grandTotal = formatVndAmount(order['grandTotal']);
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
          if (grandTotal.isNotEmpty) Text('Tổng tiền: $grandTotal'),
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
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController needController;
  final String? customerType;
  final bool customerIsStudent;
  final List<String> promotionCodes;
  final List<SalesReportCategoryGroup> categories;
  final List<String> categoryGroupIds;
  final bool loadingCategories;
  final ValueChanged<String?> onCustomerTypeChanged;
  final ValueChanged<bool> onStudentChanged;
  final ValueChanged<List<String>> onPromotionsChanged;
  final ValueChanged<List<String>> onCategoryChanged;

  const _CustomerSection({
    required this.nameController,
    required this.phoneController,
    required this.needController,
    required this.customerType,
    required this.customerIsStudent,
    required this.promotionCodes,
    required this.categories,
    required this.categoryGroupIds,
    required this.loadingCategories,
    required this.onCustomerTypeChanged,
    required this.onStudentChanged,
    required this.onPromotionsChanged,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        children: [
          AppFormTextInput(
            key: const ValueKey('sales-report-customer-name-field'),
            controller: nameController,
            label: 'Tên khách hàng',
            icon: Icons.person_outline_rounded,
            textCapitalization: TextCapitalization.words,
            maxLength: 120,
            counterText: '',
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'Vui lòng nhập tên khách hàng'
                : null,
          ),
          const SizedBox(height: AppLayoutTokens.formInlineGap),
          AppFormTextInput(
            controller: phoneController,
            label: 'Số điện thoại khách hàng',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            maxLength: 30,
            counterText: '',
          ),
          const SizedBox(height: AppLayoutTokens.formInlineGap),
          _CustomerTypePicker(
            value: customerType,
            isStudent: customerIsStudent,
            onChanged: onCustomerTypeChanged,
            onStudentChanged: onStudentChanged,
          ),
          const SizedBox(height: AppLayoutTokens.formInlineGap),
          _PromotionPicker(
            selectedCodes: promotionCodes,
            onChanged: onPromotionsChanged,
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
            key: const ValueKey('sales-report-customer-need-field'),
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

class _CustomerTypePicker extends StatelessWidget {
  final String? value;
  final bool isStudent;
  final ValueChanged<String?> onChanged;
  final ValueChanged<bool> onStudentChanged;

  const _CustomerTypePicker({
    required this.value,
    required this.isStudent,
    required this.onChanged,
    required this.onStudentChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      key: ValueKey('sales-report-customer-type-${value ?? 'none'}'),
      initialValue: value,
      validator: (_) {
        if (value == null) return 'Vui lòng chọn loại khách hàng';
        if (value == 'BUSINESS' && isStudent) {
          return 'Doanh nghiệp không thể đồng thời là Học sinh - Sinh viên';
        }
        return null;
      },
      builder: (field) {
        final businessSelected = value == 'BUSINESS';
        final personalSelected = value == 'PERSONAL';
        void changeType(String? next) {
          field.didChange(next);
          onChanged(next);
        }

        return InputDecorator(
          decoration: appInputDecoration(
            label: 'Loại khách hàng',
            icon: Icons.badge_outlined,
            errorText: field.errorText,
          ).copyWith(alignLabelWithHint: true),
          child: Column(
            children: [
              CheckboxListTile(
                key: const ValueKey('sales-report-customer-type-BUSINESS'),
                value: businessSelected,
                onChanged: (checked) =>
                    changeType(checked == true ? 'BUSINESS' : null),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(_customerTypeOptions['BUSINESS']!),
              ),
              CheckboxListTile(
                key: const ValueKey('sales-report-customer-type-PERSONAL'),
                value: personalSelected,
                onChanged: businessSelected
                    ? null
                    : (checked) =>
                          changeType(checked == true ? 'PERSONAL' : null),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(_customerTypeOptions['PERSONAL']!),
              ),
              CheckboxListTile(
                key: const ValueKey('sales-report-customer-student'),
                value: isStudent,
                onChanged: businessSelected
                    ? null
                    : (checked) {
                        if (checked == true && !personalSelected) {
                          changeType('PERSONAL');
                        }
                        onStudentChanged(checked ?? false);
                      },
                contentPadding: const EdgeInsets.only(left: 32),
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Học sinh - Sinh viên'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PromotionPicker extends StatelessWidget {
  final List<String> selectedCodes;
  final ValueChanged<List<String>> onChanged;

  const _PromotionPicker({
    required this.selectedCodes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: appInputDecoration(
        label: 'CTKM áp dụng',
        icon: Icons.local_offer_outlined,
      ).copyWith(alignLabelWithHint: true),
      child: Column(
        children: [
          for (final entry in _promotionOptions.entries)
            CheckboxListTile(
              key: ValueKey('sales-report-promotion-${entry.key}'),
              value: selectedCodes.contains(entry.key),
              onChanged: (checked) {
                final next = [...selectedCodes];
                if (checked == true) {
                  if (!next.contains(entry.key)) next.add(entry.key);
                } else {
                  next.remove(entry.key);
                }
                onChanged(next);
              },
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(entry.value),
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
  final bool? approved;
  final String? noInstallmentReason;
  final List<String> selectedPartnerCodes;
  final TextEditingController loanController;
  final ValueChanged<bool?> onChanged;
  final ValueChanged<List<String>> onPartnersChanged;
  final ValueChanged<bool?> onApprovedChanged;
  final ValueChanged<String?> onNoInstallmentReasonChanged;

  const _InstallmentSection({
    required this.isPurchased,
    required this.selected,
    required this.approved,
    required this.noInstallmentReason,
    required this.selectedPartnerCodes,
    required this.loanController,
    required this.onChanged,
    required this.onPartnersChanged,
    required this.onApprovedChanged,
    required this.onNoInstallmentReasonChanged,
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
            title: const Text('Có nhu cầu trả góp'),
            subtitle: Text(
              isPurchased
                  ? 'Ghi nhận nhu cầu và kết quả hồ sơ trả góp của đơn mua.'
                  : 'Ghi nhận nhu cầu và lý do khách chưa chốt trả góp.',
            ),
          ),
          if (selected) ...[
            const SizedBox(height: AppLayoutTokens.formInlineGap),
            _InstallmentPartnerPicker(
              selectedCodes: selectedPartnerCodes,
              onChanged: onPartnersChanged,
            ),
            const SizedBox(height: AppLayoutTokens.formInlineGap),
            _InstallmentApprovalPicker(
              value: approved,
              onChanged: onApprovedChanged,
            ),
            const SizedBox(height: AppLayoutTokens.formInlineGap),
            AppFormTextInput(
              key: const ValueKey('sales-report-installment-loan-amount'),
              controller: loanController,
              label: 'Số tiền vay',
              icon: Icons.payments_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: [VietnameseThousandsSeparatorInputFormatter()],
              suffixText: 'VND',
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return null;
                final number = parseMoneyAmount(text);
                return number == null ? 'Số tiền vay không hợp lệ' : null;
              },
            ),
            const SizedBox(height: AppLayoutTokens.formInlineGap),
            _InstallmentNoReasonPicker(
              value: noInstallmentReason,
              onChanged: onNoInstallmentReasonChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class _InstallmentApprovalPicker extends StatelessWidget {
  final bool? value;
  final ValueChanged<bool?> onChanged;

  const _InstallmentApprovalPicker({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FormField<bool>(
      key: ValueKey('sales-report-installment-approved-${value ?? 'none'}'),
      initialValue: value,
      validator: (_) =>
          value == null ? 'Vui lòng chọn hồ sơ được duyệt hay chưa' : null,
      builder: (field) {
        return InputDecorator(
          decoration: appInputDecoration(
            label: 'Hồ sơ được duyệt không',
            icon: Icons.fact_check_outlined,
            errorText: field.errorText,
          ).copyWith(alignLabelWithHint: true),
          child: Column(
            children: [
              for (final option in const [
                (value: true, label: 'Có'),
                (value: false, label: 'Không'),
              ])
                CheckboxListTile(
                  key: ValueKey(
                    'sales-report-installment-approved-${option.value}',
                  ),
                  value: value == option.value,
                  onChanged: (checked) {
                    final next = checked == true ? option.value : null;
                    field.didChange(next);
                    onChanged(next);
                  },
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(option.label),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _InstallmentNoReasonPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const _InstallmentNoReasonPicker({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      key: ValueKey('sales-report-installment-no-reason-${value ?? 'none'}'),
      initialValue: value,
      validator: (_) =>
          value == null ? 'Vui lòng chọn lý do không trả góp' : null,
      builder: (field) {
        return InputDecorator(
          decoration: appInputDecoration(
            label: 'Lý do không trả góp',
            icon: Icons.report_problem_outlined,
            errorText: field.errorText,
          ).copyWith(alignLabelWithHint: true),
          child: Column(
            children: [
              for (final entry
                  in _installmentNoInstallmentReasonOptions.entries)
                CheckboxListTile(
                  key: ValueKey(
                    'sales-report-installment-no-reason-${entry.key}',
                  ),
                  value: value == entry.key,
                  onChanged: (checked) {
                    final next = checked == true ? entry.key : null;
                    field.didChange(next);
                    onChanged(next);
                  },
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    entry.value,
                    maxLines: 3,
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
        FormField<String>(
          key: ValueKey('sales-report-answer-$label-$value'),
          initialValue: value,
          validator: (_) => value == null ? 'Vui lòng chọn $label' : null,
          builder: (field) {
            return InputDecorator(
              decoration: appInputDecoration(
                label: label,
                icon: Icons.checklist_outlined,
                errorText: field.errorText,
              ).copyWith(alignLabelWithHint: true),
              child: Column(
                children: [
                  for (final entry in options.entries)
                    CheckboxListTile(
                      key: ValueKey('sales-report-answer-$label-${entry.key}'),
                      value: value == entry.key,
                      onChanged: (checked) {
                        final next = checked == true ? entry.key : null;
                        if (next != 'OTHER') otherController.clear();
                        field.didChange(next);
                        onChanged(next);
                      },
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        entry.value,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            );
          },
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
          FormField<String>(
            key: ValueKey(
              'sales-report-not-purchased-reason-${reason ?? 'none'}',
            ),
            initialValue: reason,
            validator: (_) =>
                reason == null ? 'Vui lòng chọn lý do không mua' : null,
            builder: (field) {
              return InputDecorator(
                decoration: appInputDecoration(
                  label: 'Lý do KH không mua hàng',
                  icon: Icons.help_outline_rounded,
                  errorText: field.errorText,
                ).copyWith(alignLabelWithHint: true),
                child: Column(
                  children: [
                    for (final entry in _notPurchasedOptions.entries)
                      CheckboxListTile(
                        key: ValueKey(
                          'sales-report-not-purchased-reason-${entry.key}',
                        ),
                        value: reason == entry.key,
                        onChanged: (checked) {
                          final next = checked == true ? entry.key : null;
                          if (next != 'OTHER') otherController.clear();
                          field.didChange(next);
                          onChanged(next);
                        },
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          entry.value,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              );
            },
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
