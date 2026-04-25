import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/message_list.dart';
import '../widgets/message_input.dart';
import '../widgets/loading_indicator.dart';
import '../../../../app/widgets/gradient_header.dart';

class ChatScreen extends StatefulWidget {
  final VoidCallback? onBackToHome;

  const ChatScreen({
    super.key,
    this.onBackToHome,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  @override
  void initState() {
    super.initState();
    // Load local chat history when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Get keyboard height for manual padding
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      resizeToAvoidBottomInset: false,
      appBar: GradientHeader(
        title: 'Kiểm tra FIFO',
        showBack: widget.onBackToHome == null,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: const MessageList(),
              ),
              const MessageInput(),
              SizedBox(height: keyboardHeight),
            ],
          ),
          Consumer<ChatProvider>(
            builder: (context, provider, child) {
              return provider.isLoading
                  ? const Positioned.fill(child: LoadingIndicator())
                  : const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }
}
