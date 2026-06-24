import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';

import '../../core/teams_constants.dart';
import '../models/teams_tokens.dart';

/// Realtime notification channel, ported from `teams_trouter.c`.
///
/// Trouter is socket.io v1 carried over a WebSocket. The framing the plugin
/// reverse-engineered:
///   * `1::`            → connection established (send auth, go active, register)
///   * `3:::<json>`     → server notification; must be ACKed with another `3:::`
///   * `5:N+::<json>`   → sequenced message (we send pings/activity this way)
///   * `5:::<json>`     → ephemeral message (auth handshake)
///   * `6:...`          → response to one of our messages (ignored)
///
/// This MVP routes `/messaging` notifications (EventMessages) to
/// [onMessagingEvent]; presence/call notifications are ACKed but otherwise
/// ignored.
class TrouterService {
  final TeamsTokens _tokens;
  final String endpoint;
  final Dio _dio;

  /// Called with the decoded EventMessage body for `/messaging` notifications.
  void Function(Map<String, dynamic> eventMessage)? onMessagingEvent;

  IOWebSocketChannel? _channel;
  StreamSubscription? _socketSub;
  Timer? _pingTimer;
  Timer? _registrationTimer;
  Timer? _reconnectTimer;

  String? _surl;
  Map<String, dynamic>? _socketObj;
  int _commandCount = 1;
  bool _stopped = false;

  static const _uuid = Uuid();

  TrouterService({
    required TeamsTokens tokens,
    required this.endpoint,
    Dio? dio,
  })  : _tokens = tokens,
        _dio = dio ??
            Dio(BaseOptions(validateStatus: (s) => s != null && s < 500));

  // --- lifecycle ---

  /// `teams_trouter_begin` — bootstrap the connection.
  Future<void> begin() async {
    _stopped = false;
    stop(keepStopped: false);

    try {
      final url =
          'https://${TeamsConstants.trouterBeginHost}/v4/a?epid=${Uri.encodeComponent(endpoint)}';
      final res = await _dio.post(
        url,
        options: Options(headers: {
          'x-skypetoken': _tokens.skypeToken ?? '',
          'Content-Length': '0',
          'User-Agent': TeamsConstants.userAgent,
        }),
      );
      final obj = _asMap(res.data);
      if (obj.isEmpty) {
        _scheduleReconnect();
        return;
      }
      await _getSessionId(obj);
    } catch (_) {
      _scheduleReconnect();
    }
  }

  /// `teams_trouter_stop`.
  void stop({bool keepStopped = true}) {
    if (keepStopped) _stopped = true;
    _pingTimer?.cancel();
    _registrationTimer?.cancel();
    _reconnectTimer?.cancel();
    _socketSub?.cancel();
    _socketSub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _surl = null;
    _socketObj = null;
  }

  void dispose() => stop();

  // --- bootstrap (teams_trouter_info_cb → teams_trouter_sessionid_cb) ---

  Future<void> _getSessionId(Map<String, dynamic> obj) async {
    _socketObj = obj;
    final socketio = obj['socketio']?.toString() ??
        'https://${TeamsConstants.trouterBeginHost}/';

    final infoUrl = StringBuffer('${socketio}socket.io/1/?v=v4&');
    _appendConnectParams(infoUrl, obj);

    final res = await _dio.get(
      infoUrl.toString(),
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'X-Skypetoken': _tokens.skypeToken ?? '',
          'User-Agent': TeamsConstants.userAgent,
        },
      ),
    );

    // Response is plaintext: "<sessionId>:<hb>:<close>:websocket,xhr-polling".
    final body = res.data?.toString() ?? '';
    final sessionId = body.split(':').first;
    if (sessionId.isEmpty) {
      _scheduleReconnect();
      return;
    }

    _surl = obj['surl']?.toString();
    _connectWebSocket(obj, socketio, sessionId);
  }

  void _connectWebSocket(
    Map<String, dynamic> obj,
    String socketio,
    String sessionId,
  ) {
    final wsUrl =
        StringBuffer('${socketio}socket.io/1/websocket/$sessionId?v=v4&');
    _appendConnectParams(wsUrl, obj);

    // https/http → wss/ws for the socket connect.
    var url = wsUrl.toString();
    if (url.startsWith('https://')) {
      url = url.replaceFirst('https://', 'wss://');
    } else if (url.startsWith('http://')) {
      url = url.replaceFirst('http://', 'ws://');
    }

    _commandCount = 1;
    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse(url),
        headers: {
          'X-Skypetoken': _tokens.skypeToken ?? '',
          'User-Agent': TeamsConstants.userAgent,
        },
      );
    } catch (_) {
      _scheduleReconnect();
      return;
    }

    _socketSub = _channel!.stream.listen(
      _onFrame,
      onDone: _onClosed,
      onError: (_) => _onClosed(),
      cancelOnError: true,
    );

    // 30s heartbeat (teams_trouter_send_ping).
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _sendSequenced('{"name":"ping"}');
    });

    // Re-register before the TTL elapses.
    _registrationTimer?.cancel();
    _registrationTimer = Timer.periodic(
      const Duration(seconds: TeamsConstants.trouterTtl - 10),
      (_) => _registerAll(),
    );
  }

  /// Build the `key=value&` connectparams + tc/con_num/epid/ccid suffix shared
  /// by the info and websocket URLs.
  void _appendConnectParams(StringBuffer url, Map<String, dynamic> obj) {
    final connectParams = obj['connectparams'];
    if (connectParams is Map) {
      connectParams.forEach((key, value) {
        url.write('$key=${Uri.encodeComponent(value.toString())}&');
      });
    }
    final tc =
        '{"cv":"${TeamsConstants.trouterTccv}","ua":"TeamsCDL","hr":"","v":"${TeamsConstants.clientInfoVersion}"}';
    url.write('tc=${Uri.encodeComponent(tc)}&');
    url.write('con_num=1234567890123_1&');
    url.write('epid=${Uri.encodeComponent(endpoint)}&');
    final ccid = obj['ccid']?.toString();
    if (ccid != null) url.write('ccid=${Uri.encodeComponent(ccid)}&');
    url.write('auth=true&timeout=40&');
  }

  void _onClosed() {
    _channel = null;
    if (!_stopped) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_stopped) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), begin);
  }

  // --- inbound framing (teams_trouter_websocket_cb) ---

  void _onFrame(dynamic frame) {
    final msg = frame is String ? frame : utf8.decode(frame as List<int>);
    if (msg.isEmpty) return;

    switch (msg[0]) {
      case '1':
        _sendAuthentication();
        _sendActive(true);
        _registerAll();
        break;
      case '3':
        _handleNotification(msg);
        break;
      case '5':
        _handleSequenced(msg);
        break;
      default:
        break; // '6' responses, etc.
    }
  }

  void _handleNotification(String msg) {
    final jsonStart = _indexAfterNthColon(msg, 3);
    if (jsonStart == -1) return;
    final request = _asMap(_tryJson(msg.substring(jsonStart)));
    if (request.isEmpty) return;

    // ACK the notification (`3:::{id,status:200,body:""}`).
    final ack = jsonEncode({
      'id': request['id'],
      'status': 200,
      'body': '',
    });
    _sendRaw('3:::$ack');

    final headers = _asMap(request['headers']);
    var body = request['body']?.toString() ?? '';
    if (headers['X-Microsoft-Skype-Content-Encoding'] == 'gzip') {
      body = _gunzipBase64(body) ?? body;
    }

    var bodyObj = _asMap(_tryJson(body));
    // Nested compressed payloads (cp = gzip+base64, gp = base64).
    if (bodyObj['cp'] is String) {
      final cp = _gunzipBase64(bodyObj['cp'] as String);
      if (cp != null) bodyObj = _asMap(_tryJson(cp));
    } else if (bodyObj['gp'] is String) {
      final gp = utf8.decode(base64.decode(bodyObj['gp'] as String));
      bodyObj = _asMap(_tryJson(gp));
    }

    final requestUrl = request['url']?.toString() ?? '';
    if (requestUrl.endsWith('/messaging')) {
      onMessagingEvent?.call(bodyObj);
    }
    // Presence/call notifications are ACKed above but ignored in this MVP.
  }

  void _handleSequenced(String msg) {
    final jsonStart = _indexAfterNthColon(msg, 3);
    if (jsonStart == -1) return;
    final obj = _asMap(_tryJson(msg.substring(jsonStart)));
    if (obj['name'] == 'trouter.message_loss') {
      // Re-register the messaging worker (plugin re-registers CDL).
      _registerOne('TeamsCDLWebWorker', 'TeamsCDLWebWorker_2.6', _surl ?? '',
          productContext: 'TFL');
    }
  }

  // --- outbound (auth, activity, ping) ---

  void _sendAuthentication() {
    final connectParams =
        _socketObj?['connectparams'] ?? <String, dynamic>{};
    final payload = jsonEncode({
      'name': 'user.authenticate',
      'args': [
        {
          'headers': {
            'X-Ms-Test-User': 'False',
            'Authorization': 'Bearer ${_tokens.idToken ?? ''}',
            'X-MS-Migration': 'True',
          },
          'connectparams': connectParams,
        }
      ],
    });
    _sendRaw('5:::$payload'); // ephemeral
  }

  void _sendActive(bool active) {
    final cv = _correlationVector();
    final payload =
        '{"name":"user.activity","args":[{"state":"${active ? 'active' : 'inactive'}","cv":"$cv.0.1"}]}';
    _sendSequenced(payload);
  }

  void _sendSequenced(String message) {
    _sendRaw('5:${_commandCount++}+::$message');
  }

  void _sendRaw(String data) {
    try {
      _channel?.sink.add(data);
    } catch (_) {}
  }

  // --- registration (teams_trouter_register / _register_one) ---

  void _registerAll() {
    final surl = _surl;
    if (surl == null) return;

    _registerOne('NextGenCalling', 'DesktopNgc_2.3:SkypeNgc',
        '${surl}NGCallManagerWin');
    _registerOne('SkypeSpacesWeb', 'SkypeSpacesWeb_2.3', '${surl}SkypeSpacesWeb');
    // Personal: two CDL workers — one TFL (regId = endpoint), one blank.
    _registerOne('TeamsCDLWebWorker', 'TeamsCDLWebWorker_2.6', surl,
        productContext: 'TFL');
    _registerOne('TeamsCDLWebWorker', 'TeamsCDLWebWorker_2.3', surl,
        productContext: '');
  }

  void _registerOne(
    String appId,
    String templateKey,
    String path, {
    String? productContext,
  }) {
    final clientDescription = <String, dynamic>{
      'appId': appId,
      'aesKey': '',
      'languageId': 'en-US',
      'platform': 'edge',
      'templateKey': templateKey,
      'platformUIVersion': TeamsConstants.clientInfoVersion,
    };
    if (productContext != null) {
      clientDescription['productContext'] = productContext;
    }

    // CDL/TFL worker registers under the persistent endpoint id; others random.
    final registrationId =
        (appId == 'TeamsCDLWebWorker' && productContext == 'TFL')
            ? endpoint
            : _uuid.v4();

    final regObj = {
      'clientDescription': clientDescription,
      'registrationId': registrationId,
      'nodeId': '',
      'transports': {
        'TROUTER': [
          {'context': '', 'path': path, 'ttl': TeamsConstants.trouterTtl}
        ]
      },
    };

    _dio
        .post(
          TeamsConstants.registrarUrl,
          data: regObj,
          options: Options(
            contentType: 'application/json',
            headers: {
              'Content-Type': 'application/json',
              'X-Skypetoken': _tokens.skypeToken ?? '',
              'Authorization': 'Bearer ${_tokens.idToken ?? ''}',
              'User-Agent': TeamsConstants.userAgent,
            },
          ),
        )
        .catchError((_) => Response(requestOptions: RequestOptions(path: '')));
  }

  // --- helpers ---

  /// teams_generate_correlation_vector: 21 base64-ish chars + a suffix char.
  String _correlationVector() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/+';
    const suffix = 'AgQw';
    final rnd = Random();
    final sb = StringBuffer();
    for (var i = 0; i < 21; i++) {
      sb.write(chars[rnd.nextInt(chars.length)]);
    }
    sb.write(suffix[rnd.nextInt(suffix.length)]);
    return sb.toString();
  }

  static int _indexAfterNthColon(String s, int n) {
    var remaining = n;
    for (var i = 1; i < s.length; i++) {
      if (s[i] == ':') {
        remaining--;
        if (remaining == 0) return i + 1;
      }
    }
    return -1;
  }

  static String? _gunzipBase64(String b64) {
    try {
      final bytes = base64.decode(b64);
      return utf8.decode(GZipCodec().decode(bytes));
    } catch (_) {
      return null;
    }
  }

  static dynamic _tryJson(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _asMap(dynamic v) =>
      v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
}
