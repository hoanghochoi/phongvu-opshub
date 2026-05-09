import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/repositories/vietqr_repository.dart';
import '../../domain/entities/vietqr_transfer.dart';

class VietQrScreen extends StatefulWidget {
  const VietQrScreen({super.key});

  @override
  State<VietQrScreen> createState() => _VietQrScreenState();
}

class _VietQrScreenState extends State<VietQrScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _orderCodeController = TextEditingController();
  final _storeCodeController = TextEditingController();
  final _currencyFormatter = NumberFormat.decimalPattern('vi_VN');
  late final VietQrRepository _repository;
  VietQrTransfer? _transfer;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _repository = VietQrRepository(ApiClient());
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
    super.dispose();
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
    return '$storeCode-$orderCode'.toUpperCase();
  }

  Future<void> _copyTransferContent() async {
    final content = _transfer?.transferContent;
    if (content == null || content.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: content));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã copy nội dung chuyển khoản')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final transfer = _transfer;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: const GradientHeader(title: 'Tạo VietQR', showBack: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildInputCard(),
                if (transfer != null) ...[
                  const SizedBox(height: 16),
                  _buildQrCard(transfer),
                ],
              ],
            ),
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
              decoration: const InputDecoration(
                labelText: 'Mã đơn',
                prefixIcon: Icon(Icons.receipt_long_outlined),
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
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
              key: ValueKey(_previewContent()),
              initialValue: _previewContent(),
              decoration: const InputDecoration(
                labelText: 'Nội dung chuyển khoản',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
              readOnly: true,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _isLoading ? null : _createQr,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.qr_code_2_rounded),
              label: Text(_isLoading ? 'Đang tạo...' : 'Tạo mã QR'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrCard(VietQrTransfer transfer) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: QrImageView(
                data: transfer.qrPayload,
                version: QrVersions.auto,
                size: 240,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            _InfoRow(label: 'Ngân hàng', value: transfer.bankBin),
            _InfoRow(label: 'Số tài khoản', value: transfer.accountNumber),
            _InfoRow(label: 'Chủ tài khoản', value: transfer.accountName),
            _InfoRow(
              label: 'Số tiền',
              value: '${_currencyFormatter.format(transfer.amount)} VND',
            ),
            _InfoRow(
              label: 'Nội dung',
              value: transfer.transferContent,
              action: IconButton(
                tooltip: 'Copy',
                onPressed: _copyTransferContent,
                icon: const Icon(Icons.copy_rounded),
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
  final Widget? action;

  const _InfoRow({required this.label, required this.value, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(color: Colors.grey[700])),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
