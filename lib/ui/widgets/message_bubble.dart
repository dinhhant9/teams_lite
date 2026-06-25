import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/teams_message.dart';

/// A single chat bubble. Teams messages are `RichText/Html`, so the content is
/// rendered as real formatted HTML (bold/italic/links/lists/images) rather than
/// stripped to plain text.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isSelf,
    required this.showSender,
    this.skypeToken,
  });

  final TeamsMessage message;
  final bool isSelf;
  final bool showSender;

  /// Skype token used to authenticate inline image downloads from Skype/Teams
  /// asset hosts (sent as the `skypetoken_asm` cookie).
  final String? skypeToken;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Skip rendering bubbles whose HTML has no visible text/content.
    if (_isEffectivelyEmpty(message.content)) return const SizedBox.shrink();

    final bubbleColor = isSelf
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final textColor =
        isSelf ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    // HtmlWidget renders block-level content that fills the available width, so
    // short messages would otherwise stretch the whole bubble. IntrinsicWidth
    // makes the bubble hug its content (still wrapping at maxWidth). Skip it for
    // media (img/table), which may not support intrinsic-width measurement.
    final hugContent = !_hasMedia(message.content);

    final bubbleBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // SelectionArea keeps the rendered HTML text selectable.
        SelectionArea(
          child: HtmlWidget(
            message.content,
            // Inject the skype-token cookie when fetching Skype/Teams images.
            factoryBuilder: () => _SkypeImageFactory(skypeToken),
            textStyle:
                theme.textTheme.bodyMedium?.copyWith(color: textColor),
            // Make links legible on top of the bubble colour.
            customStylesBuilder: (element) {
              if (element.localName == 'a') {
                return {
                  'color': _cssHex(textColor),
                  'text-decoration': 'underline',
                };
              }
              return null;
            },
            onTapUrl: _openUrl,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          DateFormat.Hm().format(message.composeTime),
          style: theme.textTheme.labelSmall?.copyWith(
            color: textColor.withValues(alpha: 0.7),
          ),
        ),
      ],
    );

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
                  child: hugContent
                      ? IntrinsicWidth(child: bubbleBody)
                      : bubbleBody,
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

  static Future<bool> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// True when the HTML contains media whose intrinsic width can't be measured
  /// reliably (images/tables) — those bubbles render full-width instead.
  static bool _hasMedia(String html) =>
      html.contains('<img') || html.contains('<table');

  /// `#rrggbb` for a Flutter [Color] (no alpha), for the HTML style map.
  static String _cssHex(Color color) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
  }

  /// True when the HTML carries no visible text and no media — avoids rendering
  /// empty bubbles (e.g. reaction-only updates).
  static bool _isEffectivelyEmpty(String html) {
    if (html.contains('<img') ||
        html.contains('<table') ||
        html.contains('<ul') ||
        html.contains('<ol')) {
      return false;
    }
    final text = html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text.isEmpty;
  }
}

/// Custom fwfh factory that authenticates inline image downloads.
///
/// Skype/Teams asset hosts (e.g. `*.asm.skype.com`) require the skype token to
/// be presented as a `skypetoken_asm` cookie, otherwise they return 401. We
/// attach that cookie only for Skype/Teams hosts so the token is never sent to
/// arbitrary third-party image servers.
class _SkypeImageFactory extends WidgetFactory {
  _SkypeImageFactory(this.skypeToken);

  final String? skypeToken;

  @override
  ImageProvider? imageProviderFromNetwork(String url) {
    if (url.isEmpty) return null;
    final token = skypeToken;
    if (token != null && token.isNotEmpty && _needsSkypeAuth(url)) {
      return NetworkImage(url, headers: {'Cookie': 'skypetoken_asm=$token'});
    }
    return NetworkImage(url);
  }

  static bool _needsSkypeAuth(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.endsWith('skype.com') ||
        host.endsWith('skypeassets.com') ||
        host.endsWith('teams.live.com') ||
        host.endsWith('teams.microsoft.com');
  }
}
