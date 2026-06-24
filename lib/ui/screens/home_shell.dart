import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../widgets/conversation_list.dart';
import 'chat_screen.dart';
import 'welcome_screen.dart';

/// Width at/above which we show the two-pane (sidebar + detail) desktop layout.
const double kWideBreakpoint = 760;

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= kWideBreakpoint;
        return isWide ? const _WideLayout() : const _NarrowLayout();
      },
    );
  }
}

/// Desktop: conversation list on the left, selected chat (or welcome) on right.
class _WideLayout extends ConsumerWidget {
  const _WideLayout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedConversationProvider);

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 340,
            child: ConversationListPane(
              onSelect: (id) =>
                  ref.read(selectedConversationProvider.notifier).select(id),
              selectedId: selected,
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: selected == null
                ? const WelcomeScreen()
                : ChatPane(key: ValueKey(selected), conversationId: selected),
          ),
        ],
      ),
    );
  }
}

/// Mobile: just the list; tapping pushes the chat screen.
class _NarrowLayout extends ConsumerWidget {
  const _NarrowLayout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: ConversationListPane(
          onSelect: (id) {
            ref.read(selectedConversationProvider.notifier).select(id);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatScreen(conversationId: id),
              ),
            );
          },
          selectedId: null,
        ),
      ),
    );
  }
}
