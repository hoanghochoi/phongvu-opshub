import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/message.dart';

class MessageBubble extends StatelessWidget {
  final Message message;

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
    final regex = RegExp(r'(Serial|Mã BIN):\s*(\S+)', caseSensitive: false);
    int lastIndex = 0;

    for (final match in regex.allMatches(content)) {
      // Add normal text before match
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: content.substring(lastIndex, match.start),
          style: const TextStyle(
            color: Colors.black87,
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ));
      }

      // Add label (Serial: or BIN:)
      spans.add(TextSpan(
        text: '${match.group(1)!}: ',
        style: const TextStyle(
          color: Colors.black87,
          fontFamily: 'monospace',
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ));

      // Add highlighted value (clickable)
      final value = match.group(2)!;
      final tapRecognizer = TapGestureRecognizer()
        ..onTap = () => _copyToClipboard(context, value);

      spans.add(TextSpan(
        text: value,
        style: const TextStyle(
          color: Colors.blue,
          fontFamily: 'monospace',
          fontSize: 14,
          fontWeight: FontWeight.bold,
          decoration: TextDecoration.underline,
        ),
        recognizer: tapRecognizer,
      ));

      lastIndex = match.end;
    }

    // Add remaining text
    if (lastIndex < content.length) {
      spans.add(TextSpan(
        text: content.substring(lastIndex),
        style: const TextStyle(
          color: Colors.black87,
          fontFamily: 'monospace',
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
    final regex = RegExp(r'(SKU|sku):\s*(\S+)', caseSensitive: false);
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

      // Add highlighted value (clickable)
      final value = match.group(2)!;
      final tapRecognizer = TapGestureRecognizer()
        ..onTap = () => _copyToClipboard(context, value);

      spans.add(TextSpan(
        text: value,
        style: const TextStyle(
          color: Colors.yellowAccent,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          decoration: TextDecoration.underline,
        ),
        recognizer: tapRecognizer,
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
    final timeFormat = DateFormat('HH:mm');

    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: message.isUser
              ? Theme.of(context).colorScheme.primary
              : Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nội dung tin nhắn
            message.isUser
                ? _buildUserMessage(context)
                : _buildBotMessage(context),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeFormat.format(message.timestamp),
                  style: TextStyle(
                    color: message.isUser ? Colors.white70 : Colors.black54,
                    fontSize: 10,
                  ),
                ),
                // Nút copy toàn bộ cho bot messages
                if (!message.isUser) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _copyToClipboard(context, message.content),
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(
                        Icons.copy,
                        size: 12,
                        color: Colors.black54,
                      ),
                    ),
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
