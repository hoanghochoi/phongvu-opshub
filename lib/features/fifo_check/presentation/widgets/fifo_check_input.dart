import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/fifo_check_provider.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../core/utils/validators.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'barcode_scanner_screen.dart';

class FifoCheckInput extends StatefulWidget {
  const FifoCheckInput({super.key});

  @override
  State<FifoCheckInput> createState() => _FifoCheckInputState();
}

class _FifoCheckInputState extends State<FifoCheckInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  // Static constant to avoid recreation per build
  static final _inputShadow = [
    BoxShadow(
      offset: const Offset(0, -2),
      blurRadius: 4,
      color: AppColors.shadow.withValues(alpha: 0.1),
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    try {
      final result = await showBarcodeScanner(context);

      if (result != null && mounted) {
        // Auto-send scanned SKU/Serial immediately
        final fifoCheckProvider = context.read<FifoCheckProvider>();
        final authProvider = context.read<AuthProvider>();
        final userEmail = authProvider.user?.email ?? '';

        await fifoCheckProvider.runCheck(result, userEmail);

        if (fifoCheckProvider.error != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(fifoCheckProvider.error!),
              backgroundColor: AppColors.error,
            ),
          );
          fifoCheckProvider.clearError();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chưa quét được mã. Vui lòng thử lại.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _submitFifoCheck() async {
    final input = _controller.text.trim();

    if (input.isEmpty) return;

    if (!Validators.isValidFifoCheckInput(input)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nội dung chưa đúng. Nhập SKU, SKU + số lượng, hoặc serial.\nVí dụ: ABC123 hoặc ABC123 10',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final fifoCheckProvider = context.read<FifoCheckProvider>();
    final authProvider = context.read<AuthProvider>();
    final userEmail = authProvider.user?.email ?? '';

    _controller.clear();
    _focusNode.unfocus();

    await fifoCheckProvider.runCheck(input, userEmail);

    if (fifoCheckProvider.error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(fifoCheckProvider.error!),
          backgroundColor: AppColors.error,
        ),
      );
      fifoCheckProvider.clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: _inputShadow,
      ),
      child: Selector<FifoCheckProvider, bool>(
        selector: (_, provider) => provider.isLoading,
        builder: (context, isLoading, child) {
          return Row(
            children: [
              // Nút quét barcode/QR code
              AppIconAction(
                onPressed: isLoading ? null : _scanBarcode,
                icon: Icons.qr_code_scanner,
                tooltip: 'Quét mã',
              ),
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              Expanded(
                child: AppTextInput(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: !isLoading,
                  label: 'SKU hoặc serial',
                  icon: Icons.inventory_2_outlined,
                  hintText: 'VD: ABC123 3',
                  onSubmitted: (_) => _submitFifoCheck(),
                ),
              ),
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              AppIconAction(
                onPressed: isLoading ? null : _submitFifoCheck,
                icon: Icons.send,
                tooltip: 'Kiểm tra',
              ),
            ],
          );
        },
      ),
    );
  }
}
