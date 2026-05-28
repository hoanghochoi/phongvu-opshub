import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../app/theme/app_colors.dart';
import '../../domain/entities/message.dart';
import 'sku_bubble.dart';

class MessageBubble extends StatelessWidget {
  final Message message;

  // Cached formatters - avoid recreating on every build
  static final DateFormat _timeFormat = DateFormat('HH:mm');
  static final RegExp _botRegex = RegExp(r'(Serial|Mã BIN):\s*(\S+)', caseSensitive: false);
  static final RegExp _userRegex = RegExp(r'(SKU|sku):\s*(\S+)', caseSensitive: false);

  const MessageBubble({
    super.key,
    required this.message,
  });

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã copy: $text'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Build rich text with highlighted Serial and BIN for bot messages
  Widget _buildBotMessage(BuildContext context) {
    final content = message.content;
    final spans = <TextSpan>[];

    // Regex to match Serial: followed by value and BIN: followed by value
    final regex = _botRegex;
    int lastIndex = 0;

    for (final match in regex.allMatches(content)) {
      // Add normal text before match
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: content.substring(lastIndex, match.start),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 14,
          ),
        ));
      }

      // Add label (Serial: or BIN:)
      spans.add(TextSpan(
        text: '${match.group(1)!}: ',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ));

      // Add highlighted value (selectable)
      final value = match.group(2)!;

      spans.add(TextSpan(
        text: value,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          decoration: TextDecoration.underline,
        ),
      ));

      lastIndex = match.end;
    }

    // Add remaining text
    if (lastIndex < content.length) {
      spans.add(TextSpan(
        text: content.substring(lastIndex),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 14,
        ),
      ));
    }

    // Use SelectableText.rich to allow text selection while keeping tap recognizers
    return SelectableText.rich(
      TextSpan(children: spans),
    );
  }

  // Build rich text with highlighted SKU for user messages
  Widget _buildUserMessage(BuildContext context) {
    final content = message.content;

    // Regex to match SKU: followed by value
    final regex = _userRegex;
    final matches = regex.allMatches(content).toList();

    // If no SKU found, return plain selectable text
    if (matches.isEmpty) {
      return SelectableText(
        content,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
        ),
      );
    }

    // Build rich text with SKU highlighting
    final spans = <TextSpan>[];
    int lastIndex = 0;

    for (final match in matches) {
      // Add normal text before match
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: content.substring(lastIndex, match.start),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
        ));
      }

      // Add label (SKU:)
      spans.add(TextSpan(
        text: '${match.group(1)!}: ',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ));

      // Add highlighted value (selectable)
      final value = match.group(2)!;

      spans.add(TextSpan(
        text: value,
        style: const TextStyle(
          color: Colors.yellowAccent,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          decoration: TextDecoration.underline,
        ),
      ));

      lastIndex = match.end;
    }

    // Add remaining text
    if (lastIndex < content.length) {
      spans.add(TextSpan(
        text: content.substring(lastIndex),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
        ),
      ));
    }

    // Use SelectableText.rich to allow text selection while keeping tap recognizers
    return SelectableText.rich(
      TextSpan(children: spans),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeFormat = _timeFormat;

    // If bot message has SKU items, display SKU bubbles
    if (!message.isUser && message.skuItems != null && message.skuItems!.isNotEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Show message text above bubbles (e.g., "✅ Đúng FIFO")
              if (message.content.isNotEmpty && !message.content.contains('SKU:')) ...[
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: message.content.contains('✅')
                        ? (Theme.of(context).brightness == Brightness.dark
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.green[50])
                        : message.content.contains('❌')
                            ? (Theme.of(context).brightness == Brightness.dark
                                ? Colors.red.withValues(alpha: 0.15)
                                : Colors.red[50])
                            : (Theme.of(context).brightness == Brightness.dark
                                ? AppColors.darkNeutral100
                                : Colors.grey[200]),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: message.content.contains('✅')
                          ? (Theme.of(context).brightness == Brightness.dark
                              ? Colors.green[700]!
                              : Colors.green[300]!)
                          : message.content.contains('❌')
                              ? (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.red[700]!
                                  : Colors.red[300]!)
                              : (Theme.of(context).brightness == Brightness.dark
                                  ? AppColors.neutral700
                                  : Colors.grey[400]!),
                    ),
                  ),
                  child: Text(
                    message.content,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: message.content.contains('✅')
                          ? (Theme.of(context).brightness == Brightness.dark
                              ? Colors.green[300]
                              : Colors.green[800])
                          : message.content.contains('❌')
                              ? (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.red[300]
                                  : Colors.red[800])
                              : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
              // Checked item's SKU Bubbles
              ...message.skuItems!.map((skuItem) => SKUBubble(
                    skuItem: skuItem,
                    onCheckChanged: (item) {
                      // State is managed in SKUItem.isChecked
                    },
                  )),
              // FIFO Suggestion section
              if (message.suggestedItems != null && message.suggestedItems!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.amber.withValues(alpha: 0.15)
                        : Colors.amber[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.amber[700]!
                          : Colors.amber[400]!,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.amber[300]
                                : Colors.amber[700],
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Gợi ý — Sản phẩm cần lấy trước:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.amber[300]
                                    : Colors.amber[900],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...message.suggestedItems!.map((skuItem) => SKUBubble(
                            skuItem: skuItem,
                            onCheckChanged: (item) {},
                          )),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 4),
              // Timestamp
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  timeFormat.format(message.timestamp),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Default message bubble (for user messages or bot messages without SKU items)
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: message.isUser
              ? Theme.of(context).colorScheme.primary
              : (Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkNeutral100
                  : Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nội dung tin nhắn
            SelectionArea(
              child: message.isUser
                  ? _buildUserMessage(context)
                  : _buildBotMessage(context),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeFormat.format(message.timestamp),
                  style: TextStyle(
                    color: message.isUser
                        ? Colors.white70
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                // Nút copy toàn bộ cho bot messages
                if (!message.isUser) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _copyToClipboard(context, message.content),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.copy,
                        size: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.check_circle,
                    size: 14,
                    color: Colors.green,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
