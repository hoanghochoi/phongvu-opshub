import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../app/widgets/gradient_header.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../chat/presentation/widgets/barcode_scanner_screen.dart';
import '../../data/repositories/vietqr_repository.dart';
import '../../domain/entities/vietqr_transfer.dart';

class VietQrScreen extends StatefulWidget {
  const VietQrScreen({super.key});

  @override
  State<VietQrScreen> createState() => _VietQrScreenState();
}

class _VietQrScreenState extends State<VietQrScreen> {
  static const _mediaChannel = MethodChannel('phongvu_opshub/media');
  static const _logoAsset = 'assets/images/vietqr_logo.jpg';

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _orderCodeController = TextEditingController();
  final _storeCodeController = TextEditingController();
  final _previewContentController = TextEditingController();
  final _currencyFormatter = NumberFormat.decimalPattern('vi_VN');
  late final VietQrRepository _repository;
  VietQrTransfer? _transfer;
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _repository = VietQrRepository(ApiClient());
    _orderCodeController.addListener(_updatePreviewContent);
    _storeCodeController.addListener(_updatePreviewContent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final storeId = context.read<AuthProvider>().user?.storeId ?? '';
      _storeCodeController.text = storeId;
    });
  }

  @override
  void dispose() {
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

  Future<void> _createQr() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _transfer = null;
    });

    try {
      final transfer = await _repository.createTransferQr(
        amount: _amountValue,
        orderCode: _orderCodeController.text.trim(),
        storeCode: _storeCodeController.text.trim(),
      );

      if (mounted) {
        setState(() => _transfer = transfer);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không tạo được VietQR: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  int get _amountValue {
    final raw = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(raw) ?? 0;
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
    if (storeCode.isEmpty || orderCode.isEmpty) return '';
    return '$orderCode $storeCode BOT'.toUpperCase();
  }

  void _createNewQr() {
    setState(() {
      _transfer = null;
      _amountController.clear();
      _orderCodeController.clear();
    });
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không quét được mã đơn: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveQrImage() async {
    final transfer = _transfer;
    if (transfer == null || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      final bytes = await _buildExportPng(transfer);
      final fileName =
          'vietqr_${transfer.transferContent.replaceAll(RegExp(r'[^A-Z0-9_-]'), '_')}.png';
      await _mediaChannel.invokeMethod<String>('savePngToGallery', {
        'fileName': fileName,
        'bytes': bytes,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu ảnh QR vào thư viện ảnh')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không lưu được ảnh QR: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final transfer = _transfer;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: const GradientHeader(title: 'Tạo VietQR', showBack: true),
      body: SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
            child: transfer == null
                ? Form(key: _formKey, child: _buildInputCard())
                : _buildResultView(transfer),
          ),
        ),
      ),
    );
  }

  Widget _buildInputCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Thông tin chuyển khoản',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Số tiền',
                prefixIcon: Icon(Icons.payments_outlined),
                suffixText: 'VND',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: _formatAmount,
              validator: (_) {
                if (_amountValue <= 0) {
                  return 'Vui lòng nhập số tiền';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _orderCodeController,
              decoration: InputDecoration(
                labelText: 'Mã đơn',
                prefixIcon: const Icon(Icons.receipt_long_outlined),
                suffixIcon: AppIconAction(
                  tooltip: 'Quét mã đơn',
                  onPressed: _isLoading ? null : _scanOrderCode,
                  icon: Icons.qr_code_scanner_rounded,
                ),
                border: const OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Vui lòng nhập mã đơn';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _storeCodeController,
              decoration: const InputDecoration(
                labelText: 'Mã cửa hàng',
                prefixIcon: Icon(Icons.store_outlined),
                border: OutlineInputBorder(),
              ),
              readOnly: true,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Tài khoản chưa có mã cửa hàng';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _previewContentController,
              decoration: const InputDecoration(
                labelText: 'Nội dung chuyển khoản',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
              readOnly: true,
            ),
            const SizedBox(height: 18),
            AppPrimaryButton(
              onPressed: _createQr,
              icon: Icons.qr_code_2_rounded,
              label: 'Tạo mã QR',
              isLoading: _isLoading,
              loadingLabel: 'Đang tạo...',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultView(VietQrTransfer transfer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _QrWithLogo(size: 280, transfer: transfer),
                const SizedBox(height: 20),
                _InfoRow(label: 'Ngân hàng', value: transfer.bankName),
                _InfoRow(label: 'Số tài khoản', value: transfer.accountNumber),
                _InfoRow(label: 'Chủ tài khoản', value: transfer.accountName),
                _InfoRow(
                  label: 'Số tiền',
                  value: '${_currencyFormatter.format(transfer.amount)} VND',
                ),
                _InfoRow(label: 'Nội dung', value: transfer.transferContent),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        AppPrimaryButton(
          onPressed: _saveQrImage,
          icon: Icons.download_rounded,
          label: 'Tải ảnh QR',
          isLoading: _isSaving,
          loadingLabel: 'Đang lưu...',
        ),
        const SizedBox(height: 10),
        AppSecondaryButton(
          onPressed: _createNewQr,
          icon: Icons.add_rounded,
          label: 'Tạo mã mới',
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Quay lại'),
        ),
      ],
    );
  }

  Future<Uint8List> _buildExportPng(VietQrTransfer transfer) async {
    const width = 1080.0;
    const height = 1560.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = Colors.white;
    canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), paint);

    final titleStyle = const TextStyle(
      color: Color(0xFF1238C8),
      fontSize: 58,
      fontWeight: FontWeight.w800,
    );
    final labelStyle = TextStyle(color: Colors.grey[700], fontSize: 32);
    const valueStyle = TextStyle(
      color: Color(0xFF1F2430),
      fontSize: 38,
      fontWeight: FontWeight.w700,
    );

    _drawText(canvas, 'PhongVu OpsHub', 72, 64, titleStyle);
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
        color: Colors.black,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
    );
    canvas.translate(qrLeft, qrTop);
    qrPainter.paint(canvas, const Size(qrSize, qrSize));
    canvas.translate(-qrLeft, -qrTop);

    final logo = await _loadUiImage(_logoAsset);
    const logoSize = 150.0;
    final logoRect = Rect.fromCenter(
      center: const Offset(width / 2, qrTop + qrSize / 2),
      width: logoSize,
      height: logoSize,
    );
    final logoBg = RRect.fromRectAndRadius(
      logoRect.inflate(18),
      const Radius.circular(26),
    );
    canvas.drawRRect(logoBg, Paint()..color = Colors.white);
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(logoRect, const Radius.circular(20)),
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
      '${_currencyFormatter.format(transfer.amount)} VND',
      y,
      labelStyle,
      valueStyle,
    );
    _drawInfo(
      canvas,
      'Nội dung',
      transfer.transferContent,
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

class _QrWithLogo extends StatelessWidget {
  final double size;
  final VietQrTransfer transfer;

  const _QrWithLogo({required this.size, required this.transfer});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            QrImageView(
              data: transfer.qrPayload,
              version: QrVersions.auto,
              errorCorrectionLevel: QrErrorCorrectLevel.H,
              size: size,
              backgroundColor: Colors.white,
            ),
            Container(
              width: size * 0.24,
              height: size * 0.24,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.asset(
                  _VietQrScreenState._logoAsset,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(label, style: TextStyle(color: Colors.grey[700])),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
