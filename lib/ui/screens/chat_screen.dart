import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/teams_conversation.dart';
import '../../state/providers.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_composer.dart';

/// Full-screen chat for the narrow (mobile) layout — wraps [ChatPane] with an
/// app bar and a back button.
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key, required this.conversationId});
  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conv = _findConversation(ref, conversationId);
    return Scaffold(
      appBar: AppBar(title: Text(conv?.title ?? 'Chat')),
      body: ChatPane(conversationId: conversationId, showHeader: false),
    );
  }
}

/// The reusable chat body (message list + composer), used directly in the wide
/// layout's detail pane and inside [ChatScreen] on mobile.
class ChatPane extends ConsumerStatefulWidget {
  const ChatPane({
    super.key,
    required this.conversationId,
    this.showHeader = true,
  });

  final String conversationId;
  final bool showHeader;

  @override
  ConsumerState<ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends ConsumerState<ChatPane> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(teamsControllerProvider.notifier)
          .loadHistory(widget.conversationId);
    });
  }

  @override
  void didUpdateWidget(covariant ChatPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(teamsControllerProvider.notifier)
            .loadHistory(widget.conversationId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(teamsControllerProvider);
    final self = state.self;
    final messages = state.messagesByConv[widget.conversationId] ?? const [];
    final loading = state.loadingHistory.contains(widget.conversationId);
    final conv = _findConversation(ref, widget.conversationId);

    return Column(
      children: [
        if (widget.showHeader && conv != null) _PaneHeader(conversation: conv),
        if (widget.showHeader && conv != null) const Divider(height: 1),
        Expanded(
          child: loading && messages.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : messages.isEmpty
                  ? Center(
                      child: Text(
                        'No messages yet. Say hello!',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  // SingleChildScrollView + Column (NOT a ListView) is used on
                  // purpose. Both ListView(children:) and ListView.builder are
                  // backed by a SliverList that lays children out lazily and
                  // only *estimates* the total scroll extent from the average
                  // measured item height. When one message is much taller than
                  // the rest, that estimate changes as the tall item scrolls in,
                  // so maxScrollExtent jumps every frame and the desktop
                  // scrollbar jitters. A Column measures every child up front,
                  // giving an exact, stable extent → smooth scrollbar. Message
                  // counts here are small, so laying out all of them is cheap.
                  //
                  // reverse:true anchors the viewport at the bottom (newest
                  // message) and keeps it pinned there as new messages arrive.
                  // Children stay in chronological order (oldest → newest).
                  : SingleChildScrollView(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final msg in messages)
                            MessageBubble(
                              message: msg,
                              // In a group, show sender on others' messages.
                              showSender: conv?.isOneToOne == false,
                              isSelf: msg.isFromSelf ||
                                  (self?.isSelf(msg.from) ?? false),
                            ),
                        ],
                      ),
                    ),
        ),
        MessageComposer(
          onSend: (text) => ref
              .read(teamsControllerProvider.notifier)
              .sendMessage(widget.conversationId, text),
        ),
      ],
    );
  }
}

class _PaneHeader extends StatelessWidget {
  const _PaneHeader({required this.conversation});
  final TeamsConversation conversation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            child: Text(conversation.title.isEmpty
                ? '?'
                : conversation.title.characters.first.toUpperCase()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              conversation.title.isEmpty ? '(unnamed)' : conversation.title,
              style: theme.textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!conversation.isOneToOne && conversation.memberCount != null)
            Text('${conversation.memberCount} members',
                style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

TeamsConversation? _findConversation(WidgetRef ref, String id) {
  final convs = ref.watch(teamsControllerProvider).conversations;
  for (final c in convs) {
    if (c.id == id) return c;
  }
  return null;
}
