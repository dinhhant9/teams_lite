/// A single chat message, parsed from a `RichText/Html` (or `Text`) resource.
///
/// Ported from the text-handling branch of `process_message_resource`.
class TeamsMessage {
  /// Server message id (`id`), when present.
  final String? id;

  /// Conversation/thread id this message belongs to.
  final String conversationId;

  /// Sender id with any numeric prefix stripped (e.g. `orgid:abc`,
  /// `live:.cid.x`). `null`/empty is treated as a system message.
  final String? from;

  /// Sender display name (`imdisplayname` / `imDisplayName`), if provided.
  final String? displayName;

  /// HTML content as delivered by the server.
  final String content;

  /// `composetime` parsed to a local [DateTime].
  final DateTime composeTime;

  /// Whether this message was authored by the signed-in user.
  final bool isFromSelf;

  /// Client message id used for echo de-duplication.
  final String? clientMessageId;

  const TeamsMessage({
    this.id,
    required this.conversationId,
    required this.from,
    required this.displayName,
    required this.content,
    required this.composeTime,
    required this.isFromSelf,
    this.clientMessageId,
  });

  /// Stable key for de-duping in the UI list (server id, else client id, else
  /// a content+time composite).
  String get dedupeKey =>
      id ?? clientMessageId ?? '$conversationId|${composeTime.millisecondsSinceEpoch}|$content';
}
