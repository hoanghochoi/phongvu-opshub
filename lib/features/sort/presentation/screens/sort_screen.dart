import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/sort_provider.dart';
import '../../../chat/presentation/widgets/barcode_scanner_screen.dart';
import '../widgets/sort_sku_group_widget.dart';
import '../../../../app/widgets/gradient_header.dart';

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
        MaterialPageRoute(
          builder: (context) => const BarcodeScannerScreen(),
        ),
      );

      if (result != null && mounted) {
        _controller.text = result;
        _focusNode.requestFocus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi quét mã: $e')),
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
          content: Text('⚠️ Chức năng Sắp xếp chỉ hỗ trợ SKU hoặc BIN.\nĐể kiểm tra serial, vui lòng dùng Kiểm tra FIFO.'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.orange,
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
          SnackBar(
            content: Text(error),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: const GradientHeader(title: 'Sắp xếp FIFO', showBack: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hướng dẫn
              Card(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Hướng dẫn',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Nhập hoặc quét mã SKU hoặc BIN để sắp xếp hàng hóa.',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Response display
              Consumer<SortProvider>(
                builder: (context, provider, child) {
                  if (provider.skuGroups != null && provider.skuGroups!.isNotEmpty) {
                    return Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Row(
                            children: [
                              const Icon(
                                Icons.inventory_2,
                                color: Colors.blue,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Kết quả',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // SKU groups list
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
                  return const Spacer();
                },
              ),

              // Input area
              Consumer<SortProvider>(
                builder: (context, provider, child) {
                  final isLoading = provider.isLoading;

                  return Column(
                    children: [
                      // Input field
                      TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        enabled: !isLoading,
                        decoration: InputDecoration(
                          hintText: 'Nhập SKU hoặc BIN',
                          prefixIcon: const Icon(Icons.inventory_2_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        onSubmitted: (_) => _sendSortRequest(),
                      ),
                      const SizedBox(height: 16),

                      // Buttons
                      Row(
                        children: [
                          // Scan button
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: isLoading ? null : _scanBarcode,
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('Quét mã'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),

                          // Send button
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: isLoading ? null : _sendSortRequest,
                              icon: isLoading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : const Icon(Icons.send),
                              label: Text(isLoading ? 'Đang gửi...' : 'Gửi'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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
