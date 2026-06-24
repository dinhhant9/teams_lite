import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/teams_message.dart';

/// A single chat bubble. The MVP renders message HTML as plain text (tags
/// stripped, entities decoded); rich rendering can be layered on later.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isSelf,
    required this.showSender,
  });

  final TeamsMessage message;
  final bool isSelf;
  final bool showSender;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = _htmlToText(message.content);
    if (text.isEmpty) return const SizedBox.shrink();

    final bubbleColor = isSelf
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final textColor =
        isSelf ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment:
            isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showSender && !isSelf && _senderLabel != null)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 2),
              child: Text(
                _senderLabel!,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          Row(
            mainAxisAlignment:
                isSelf ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 520),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(14),
                      topRight: const Radius.circular(14),
                      bottomLeft: Radius.circular(isSelf ? 14 : 4),
                      bottomRight: Radius.circular(isSelf ? 4 : 14),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        text,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: textColor),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat.Hm().format(message.composeTime),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: textColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? get _senderLabel {
    final name = message.displayName;
    if (name != null && name.isNotEmpty && !name.startsWith('orgid:')) {
      return name;
    }
    return message.from;
  }

  static String _htmlToText(String html) {
    var text = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '');
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    return text.trim();
  }
}
