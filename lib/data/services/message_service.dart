import '../../core/teams_constants.dart';
import '../../core/teams_util.dart';
import '../models/teams_conversation.dart';
import '../models/teams_message.dart';
import '../models/teams_self.dart';
import 'teams_http_client.dart';

/// Ports the conversation/message endpoints of `teams_messages.c` for the
/// text-only MVP: list conversations, fetch history, send a message, and parse
/// incoming message resources (shared between history fetches and trouter
/// events).
class MessageService {
  final TeamsHttpClient _http;

  /// The signed-in identity, needed to decide `isFromSelf`. Set after
  /// self-details load.
  TeamsSelf? self;

  /// 1:1 buddy ↔ conversation maps (`buddy_to_chat_lookup` /
  /// `chat_to_buddy_lookup`).
  final Map<String, String> buddyToChat = {};
  final Map<String, String> chatToBuddy = {};

  /// Client message ids we've sent, for echo de-duplication
  /// (`sent_messages_hash`).
  final Set<String> _sentMessageIds = {};

  /// `time` values of already-processed trouter events
  /// (`processed_event_messages`), capped like the plugin.
  final List<String> _processedEventTimes = [];

  static const String _targetTypes =
      'Passport|Skype|Lync|Thread|PSTN|Agent';

  MessageService(this._http);

  // --- Conversation list (teams_get_all_conversations_since) ---

  Future<List<TeamsConversation>> getAllConversations({int since = 0}) async {
    final path = '${TeamsConstants.contactsPathPrefix}'
        '/v1/users/ME/conversations'
        '?startTime=${since}000&pageSize=100&view=msnp24Equivalent'
        '&targetType=$_targetTypes';

    final res = await _http.get(path);
    final data = res.data;
    if (data is! Map) return [];

    final convs = data['conversations'];
    if (convs is! List) return [];

    final result = <TeamsConversation>[];
    for (final raw in convs) {
      if (raw is! Map) continue;
      final conv = _parseConversation(raw.cast<String, dynamic>());
      if (conv != null) result.add(conv);
    }

    // Most-recent first.
    result.sort((a, b) => (b.lastMessageTime ?? DateTime(0))
        .compareTo(a.lastMessageTime ?? DateTime(0)));
    return result;
  }

  TeamsConversation? _parseConversation(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    if (id == null) return null;

    final threadProps = json['threadProperties'];
    final props = threadProps is Map ? threadProps.cast<String, dynamic>() : null;
    final lastMessage = json['lastMessage'];
    final last =
        lastMessage is Map ? lastMessage.cast<String, dynamic>() : null;

    final uniqueRoster = props?['uniquerosterthread']?.toString();
    final productType = props?['productThreadType']?.toString();
    final isOneToOne =
        uniqueRoster == 'true' || productType == 'OneToOneChat';

    final topic = props?['topic']?.toString();
    final memberCount = int.tryParse(props?['membercount']?.toString() ?? '');

    // Resolve the 1:1 buddy (process_conversation_resource).
    String? buddyId;
    if (isOneToOne) {
      buddyId = _resolveOneToOneBuddy(id, last);
      if (buddyId != null) {
        buddyToChat[buddyId] = id;
        chatToBuddy[id] = buddyId;
      }
    }

    // Preview + timestamp from the last message.
    String preview = '';
    DateTime? lastTime;
    String? lastSenderName;
    if (last != null) {
      preview = _htmlToPreview(last['content']?.toString() ?? '');
      lastTime = _parseTime(last['composetime']?.toString());
      lastSenderName = last['imdisplayname']?.toString() ??
          last['imDisplayName']?.toString();
    }

    // Title: group → topic; 1:1 → other party's name, else their id.
    String title;
    if (topic != null && topic.isNotEmpty) {
      title = topic;
    } else if (isOneToOne) {
      final senderFrom =
          TeamsUtil.contactUrlToName(last?['from']?.toString());
      if (lastSenderName != null &&
          lastSenderName.isNotEmpty &&
          self?.isSelf(senderFrom) == false &&
          !lastSenderName.startsWith('orgid:')) {
        title = lastSenderName;
      } else {
        title = TeamsUtil.stripUserPrefix(buddyId ?? id);
      }
    } else {
      title = TeamsUtil.stripUserPrefix(id);
    }

    return TeamsConversation(
      id: id,
      title: title,
      buddyId: buddyId,
      isOneToOne: isOneToOne,
      memberCount: memberCount,
      lastMessagePreview: preview,
      lastMessageTime: lastTime,
    );
  }

  /// process_conversation_resource: figure out the other participant of a 1:1.
  String? _resolveOneToOneBuddy(String id, Map<String, dynamic>? lastMessage) {
    final existing = chatToBuddy[id];
    if (existing != null) return existing;

    String? buddyId;
    if (lastMessage != null) {
      buddyId = TeamsUtil.contactUrlToName(lastMessage['from']?.toString());
    }

    if (buddyId == null || (self?.isSelf(buddyId) ?? false)) {
      if (id.startsWith('19:uni01_')) return null; // not guessable
      // Guess from the chat id, e.g. 19:aaa_bbb@unq.gbl.spaces.
      final parts = id.split(RegExp(r'[:_@]'));
      if (parts.length >= 3) {
        buddyId = 'orgid:${parts[1]}';
        if (self?.isSelf(buddyId) ?? false) {
          buddyId = 'orgid:${parts[2]}';
        }
      }
    }
    return buddyId;
  }

  // --- History (teams_get_conversation_history_since) ---

  Future<List<TeamsMessage>> getConversationHistory(
    String conversationId, {
    int since = 0,
  }) async {
    final encoded = Uri.encodeComponent(conversationId);
    final path = '${TeamsConstants.contactsPathPrefix}'
        '/v1/users/ME/conversations/$encoded/messages'
        '?startTime=${since}000&pageSize=30&view=msnp24Equivalent'
        '&targetType=$_targetTypes';

    final res = await _http.get(path);
    final data = res.data;
    if (data is! Map) return [];
    final messages = data['messages'];
    if (messages is! List) return [];

    final result = <TeamsMessage>[];
    for (final raw in messages) {
      if (raw is! Map) continue;
      final msg = parseMessageResource(
        raw.cast<String, dynamic>(),
        fallbackConversationId: conversationId,
        dedupeSent: false,
      );
      if (msg != null) result.add(msg);
    }
    // Server returns newest-first; present oldest-first.
    result.sort((a, b) => a.composeTime.compareTo(b.composeTime));
    return result;
  }

  // --- Send (teams_send_message) ---

  /// Posts [htmlContent] to [conversationId] and returns the client message id.
  Future<String> sendMessage(String conversationId, String htmlContent) async {
    final encoded = Uri.encodeComponent(conversationId);
    final path = '${TeamsConstants.contactsPathPrefix}'
        '/v1/users/ME/conversations/$encoded/messages';

    final clientMessageId = TeamsUtil.jsTime().toString();
    _sentMessageIds.add(clientMessageId);

    final body = {
      'clientmessageid': clientMessageId,
      'content': htmlContent,
      'messagetype': 'RichText/Html',
      'contenttype': 'text',
      'imdisplayname': self?.displayName ?? self?.username ?? '',
    };

    await _http.post(path, body: body);
    return clientMessageId;
  }

  // --- Shared parser (process_message_resource, text branch) ---

  /// Returns a [TeamsMessage] for text content, or `null` for non-text
  /// resources (typing/control/thread-activity) which the MVP ignores.
  ///
  /// When [dedupeSent] is true (trouter events), messages we sent ourselves are
  /// suppressed via the client-message-id hash.
  TeamsMessage? parseMessageResource(
    Map<String, dynamic> resource, {
    String? fallbackConversationId,
    bool dedupeSent = true,
  }) {
    final messageType = resource['messagetype']?.toString();
    if (messageType == null) return null;

    final clientMessageId = resource['clientmessageid']?.toString();
    if (dedupeSent &&
        clientMessageId != null &&
        _sentMessageIds.remove(clientMessageId)) {
      return null; // echo of our own message
    }

    final parts = messageType.split('/');
    final isText =
        parts.first == 'RichText' || messageType == 'Text';
    if (!isText) return null; // MVP: text only

    final content = resource['content']?.toString() ?? '';
    if (content.isEmpty) return null;

    final fromRaw = resource['from']?.toString();
    final from = TeamsUtil.contactUrlToName(fromRaw);

    final conversationLink = resource['conversationLink']?.toString();
    final conversationId = TeamsUtil.threadUrlToName(conversationLink) ??
        fallbackConversationId ??
        '';

    final composeTime =
        _parseTime(resource['composetime']?.toString()) ?? DateTime.now();

    final displayName = resource['imdisplayname']?.toString() ??
        resource['imDisplayName']?.toString();

    return TeamsMessage(
      id: resource['id']?.toString(),
      conversationId: conversationId,
      from: from,
      displayName: displayName,
      content: content,
      composeTime: composeTime,
      isFromSelf: self?.isSelf(from) ?? false,
      clientMessageId: clientMessageId,
    );
  }

  /// teams_process_event_message de-dup: returns false if [time] was already
  /// handled.
  bool registerEventTime(String? time) {
    if (time == null) return true;
    if (_processedEventTimes.contains(time)) return false;
    _processedEventTimes.insert(0, time);
    if (_processedEventTimes.length > TeamsConstants.maxProcessedEventBuffer) {
      _processedEventTimes.removeLast();
    }
    return true;
  }

  // --- helpers ---

  static DateTime? _parseTime(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    return DateTime.tryParse(iso)?.toLocal();
  }

  /// Strip tags/entities for a one-line list preview.
  static String _htmlToPreview(String html) {
    var text = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
