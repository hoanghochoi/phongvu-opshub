import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../providers/fifo_check_provider.dart';
import 'fifo_check_entry_card.dart';

class FifoCheckHistoryList extends StatelessWidget {
  const FifoCheckHistoryList({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FifoCheckProvider>(
      builder: (context, provider, child) {
        final entries = provider.entries;

        if (entries.isEmpty) {
          return const AppStatePanel.empty(
            title: 'Nhập SKU hoặc serial để kiểm tra FIFO',
            message: 'Có thể nhập thêm số lượng, ví dụ ABC123 10.',
            icon: Icons.inventory_2_outlined,
          );
        }

        // reverse: true keeps latest entries at bottom without manual scrolling.
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.all(8.0),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final reversedIndex = entries.length - 1 - index;
            return FifoCheckEntryCard(entry: entries[reversedIndex]);
          },
        );
      },
    );
  }
}
