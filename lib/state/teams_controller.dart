import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/teams_constants.dart';
import '../data/models/teams_message.dart';
import '../data/models/teams_self.dart';
import '../data/models/teams_tokens.dart';
import '../data/services/auth_service.dart';
import '../data/services/message_service.dart';
import '../data/services/session_store.dart';
import '../data/services/teams_http_client.dart';
import '../data/services/trouter_service.dart';
import 'providers.dart';
import 'teams_state.dart';

/// Top-level connection orchestrator — the Dart counterpart of
/// `teams_do_connect` + `teams_do_all_the_things`.
class TeamsController extends Notifier<TeamsState> {
  late final SessionStore _store;
  late final TeamsTokens _tokens;
  late final AuthService _auth;
  late final TeamsHttpClient _http;
  late final MessageService _messages;

  TrouterService? _trouter;
  String? _endpoint;
  Timer? _devicePoll;
  bool _connectStarted = false;

  @override
  TeamsState build() {
    _store = ref.read(sessionStoreProvider);
    _tokens = TeamsTokens();
    _auth = AuthService(store: _store, tokens: _tokens);
    _http = TeamsHttpClient(_tokens);
    _messages = MessageService(_http);
    _auth.onSkypeTokenReady = _onSkypeTokenReady;

    ref.onDispose(() {
      _devicePoll?.cancel();
      _trouter?.dispose();
      _auth.dispose();
    });

    _bootstrap();
    return const TeamsState();
  }

  // --- bootstrap ---

  Future<void> _bootstrap() async {
    _endpoint = await _store.readOrCreateEndpoint();
    final saved = await _store.readRefreshToken();
    if (saved != null && saved.isNotEmpty) {
      // Restore an existing session.
      _tokens.refreshToken = saved;
      try {
        await _auth.refreshAll(); // → _onSkypeTokenReady on success
      } on AuthException catch (e) {
        if (e.invalidGrant) {
          await _startDeviceCodeLogin();
        } else {
          _fail(e.message);
        }
      } catch (e) {
        _fail('$e');
      }
    } else {
      await _startDeviceCodeLogin();
    }
  }

  // --- device code login ---

  Future<void> _startDeviceCodeLogin() async {
    try {
      final info = await _auth.requestDeviceCode();
      state = state.copyWith(
        status: TeamsStatus.awaitingDeviceCode,
        deviceCode: info,
        clearError: true,
      );
      _beginPolling(info);
    } on AuthException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('$e');
    }
  }

  void _beginPolling(DeviceCodeInfo info) {
    _devicePoll?.cancel();
    final interval = Duration(seconds: info.interval.clamp(1, 60));
    _devicePoll = Timer.periodic(interval, (_) async {
      try {
        final done = await _auth.pollOnce(info.deviceCode);
        if (done) {
          _devicePoll?.cancel();
          _devicePoll = null;
          // _onSkypeTokenReady drives the rest once services finish.
          state = state.copyWith(
            status: TeamsStatus.connecting,
            clearDeviceCode: true,
          );
        }
      } on AuthException catch (e) {
        _devicePoll?.cancel();
        _devicePoll = null;
        _fail(e.message);
      } catch (_) {
        // transient network error — keep polling
      }
    });
  }

  /// Restart the login flow (e.g. after the code expired).
  Future<void> retryLogin() async {
    _devicePoll?.cancel();
    state = state.copyWith(status: TeamsStatus.connecting, clearError: true);
    await _startDeviceCodeLogin();
  }

  // --- connected: teams_do_all_the_things ---

  void _onSkypeTokenReady() {
    if (_connectStarted) {
      // A later token refresh — nothing else to do, trouter keeps running.
      return;
    }
    _connectStarted = true;
    _afterAuth();
  }

  Future<void> _afterAuth() async {
    try {
      final self = await _fetchSelfDetails();
      _messages.self = self;

      // Start realtime channel.
      _trouter = TrouterService(tokens: _tokens, endpoint: _endpoint!);
      _trouter!.onMessagingEvent = _onMessagingEvent;
      _trouter!.begin();

      // Load the conversation list.
      final convs = await _messages.getAllConversations(since: 0);

      state = state.copyWith(
        status: TeamsStatus.connected,
        self: self,
        conversations: convs,
        clearError: true,
        clearDeviceCode: true,
      );
    } catch (e) {
      _fail('$e');
    }
  }

  /// teams_get_self_details + teams_got_self_details.
  Future<TeamsSelf> _fetchSelfDetails() async {
    final res = await _http
        .get('${TeamsConstants.contactsPathPrefix}/v1/users/ME/properties');
    final data = res.data;
    final obj = data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};

    final username = obj['skypeName']?.toString() ?? '';
    String displayName = username;
    final userDetailsRaw = obj['userDetails'];
    if (userDetailsRaw is String && userDetailsRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(userDetailsRaw);
        final ud =
            decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
        final name = ud['name']?.toString();
        final upn = ud['upn']?.toString();
        if (name != null && name.isNotEmpty && name != username) {
          displayName = name;
        } else if (upn != null && upn.isNotEmpty) {
          displayName = upn;
        }
      } catch (_) {}
    }

    return TeamsSelf(
      username: username,
      displayName: displayName,
      primaryMemberName: obj['primaryMemberName']?.toString(),
    );
  }

  // --- realtime events ---

  void _onMessagingEvent(Map<String, dynamic> eventMessage) {
    if (eventMessage['type'] != 'EventMessage') return;

    final time = eventMessage['time']?.toString();
    if (!_messages.registerEventTime(time)) return; // duplicate

    final resourceType = eventMessage['resourceType']?.toString();
    if (resourceType != 'NewMessage' && resourceType != 'MessageUpdate') {
      return; // MVP: only new/edited messages
    }

    final resource = eventMessage['resource'];
    if (resource is! Map) return;

    final msg = _messages.parseMessageResource(
      resource.cast<String, dynamic>(),
      dedupeSent: true,
    );
    if (msg == null) return;

    _appendMessage(msg);
  }

  // --- history + send (UI-driven) ---

  Future<void> loadHistory(String conversationId) async {
    if (state.loadingHistory.contains(conversationId)) return;
    if (state.messagesByConv.containsKey(conversationId)) return; // cached

    state = state.copyWith(
      loadingHistory: {...state.loadingHistory, conversationId},
    );

    try {
      final history =
          await _messages.getConversationHistory(conversationId, since: 0);
      final updated =
          Map<String, List<TeamsMessage>>.from(state.messagesByConv);
      // Merge with any realtime messages that arrived before history loaded.
      final pending = updated[conversationId] ?? const [];
      final merged = _mergeMessages(history, pending);
      updated[conversationId] = merged;

      state = state.copyWith(
        messagesByConv: updated,
        loadingHistory: {...state.loadingHistory}..remove(conversationId),
      );
    } catch (_) {
      state = state.copyWith(
        loadingHistory: {...state.loadingHistory}..remove(conversationId),
      );
    }
  }

  Future<void> sendMessage(String conversationId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final html = _escapeToHtml(trimmed);

    // Optimistic local echo.
    final clientId = await _messages.sendMessage(conversationId, html);
    final echo = TeamsMessage(
      id: null,
      conversationId: conversationId,
      from: state.self?.username,
      displayName: state.self?.displayName,
      content: html,
      composeTime: DateTime.now(),
      isFromSelf: true,
      clientMessageId: clientId,
    );
    _appendMessage(echo);
  }

  // --- reload everything ---

  /// Re-fetch self details + the conversation list, and reload the history of
  /// every conversation that was already opened. The realtime trouter socket
  /// keeps running (it self-reconnects), so this is a pure data refresh.
  Future<void> reload() async {
    if (!_connectStarted) return; // not connected yet
    try {
      final self = await _fetchSelfDetails();
      _messages.self = self;

      final convs = await _messages.getAllConversations(since: 0);

      // Refresh history for conversations the user had already opened so the
      // currently-visible chat updates too.
      final previouslyLoaded = state.messagesByConv.keys.toList();
      final refreshed = <String, List<TeamsMessage>>{};
      for (final id in previouslyLoaded) {
        refreshed[id] =
            await _messages.getConversationHistory(id, since: 0);
      }

      state = state.copyWith(
        self: self,
        conversations: convs,
        messagesByConv: refreshed,
        loadingHistory: {},
        clearError: true,
      );
    } catch (e) {
      _fail('$e');
    }
  }

  // --- logout ---

  Future<void> logout() async {
    _devicePoll?.cancel();
    _trouter?.stop();
    _auth.dispose();
    await _store.clearRefreshToken();
    _tokens
      ..idToken = null
      ..skypeToken = null
      ..refreshToken = null
      ..substrateToken = null;
    _connectStarted = false;
    state = const TeamsState(status: TeamsStatus.connecting);
    await _startDeviceCodeLogin();
  }

  // --- internal helpers ---

  void _appendMessage(TeamsMessage msg) {
    final convId = msg.conversationId;
    final updated =
        Map<String, List<TeamsMessage>>.from(state.messagesByConv);
    final existing = updated[convId] ?? const [];
    if (existing.any((m) => m.dedupeKey == msg.dedupeKey)) return;
    updated[convId] = [...existing, msg]
      ..sort((a, b) => a.composeTime.compareTo(b.composeTime));

    // Bump the conversation preview/order.
    final convs = [...state.conversations];
    final idx = convs.indexWhere((c) => c.id == convId);
    if (idx != -1) {
      final c = convs[idx];
      c.lastMessagePreview = _previewFromHtml(msg.content);
      c.lastMessageTime = msg.composeTime;
      convs.removeAt(idx);
      convs.insert(0, c);
    }

    state = state.copyWith(messagesByConv: updated, conversations: convs);
  }

  static List<TeamsMessage> _mergeMessages(
    List<TeamsMessage> a,
    List<TeamsMessage> b,
  ) {
    final seen = <String>{};
    final out = <TeamsMessage>[];
    for (final m in [...a, ...b]) {
      if (seen.add(m.dedupeKey)) out.add(m);
    }
    out.sort((x, y) => x.composeTime.compareTo(y.composeTime));
    return out;
  }

  void _fail(String message) {
    state = state.copyWith(status: TeamsStatus.error, error: message);
  }

  static String _escapeToHtml(String text) {
    final escaped = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('\n', '<br>');
    return escaped;
  }

  static String _previewFromHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
