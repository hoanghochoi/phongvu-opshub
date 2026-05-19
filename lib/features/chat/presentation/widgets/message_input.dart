import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../core/utils/validators.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'barcode_scanner_screen.dart';

class MessageInput extends StatefulWidget {
  const MessageInput({super.key});

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  // Static constant to avoid recreation per build
  static final _inputShadow = [
    BoxShadow(
      offset: const Offset(0, -2),
      blurRadius: 4,
      color: Colors.black.withValues(alpha: 0.1),
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
      final result = await Navigator.of(context, rootNavigator: false)
          .push<String>(
            MaterialPageRoute(
              builder: (context) => const BarcodeScannerScreen(),
            ),
          );

      if (result != null && mounted) {
        // Auto-send scanned SKU/Serial immediately
        final chatProvider = context.read<ChatProvider>();
        final authProvider = context.read<AuthProvider>();
        final userEmail = authProvider.user?.email ?? '';

        await chatProvider.sendMessage(result, userEmail);

        if (chatProvider.error != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(chatProvider.error!),
              backgroundColor: Colors.red,
            ),
          );
          chatProvider.clearError();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi quét mã: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final message = _controller.text.trim();

    if (message.isEmpty) return;

    if (!Validators.isValidMessage(message)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Format không đúng. Nhập: SKU, SKU SỐ_LƯỢNG, hoặc SERIAL\nVí dụ: ABC123 hoặc ABC123 10',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final chatProvider = context.read<ChatProvider>();
    final authProvider = context.read<AuthProvider>();
    final userEmail = authProvider.user?.email ?? '';

    _controller.clear();
    _focusNode.unfocus();

    await chatProvider.sendMessage(message, userEmail);

    if (chatProvider.error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(chatProvider.error!),
          backgroundColor: Colors.red,
        ),
      );
      chatProvider.clearError();
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
      child: Selector<ChatProvider, bool>(
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
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: !isLoading,
                  decoration: const InputDecoration(
                    hintText: 'Nhập SKU / Serial (VD: ABC123 3)',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              AppIconAction(
                onPressed: isLoading ? null : _sendMessage,
                icon: Icons.send,
                tooltip: 'Gửi',
              ),
            ],
          );
        },
      ),
    );
  }
}
