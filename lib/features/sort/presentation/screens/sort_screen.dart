import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/sort_provider.dart';
import '../../../fifo_check/presentation/widgets/barcode_scanner_screen.dart';
import '../widgets/sort_sku_group_widget.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';

class SortScreen extends StatefulWidget {
  const SortScreen({super.key});

  @override
  State<SortScreen> createState() => _SortScreenState();
}

class _SortScreenState extends State<SortScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    try {
      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
      );

      if (result != null && mounted) {
        _controller.text = result;
        _focusNode.requestFocus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa quét được mã. Vui lòng thử lại.')),
        );
      }
    }
  }

  // Check if input looks like a serial number (mix of letters and digits, no dots/dashes)
  bool _looksLikeSerial(String text) {
    final trimmed = text.trim();
    // BIN contains dots or dashes (e.g., "LK.04-A-03-a")
    if (trimmed.contains('.') || trimmed.contains('-')) return false;
    // Serial = alphanumeric mix, longer than typical SKU
    final hasLetters = RegExp(r'[a-zA-Z]').hasMatch(trimmed);
    final hasDigits = RegExp(r'[0-9]').hasMatch(trimmed);
    return hasLetters && hasDigits;
  }

  Future<void> _sendSortRequest() async {
    final text = _controller.text.trim();

    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập SKU hoặc BIN')),
      );
      return;
    }

    // Warn if input looks like a serial number
    if (_looksLikeSerial(text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sắp xếp chỉ hỗ trợ SKU hoặc BIN.\nNếu cần kiểm tra serial, vui lòng dùng Kiểm tra FIFO.',
          ),
          duration: Duration(seconds: 3),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final sortProvider = context.read<SortProvider>();
    final userEmail = context.read<AuthProvider>().user?.email ?? '';

    _controller.clear();
    _focusNode.unfocus();

    await sortProvider.sendSortRequest(text, userEmail);

    if (mounted) {
      final error = sortProvider.error;

      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientHeader(title: 'Sắp xếp FIFO', showBack: true),
      body: SafeArea(
        child: AppResponsiveContent(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSurfaceCard(
                backgroundColor: AppColors.info.withValues(alpha: 0.08),
                borderColor: AppColors.info.withValues(alpha: 0.20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: AppColors.info,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Hướng dẫn',
                          style: AppTextStyles.labelL.copyWith(
                            color: AppColors.info,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Nhập hoặc quét mã SKU hoặc BIN để sắp xếp hàng hóa.',
                      style: AppTextStyles.bodyM.copyWith(
                        color: AppColors.neutral700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Consumer<SortProvider>(
                builder: (context, provider, child) {
                  if (provider.skuGroups != null &&
                      provider.skuGroups!.isNotEmpty) {
                    return Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Row(
                            children: [
                              const Icon(
                                Icons.inventory_2,
                                color: AppColors.info,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Kết quả',
                                style: AppTextStyles.labelL.copyWith(
                                  color: AppColors.info,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: ListView.builder(
                              itemCount: provider.skuGroups!.length,
                              itemBuilder: (context, index) {
                                final group = provider.skuGroups![index];
                                return SortSKUGroupWidget(
                                  group: group,
                                  onItemCheckChanged: (item) {
                                    provider.updateSKUItem(item);
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const Expanded(
                    child: AppStatePanel(
                      icon: Icons.inventory_2_outlined,
                      title: 'Chưa có kết quả sắp xếp',
                      message: 'Nhập SKU hoặc BIN để xem vị trí hàng hóa.',
                    ),
                  );
                },
              ),

              Consumer<SortProvider>(
                builder: (context, provider, child) {
                  final isLoading = provider.isLoading;

                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppLayoutTokens.actionBarMaxWidth,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: AppTextInput(
                              controller: _controller,
                              focusNode: _focusNode,
                              enabled: !isLoading,
                              label: 'SKU hoặc BIN',
                              hintText: 'Nhập SKU hoặc BIN',
                              icon: Icons.inventory_2_outlined,
                              textCapitalization: TextCapitalization.characters,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _sendSortRequest(),
                            ),
                          ),
                          const SizedBox(width: AppLayoutTokens.formInlineGap),
                          AppIconAction(
                            onPressed: isLoading ? null : _scanBarcode,
                            icon: Icons.qr_code_scanner_rounded,
                            tooltip: 'Quét mã',
                          ),
                          const SizedBox(width: AppLayoutTokens.formInlineGap),
                          AppIconAction(
                            onPressed: isLoading ? null : _sendSortRequest,
                            icon: Icons.send_rounded,
                            tooltip: 'Gửi',
                            filled: true,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
