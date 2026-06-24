import 'package:dio/dio.dart';

import '../../core/teams_constants.dart';
import '../models/teams_tokens.dart';

/// Thin wrapper over Dio that reproduces the per-request headers the plugin
/// sets in `teams_post_or_get` for the **personal** chat-service host
/// (`teams.live.com` + `/api/chatsvc/consumer/...`).
///
/// Microsoft rejects requests with the wrong client identity, so the header set
/// here is a faithful copy of the `ENABLE_TEAMS_PERSONAL` branch.
class TeamsHttpClient {
  final Dio _dio;
  final TeamsTokens _tokens;

  TeamsHttpClient(this._tokens, [Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 120),
              validateStatus: (s) => s != null && s < 500,
            ));

  /// Build the request URI from an already-encoded path+query string.
  ///
  /// IMPORTANT: do NOT use `Uri.https(host, path)` here — that treats the whole
  /// string as an unencoded path, which (a) percent-encodes the `?` into the
  /// path (breaking the query) and (b) double-encodes the conversation id
  /// (`%3A` → `%253A`), so the server can't find the conversation. Callers
  /// pre-encode the id with `Uri.encodeComponent` (matching the plugin's
  /// `purple_url_encode`), so we parse the full URL verbatim instead.
  Uri _url(String path) =>
      Uri.parse('https://${TeamsConstants.contactsHost}$path');

  Map<String, String> _chatHeaders() => {
        'BehaviorOverride': 'redirectAs404',
        'X-MS-Client-Consumer-Type': 'teams4life',
        'User-Agent': TeamsConstants.userAgent,
        // Personal auth: skype token in the `Authentication` header.
        'Authentication': 'skypetoken=${_tokens.skypeToken ?? ''}',
        'ms-ic3-product': 'tfl',
        'ms-ic3-additional-product': 'Sfl',
        'X-Stratus-Caller': TeamsConstants.clientInfoName,
        'X-Stratus-Request': 'abcd1234',
        'Origin': 'https://${TeamsConstants.baseOriginHost}',
        'Referer': 'https://${TeamsConstants.baseOriginHost}/',
        'Accept': 'application/json; ver=1.0;',
        'Accept-Language': 'en-US,en;q=0.9',
      };

  Future<Response<dynamic>> get(String path) {
    return _dio.getUri(
      _url(path),
      options: Options(headers: _chatHeaders()),
    );
  }

  Future<Response<dynamic>> post(String path, {Object? body}) {
    final headers = _chatHeaders();
    // The plugin sends JSON bodies as application/json.
    headers['Content-Type'] = 'application/json';
    return _dio.postUri(
      _url(path),
      data: body,
      options: Options(headers: headers, contentType: 'application/json'),
    );
  }

  Future<Response<dynamic>> put(String path, {Object? body}) {
    final headers = _chatHeaders();
    headers['Content-Type'] = 'application/json';
    return _dio.putUri(
      _url(path),
      data: body,
      options: Options(headers: headers, contentType: 'application/json'),
    );
  }
}
