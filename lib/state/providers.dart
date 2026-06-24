import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/session_store.dart';
import 'teams_controller.dart';
import 'teams_state.dart';

/// Secure storage for the refresh token + endpoint id.
final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

/// The single connection controller for the whole app.
final teamsControllerProvider =
    NotifierProvider<TeamsController, TeamsState>(TeamsController.new);

/// Currently selected conversation id (null → show the welcome pane).
class SelectedConversation extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? conversationId) => state = conversationId;
}

final selectedConversationProvider =
    NotifierProvider<SelectedConversation, String?>(SelectedConversation.new);
