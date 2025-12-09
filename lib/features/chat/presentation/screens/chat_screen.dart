import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/message_list.dart';
import '../widgets/message_input.dart';
import '../widgets/loading_indicator.dart';

class ChatScreen extends StatelessWidget {
  final VoidCallback? onBackToHome;

  const ChatScreen({
    super.key,
    this.onBackToHome,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat với BOT'),
        leading: onBackToHome != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onBackToHome,
              )
            : null,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              const Expanded(child: MessageList()),
              SafeArea(
                top: false,
                child: const MessageInput(),
              ),
            ],
          ),
          Consumer<ChatProvider>(
            builder: (context, provider, child) {
              return provider.isLoading
                  ? const LoadingIndicator()
                  : const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }
}
