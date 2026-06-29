import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/fifo_check_provider.dart';
import '../widgets/fifo_check_history_list.dart';
import '../widgets/fifo_check_input.dart';
import '../widgets/loading_indicator.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/gradient_header.dart';

class FifoCheckConversationScreen extends StatefulWidget {
  final VoidCallback? onBackToHome;

  const FifoCheckConversationScreen({super.key, this.onBackToHome});

  @override
  State<FifoCheckConversationScreen> createState() =>
      _FifoCheckConversationScreenState();
}

class _FifoCheckConversationScreenState
    extends State<FifoCheckConversationScreen> {
  @override
  void initState() {
    super.initState();
    // Load local FIFO check history when screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FifoCheckProvider>().loadHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Get keyboard height for manual padding
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: GradientHeader(
        title: 'Kiểm tra FIFO',
        showBack: widget.onBackToHome == null,
      ),
      body: Stack(
        children: [
          AppResponsiveContent(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Expanded(child: const FifoCheckHistoryList()),
                const FifoCheckInput(),
                SizedBox(height: keyboardHeight),
              ],
            ),
          ),
          Consumer<FifoCheckProvider>(
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
