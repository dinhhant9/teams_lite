import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/teams_conversation.dart';
import '../../state/providers.dart';

/// The left-hand conversation list (used in both layouts).
class ConversationListPane extends ConsumerWidget {
  const ConversationListPane({
    super.key,
    required this.onSelect,
    required this.selectedId,
  });

  final void Function(String conversationId) onSelect;
  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(teamsControllerProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(self: state.self?.displayName ?? 'Chat'),
        const Divider(height: 1),
        Expanded(
          child: state.conversations.isEmpty
              ? Center(
                  child: Text(
                    'No conversations yet',
                    style: theme.textTheme.bodySmall,
                  ),
                )
              : ListView.builder(
                  itemCount: state.conversations.length,
                  itemBuilder: (context, index) {
                    final conv = state.conversations[index];
                    return _ConversationTile(
                      conversation: conv,
                      selected: conv.id == selectedId,
                      onTap: () => onSelect(conv.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.self});
  final String self;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Chat', style: theme.textTheme.titleLarge),
                Text(
                  self,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu),
            onSelected: (value) {
              final notifier = ref.read(teamsControllerProvider.notifier);
              switch (value) {
                case 'reload':
                  notifier.reload();
                case 'logout':
                  notifier.logout();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'reload',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh),
                  title: Text('Reload'),
                ),
              ),
              PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout),
                  title: Text('Logout'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.selected,
    required this.onTap,
  });

  final TeamsConversation conversation;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = conversation.title.isEmpty ? '(unnamed)' : conversation.title;

    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
          : Colors.transparent,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          child: Text(_initials(title)),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: conversation.lastMessagePreview.isEmpty
            ? null
            : Text(
                conversation.lastMessagePreview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: conversation.lastMessageTime == null
            ? null
            : Text(
                _formatTime(conversation.lastMessageTime!),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
      ),
    );
  }

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  static String _formatTime(DateTime time) {
    final now = DateTime.now();
    final isToday =
        now.year == time.year && now.month == time.month && now.day == time.day;
    if (isToday) return DateFormat.Hm().format(time);
    final isThisYear = now.year == time.year;
    return isThisYear
        ? DateFormat.MMMd().format(time)
        : DateFormat.yMd().format(time);
  }
}
