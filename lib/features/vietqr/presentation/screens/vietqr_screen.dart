import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../app/widgets/info_row.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/domain/entities/store_branch.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../fifo_check/presentation/widgets/barcode_scanner_screen.dart';
import '../../data/repositories/vietqr_repository.dart';
import '../../domain/entities/vietqr_transfer.dart';
import '../widgets/qr_with_logo.dart';
import '../widgets/payment_waiting_card.dart';
import '../widgets/payment_success_panel.dart';
import '../widgets/payment_confirmation_card.dart';
import '../services/vietqr_image_saver.dart';
import 'package:go_router/go_router.dart';

class VietQrScreen extends StatefulWidget {
  const VietQrScreen({super.key});

  @override
  State<VietQrScreen> createState() => _VietQrScreenState();
}

class _VietQrScreenState extends State<VietQrScreen> {
  static const _paymentPollInterval = Duration(seconds: 10);
  static const _paymentPollMaxAttempts = 36;

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _orderCodeController = TextEditingController();
  final _storeCodeController = TextEditingController();
  final _previewContentController = TextEditingController();
  final _currencyFormatter = NumberFormat.decimalPattern('vi_VN');
  final _imageSaver = VietQrImageSaver();
  late final VietQrRepository _repository;
  VietQrTransfer? _transfer;
  VietQrPaymentConfirmation? _paymentConfirmation;
  Timer? _paymentPollingTimer;
  String? _storeScopeSignature;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isCheckingPayment = false;
  int _paymentPollAttempts = 0;
  bool _hasShownPaymentReceived = false;

  @override
  void initState() {
    super.initState();
    _repository = VietQrRepository(ApiClient());
    _orderCodeController.addListener(_updatePreviewContent);
    _storeCodeController.addListener(_updatePreviewContent);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncStoreSelection(context.watch<AuthProvider>().user);
  }

  @override
  void dispose() {
    _stopPaymentPolling();
    _amountController.dispose();
    _orderCodeController.dispose();
    _storeCodeController.dispose();
    _previewContentController.dispose();
    super.dispose();
  }

  void _updatePreviewContent() {
    final nextValue = _previewContent();
    if (_previewContentController.text == nextValue) return;
    _previewContentController.value = TextEditingValue(
      text: nextValue,
      selection: TextSelection.collapsed(offset: nextValue.length),
    );
  }

  void _syncStoreSelection(User? user) {
    final stores = _assignedStoreOptions(user);
    final signature = [
      user?.id ?? '',
      user?.storeId ?? '',
      ...stores.map((store) => '${store.storeId}:${store.storeName}'),
    ].join('|');
    if (_storeScopeSignature == signature) return;
    _storeScopeSignature = signature;

    final allowedStoreIds = stores
        .map((store) => store.storeId.trim().toUpperCase())
        .where((storeId) => storeId.isNotEmpty)
        .toSet();
    final current = _storeCodeController.text.trim().toUpperCase();
    final nextStoreCode = allowedStoreIds.contains(current)
        ? current
        : (stores.isNotEmpty ? stores.first.storeId.trim().toUpperCase() : '');

    if (_storeCodeController.text.trim().toUpperCase() != nextStoreCode) {
      _storeCodeController.value = TextEditingValue(
        text: nextStoreCode,
        selection: TextSelection.collapsed(offset: nextStoreCode.length),
      );
    }

    unawaited(
      AppLogger.instance.info(
        'VietQR',
        'Store scope resolved',
        context: {
          'assignedStoreCount': stores.length,
          'selectedStoreCode': nextStoreCode,
          'selectionMode': stores.length > 1 ? 'dropdown' : 'locked',
        },
      ),
    );
  }

  List<StoreBranch> _assignedStoreOptions(User? user) {
    final storesByCode = <String, StoreBranch>{};
    void pushStore(StoreBranch store) {
      final storeCode = store.storeId.trim().toUpperCase();
      if (storeCode.isEmpty || storesByCode.containsKey(storeCode)) return;
      storesByCode[storeCode] = StoreBranch(
        id: store.id,
        storeId: storeCode,
        storeName: store.storeName.trim(),
        areaCode: store.areaCode,
        areaName: store.areaName,
        areaAbbreviation: store.areaAbbreviation,
        regionCode: store.regionCode,
        regionName: store.regionName,
        regionAbbreviation: store.regionAbbreviation,
        transferAccountNumber: store.transferAccountNumber,
        transferAccountName: store.transferAccountName,
        transferBankName: store.transferBankName,
        transferBankBin: store.transferBankBin,
        mapVietinUsername: store.mapVietinUsername,
        hasMapVietinPassword: store.hasMapVietinPassword,
        userCount: store.userCount,
      );
    }

    for (final store in user?.assignedStores ?? const <StoreBranch>[]) {
      pushStore(store);
    }
    final fallbackStoreId = user?.storeId?.trim();
    if (storesByCode.isEmpty &&
        fallbackStoreId != null &&
        fallbackStoreId.isNotEmpty) {
      pushStore(
        StoreBranch(
          id: '',
          storeId: fallbackStoreId,
          storeName: user?.storeName?.trim() ?? '',
        ),
      );
    }
    return storesByCode.values.toList(growable: false);
  }

  String _storeOptionLabel(StoreBranch store) {
    final storeId = store.storeId.trim().toUpperCase();
    final storeName = store.storeName.trim();
    if (storeName.isEmpty || storeName.toUpperCase() == storeId) {
      return storeId;
    }
    return '$storeId - $storeName';
  }

  void _selectStoreCode(String? value) {
    final storeCode = value?.trim().toUpperCase() ?? '';
    if (storeCode.isEmpty) return;
    _storeCodeController.value = TextEditingValue(
      text: storeCode,
      selection: TextSelection.collapsed(offset: storeCode.length),
    );
    unawaited(
      AppLogger.instance.info(
        'VietQR',
        'Store selection changed',
        context: {'storeCode': storeCode},
      ),
    );
  }

  Future<void> _createQr() async {
    if (!_formKey.currentState!.validate()) return;

    _stopPaymentPolling();
    setState(() {
      _isLoading = true;
      _transfer = null;
      _paymentConfirmation = null;
      _paymentPollAttempts = 0;
      _hasShownPaymentReceived = false;
    });

    try {
      await AppLogger.instance.info(
        'VietQR',
        'Create QR started',
        context: {
          'storeCode': _storeCodeController.text.trim(),
          'hasAmount': _amountValue != null,
          'hasOrderCode': _orderCodeController.text.trim().isNotEmpty,
        },
      );
      final transfer = await _repository.createTransferQr(
        amount: _amountValue,
        orderCode: _orderCodeController.text.trim(),
        storeCode: _storeCodeController.text.trim(),
      );

      if (mounted) {
        setState(() => _transfer = transfer);
        await AppLogger.instance.info(
          'VietQR',
          'Create QR succeeded',
          context: {
            'paymentId': transfer.id,
            'storeCode': _storeCodeController.text.trim(),
            'brandKey': transfer.qrBrand.key,
            'brandTitle': transfer.qrBrand.title,
            'amount': transfer.amount,
            'hasTransferContent': transfer.transferContent.trim().isNotEmpty,
          },
        );
        _startPaymentPolling(transfer);
      }
    } catch (e) {
      await AppLogger.instance.error(
        'VietQR',
        'Create QR failed',
        error: e,
        upload: true,
        context: {'storeCode': _storeCodeController.text.trim()},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chưa tạo được mã QR. Vui lòng thử lại.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  int? get _amountValue {
    final raw = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  String _amountLabel(int? amount) {
    if (amount == null) return 'Người chuyển nhập';
    return '${_currencyFormatter.format(amount)} VND';
  }

  String _contentLabel(String transferContent) {
    if (transferContent.isEmpty) return 'Người chuyển nhập';
    return transferContent;
  }

  void _formatAmount(String value) {
    final amount = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''));
    if (amount == null) {
      _amountController.clear();
      return;
    }

    final formatted = _currencyFormatter.format(amount);
    _amountController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _previewContent() {
    final storeCode = _storeCodeController.text.trim();
    final orderCode = _orderCodeController.text.trim();
    if (orderCode.isEmpty) return '';
    if (storeCode.isEmpty) return orderCode.toUpperCase();
    return '$orderCode $storeCode BOT'.toUpperCase();
  }

  void _createNewQr() {
    _stopPaymentPolling();
    setState(() {
      _transfer = null;
      _paymentConfirmation = null;
      _amountController.clear();
      _orderCodeController.clear();
      _paymentPollAttempts = 0;
      _hasShownPaymentReceived = false;
    });
  }

  Future<void> _confirmPayment() async {
    await _checkPayment(showFeedback: true);
  }

  void _startPaymentPolling(VietQrTransfer transfer) {
    _stopPaymentPolling();
    if (!_canAutoConfirm(transfer)) return;
    unawaited(
      AppLogger.instance.info(
        'VietQR',
        'Payment polling started',
        context: {
          'paymentId': transfer.id,
          'storeCode': _storeCodeController.text.trim(),
        },
      ),
    );
    _paymentPollAttempts = 0;
    _hasShownPaymentReceived = false;
    _checkPayment();
    _paymentPollingTimer = Timer.periodic(
      _paymentPollInterval,
      (_) => _checkPayment(),
    );
  }

  void _stopPaymentPolling() {
    if (_paymentPollingTimer != null) {
      unawaited(
        AppLogger.instance.info(
          'VietQR',
          'Payment polling stopped',
          context: {'attempts': _paymentPollAttempts},
        ),
      );
    }
    _paymentPollingTimer?.cancel();
    _paymentPollingTimer = null;
  }

  bool _canAutoConfirm(VietQrTransfer transfer) {
    return transfer.id.isNotEmpty &&
        transfer.amount != null &&
        transfer.transferContent.trim().isNotEmpty;
  }

  bool get _hasConfirmedPayment => _paymentConfirmation?.confirmed == true;

  bool _shouldStopAutoCheck(VietQrPaymentConfirmation confirmation) {
    return confirmation.confirmed ||
        confirmation.reason == 'MISSING_MATCH_FIELDS' ||
        confirmation.reason == 'MULTIPLE_MATCHES' ||
        confirmation.reason == 'EXPIRED_VIETNAM_DAY';
  }

  Future<void> _checkPayment({bool showFeedback = false}) async {
    final transfer = _transfer;
    if (transfer == null ||
        transfer.id.isEmpty ||
        _isCheckingPayment ||
        _hasConfirmedPayment) {
      return;
    }
    if (!showFeedback && _paymentPollAttempts >= _paymentPollMaxAttempts) {
      _stopPaymentPolling();
      return;
    }

    setState(() {
      _isCheckingPayment = true;
      _paymentPollAttempts += 1;
    });
    try {
      final confirmation = await _repository.confirmPayment(transfer.id);
      if (!mounted) return;
      setState(() => _paymentConfirmation = confirmation);
      await AppLogger.instance.info(
        'VietQR',
        'Payment confirmation checked',
        context: {
          'paymentId': transfer.id,
          'attempt': _paymentPollAttempts,
          'confirmed': confirmation.confirmed,
          'reason': confirmation.reason,
          'matchedAmount': confirmation.matchedAmount,
        },
      );
      if (_shouldStopAutoCheck(confirmation)) {
        _stopPaymentPolling();
      }
      if (confirmation.confirmed && !_hasShownPaymentReceived) {
        _hasShownPaymentReceived = true;
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã nhận thanh toán'),
            backgroundColor: AppColors.success,
          ),
        );
      } else if (showFeedback) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_confirmationMessage(confirmation))),
        );
      }
    } catch (e) {
      await AppLogger.instance.error(
        'VietQR',
        'Payment confirmation check failed',
        error: e,
        upload: showFeedback,
        context: {'paymentId': transfer.id, 'attempt': _paymentPollAttempts},
      );
      if (mounted) {
        if (showFeedback) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Chưa kiểm tra được thanh toán. Vui lòng thử lại.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isCheckingPayment = false);
    }
  }

  Future<void> _scanOrderCode() async {
    FocusScope.of(context).unfocus();
    try {
      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => const BarcodeScannerScreen(
            title: 'Quét mã đơn',
            instruction: 'Đưa barcode mã đơn vào khung hình để quét',
            helperText: 'Kết quả quét sẽ điền vào ô mã đơn',
            parsePhongVuSku: false,
          ),
        ),
      );
      if (result == null || !mounted) return;

      final scannedCode = result.trim().toUpperCase();
      _orderCodeController.value = TextEditingValue(
        text: scannedCode,
        selection: TextSelection.collapsed(offset: scannedCode.length),
      );
      await AppLogger.instance.info(
        'VietQR',
        'Order code scanned',
        context: {'codeLength': scannedCode.length},
      );
    } catch (e) {
      await AppLogger.instance.error(
        'VietQR',
        'Order code scan failed',
        error: e,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chưa quét được mã đơn. Vui lòng thử lại.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _saveQrImage() async {
    final transfer = _transfer;
    if (transfer == null || _isSaving) return;

    setState(() => _isSaving = true);
    final startedAt = DateTime.now();
    try {
      final fileName = buildVietQrImageFileName(
        transfer.transferContent,
        DateTime.now(),
      );
      await AppLogger.instance.info(
        'VietQR',
        'QR image save started',
        context: {
          'paymentId': transfer.id,
          'brandKey': transfer.qrBrand.key,
          'brandTitle': transfer.qrBrand.title,
          'fileName': fileName,
        },
      );

      final bytes = await _buildExportPng(transfer);
      final result = await _imageSaver.savePng(
        bytes: bytes,
        fileName: fileName,
      );
      if (result.usedFallback) {
        await AppLogger.instance.warn(
          'VietQR',
          'QR image save used fallback',
          context: {
            'paymentId': transfer.id,
            'method': result.method,
            'destination': result.destination,
            'fallbackReason': result.fallbackReason,
          },
        );
      }
      await AppLogger.instance.info(
        'VietQR',
        'QR image saved',
        context: {
          'paymentId': transfer.id,
          'brandKey': transfer.qrBrand.key,
          'brandTitle': transfer.qrBrand.title,
          'fileName': result.fileName,
          'method': result.method,
          'destination': result.destination,
          'byteCount': bytes.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.userMessage)));
      }
    } catch (e) {
      await AppLogger.instance.error(
        'VietQR',
        'QR image save failed',
        error: e,
        context: {
          'paymentId': transfer.id,
          'brandKey': transfer.qrBrand.key,
          'brandTitle': transfer.qrBrand.title,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chưa lưu được ảnh QR. Vui lòng thử lại.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildStoreField(List<StoreBranch> storeOptions) {
    String? selectedStoreCode = _storeCodeController.text.trim().toUpperCase();
    final allowedStoreIds = storeOptions
        .map((store) => store.storeId.trim().toUpperCase())
        .where((storeId) => storeId.isNotEmpty)
        .toSet();
    if (!allowedStoreIds.contains(selectedStoreCode)) {
      selectedStoreCode = null;
    }

    if (storeOptions.length > 1) {
      return AppSelectField<String>(
        key: ValueKey(
          'vietqr-store-${allowedStoreIds.join(',')}-$selectedStoreCode',
        ),
        label: 'Mã SR',
        value: selectedStoreCode,
        hintText: 'Chọn SR tạo QR',
        icon: Icons.store_outlined,
        items: storeOptions
            .map(
              (store) => DropdownMenuItem<String>(
                value: store.storeId.trim().toUpperCase(),
                child: Text(
                  _storeOptionLabel(store),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(growable: false),
        onChanged: _isLoading ? null : _selectStoreCode,
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Vui lòng chọn SR để tạo QR';
          }
          return null;
        },
      );
    }

    return AppFormTextInput(
      controller: _storeCodeController,
      label: 'Mã SR',
      icon: Icons.store_outlined,
      readOnly: true,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Tài khoản chưa có SR để tạo QR';
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final transfer = _transfer;
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      appBar: const GradientHeader(title: 'Tạo VietQR', showBack: true),
      body: SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: AppResponsiveScrollView(
            maxWidth: AppLayoutTokens.formMaxWidth,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: transfer == null
                ? Form(key: _formKey, child: _buildInputCard(user))
                : _buildResultView(transfer),
          ),
        ),
      ),
    );
  }

  Widget _buildInputCard(User? user) {
    final storeOptions = _assignedStoreOptions(user);
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Thông tin chuyển khoản', style: AppTextStyles.headingS),
          const SizedBox(height: AppLayoutTokens.formFieldGap),
          AppFormTextInput(
            controller: _amountController,
            label: 'Số tiền',
            hintText: 'Để trống nếu người chuyển tự nhập',
            icon: Icons.payments_outlined,
            suffixText: 'VND',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: _formatAmount,
            validator: (_) {
              final amount = _amountValue;
              if (_amountController.text.trim().isEmpty) {
                return null;
              }
              if (amount == null || amount <= 0) {
                return 'Số tiền phải lớn hơn 0 hoặc để trống';
              }
              return null;
            },
          ),
          const SizedBox(height: AppLayoutTokens.formFieldGap),
          AppFormTextInput(
            controller: _orderCodeController,
            label: 'Mã đơn / nội dung',
            hintText: 'Có thể để trống để người chuyển tự nhập',
            icon: Icons.receipt_long_outlined,
            suffixIcon: AppIconAction(
              tooltip: 'Quét mã đơn',
              onPressed: _isLoading ? null : _scanOrderCode,
              icon: Icons.qr_code_scanner_rounded,
            ),
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: AppLayoutTokens.formFieldGap),
          _buildStoreField(storeOptions),
          const SizedBox(height: AppLayoutTokens.formFieldGap),
          AppFormTextInput(
            controller: _previewContentController,
            label: 'Nội dung chuyển khoản',
            hintText: 'Người chuyển tự nhập nếu ô này trống',
            icon: Icons.lock_outline,
            readOnly: true,
          ),
          const SizedBox(height: AppLayoutTokens.formSectionGap),
          AppPrimaryButton(
            onPressed: _createQr,
            icon: Icons.qr_code_2_rounded,
            label: 'Tạo mã QR',
            isLoading: _isLoading,
            loadingLabel: 'Đang tạo...',
          ),
        ],
      ),
    );
  }

  Widget _buildResultView(VietQrTransfer transfer) {
    final confirmed = _hasConfirmedPayment;
    final canAutoConfirm = _canAutoConfirm(transfer);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (confirmed && _paymentConfirmation != null)
          PaymentSuccessPanel(
            confirmation: _paymentConfirmation!,
            amountFormatter: _currencyFormatter,
          )
        else
          AppSurfaceCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                QrWithLogo(size: 280, transfer: transfer),
                const SizedBox(height: 20),
                AppInfoRow(
                  label: 'Ngân hàng',
                  value: transfer.bankName,
                  labelWidth: 118,
                ),
                AppInfoRow(
                  label: 'Số tài khoản',
                  value: transfer.accountNumber,
                  labelWidth: 118,
                ),
                AppInfoRow(
                  label: 'Chủ tài khoản',
                  value: transfer.accountName,
                  labelWidth: 118,
                ),
                AppInfoRow(
                  label: 'Số tiền',
                  value: _amountLabel(transfer.amount),
                  labelWidth: 118,
                ),
                AppInfoRow(
                  label: 'Nội dung',
                  value: _contentLabel(transfer.transferContent),
                  labelWidth: 118,
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        if (_paymentConfirmation != null && !confirmed) ...[
          PaymentConfirmationCard(
            confirmation: _paymentConfirmation!,
            amountFormatter: _currencyFormatter,
          ),
          const SizedBox(height: 16),
        ] else if (!confirmed && canAutoConfirm) ...[
          PaymentWaitingCard(isChecking: _isCheckingPayment),
          const SizedBox(height: 16),
        ],
        if (!confirmed) ...[
          AppPrimaryButton(
            onPressed: _confirmPayment,
            icon: Icons.sync_rounded,
            label: 'Kiểm tra ngay',
            isLoading: _isCheckingPayment,
            loadingLabel: 'Đang kiểm tra...',
          ),
          const SizedBox(height: 10),
          AppPrimaryButton(
            onPressed: _saveQrImage,
            icon: Icons.download_rounded,
            label: 'Tải ảnh QR',
            isLoading: _isSaving,
            loadingLabel: 'Đang lưu...',
          ),
          const SizedBox(height: 10),
        ],
        AppSecondaryButton(
          onPressed: _createNewQr,
          icon: Icons.add_rounded,
          label: 'Tạo mã mới',
        ),
        const SizedBox(height: 10),
        AppSecondaryButton(
          onPressed: () => context.pop(),
          icon: Icons.arrow_back_rounded,
          label: 'Quay lại',
        ),
      ],
    );
  }

  String _confirmationMessage(VietQrPaymentConfirmation confirmation) {
    switch (confirmation.reason) {
      case 'NO_MATCH':
        return 'Chưa thấy giao dịch khớp';
      case 'MULTIPLE_MATCHES':
        return 'Có nhiều giao dịch khớp, cần kiểm tra thủ công';
      case 'MISSING_MATCH_FIELDS':
        return 'QR thiếu số tiền hoặc nội dung, cần kiểm tra thủ công';
      case 'EXPIRED_VIETNAM_DAY':
        return 'QR đã qua ngày. Vui lòng tạo mã mới.';
      default:
        return 'Chưa xác nhận được thanh toán';
    }
  }

  Future<Uint8List> _buildExportPng(VietQrTransfer transfer) async {
    const width = 1080.0;
    const height = 1560.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = AppColors.surface;
    canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), paint);

    final titleStyle = AppTextStyles.headingXL.copyWith(
      color: AppColors.primary500,
      fontSize: 58,
      fontWeight: FontWeight.w700,
    );
    final labelStyle = AppTextStyles.headingS.copyWith(
      color: AppColors.neutral700,
      fontSize: 32,
    );
    final valueStyle = AppTextStyles.headingXL.copyWith(
      color: AppColors.neutral800,
      fontSize: 38,
      fontWeight: FontWeight.w700,
    );

    _drawText(canvas, transfer.qrBrand.title, 72, 64, titleStyle);
    _drawText(canvas, 'Mã chuyển khoản VietQR', 72, 136, labelStyle);

    const qrSize = 690.0;
    const qrLeft = (width - qrSize) / 2;
    const qrTop = 230.0;
    final qrPainter = QrPainter(
      data: transfer.qrPayload,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.H,
      gapless: true,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: AppColors.neutral900,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: AppColors.neutral900,
      ),
    );
    canvas.translate(qrLeft, qrTop);
    qrPainter.paint(canvas, const Size(qrSize, qrSize));
    canvas.translate(-qrLeft, -qrTop);

    final logo = await _loadUiImage(transfer.qrBrand.logoAsset);
    const logoSize = 150.0;
    final logoRect = Rect.fromCenter(
      center: const Offset(width / 2, qrTop + qrSize / 2),
      width: logoSize,
      height: logoSize,
    );
    final logoBg = RRect.fromRectAndRadius(
      logoRect.inflate(18),
      const Radius.circular(AppRadius.xxl),
    );
    canvas.drawRRect(logoBg, Paint()..color = AppColors.surface);
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(logoRect, const Radius.circular(AppRadius.xl)),
    );
    canvas.drawImageRect(
      logo,
      Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
      logoRect,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();

    var y = 990.0;
    y = _drawInfo(
      canvas,
      'Ngân hàng',
      transfer.bankName,
      y,
      labelStyle,
      valueStyle,
    );
    y = _drawInfo(
      canvas,
      'Số tài khoản',
      transfer.accountNumber,
      y,
      labelStyle,
      valueStyle,
    );
    y = _drawInfo(
      canvas,
      'Chủ tài khoản',
      transfer.accountName,
      y,
      labelStyle,
      valueStyle,
    );
    y = _drawInfo(
      canvas,
      'Số tiền',
      _amountLabel(transfer.amount),
      y,
      labelStyle,
      valueStyle,
    );
    _drawInfo(
      canvas,
      'Nội dung',
      _contentLabel(transfer.transferContent),
      y,
      labelStyle,
      valueStyle,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  Future<ui.Image> _loadUiImage(String asset) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  double _drawInfo(
    Canvas canvas,
    String label,
    String value,
    double y,
    TextStyle labelStyle,
    TextStyle valueStyle,
  ) {
    _drawText(canvas, label, 72, y, labelStyle);
    _drawText(canvas, value, 360, y - 4, valueStyle, maxWidth: 640);
    return y + 96;
  }

  void _drawText(
    Canvas canvas,
    String text,
    double x,
    double y,
    TextStyle style, {
    double maxWidth = 940,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
      maxLines: 2,
      ellipsis: '...',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, Offset(x, y));
  }
}
