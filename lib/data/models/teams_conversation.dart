/// A conversation/thread shown in the left-hand list.
///
/// Built from the `conversations[]` entries returned by
/// `/v1/users/ME/conversations` (`teams_got_all_convs` +
/// `process_conversation_resource`).
class TeamsConversation {
  /// Thread id (`id`), e.g. `19:...@unq.gbl.spaces` or a group `19:...@thread`.
  final String id;

  /// Display title — `threadProperties.topic` for groups, or the resolved
  /// other-party display name for 1:1 chats.
  String title;

  /// For 1:1 chats, the other participant's id (prefix-stripped).
  String? buddyId;

  /// Whether this is a one-to-one (unique roster / OneToOneChat) thread.
  final bool isOneToOne;

  /// Number of members, when known.
  final int? memberCount;

  /// Preview text of the most recent message (plain text).
  String lastMessagePreview;

  /// Timestamp of the most recent message.
  DateTime? lastMessageTime;

  TeamsConversation({
    required this.id,
    required this.title,
    this.buddyId,
    required this.isOneToOne,
    this.memberCount,
    this.lastMessagePreview = '',
    this.lastMessageTime,
  });
}
