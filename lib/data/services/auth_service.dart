import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/teams_constants.dart';
import '../models/teams_tokens.dart';
import 'session_store.dart';

/// Info returned by the device-code request, shown to the user so they can
/// authenticate in a browser (`teams_devicecode_login_cb`).
class DeviceCodeInfo {
  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final String message;
  final int interval; // seconds between polls
  final int expiresIn; // seconds until the code expires

  const DeviceCodeInfo({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.message,
    required this.interval,
    required this.expiresIn,
  });
}

/// Raised for terminal auth failures (bad/expired grant, etc.).
class AuthException implements Exception {
  final String message;
  final bool invalidGrant;
  const AuthException(this.message, {this.invalidGrant = false});
  @override
  String toString() => 'AuthException: $message';
}

/// Ports the OAuth2 logic of `teams_login.c` for **personal** Teams accounts.
///
/// Flow:
///  1. [requestDeviceCode] → show code to user.
///  2. [pollOnce] repeatedly until it returns true (authorised) — this stores
///     the refresh token and obtains the first id token.
///  3. [refreshAll] mints the id token, skype token and substrate token from
///     the refresh token, and schedules itself to run again before expiry.
///
/// On a subsequent launch with a saved refresh token, call [refreshAll]
/// directly (step 1–2 are skipped).
class AuthService {
  final Dio _dio;
  final SessionStore _store;
  final TeamsTokens tokens;

  /// Invoked once a fresh skype token is available — the cue to run
  /// `teams_do_all_the_things` (see the skype-token callback in the plugin).
  void Function()? onSkypeTokenReady;

  Timer? _refreshTimer;

  AuthService({
    required SessionStore store,
    Dio? dio,
    TeamsTokens? tokens,
  })  : _store = store,
        tokens = tokens ?? TeamsTokens(),
        _dio = dio ??
            Dio(BaseOptions(
              // OAuth endpoints answer with non-2xx + a JSON error body we want
              // to inspect (e.g. authorization_pending), so accept everything.
              validateStatus: (_) => true,
              headers: {'User-Agent': TeamsConstants.userAgent},
            ));

  // Shared headers mirroring the plugin's device-code requests.
  Map<String, String> get _formHeaders => {
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': TeamsConstants.userAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
      };

  /// Step 1 — `teams_do_devicecode_login`.
  Future<DeviceCodeInfo> requestDeviceCode() async {
    final res = await _dio.post(
      TeamsConstants.deviceCodeUrl,
      data: {
        'client_id': TeamsConstants.personalOauthClientId,
        'resource': TeamsConstants.oauthResource,
      },
      options: Options(
        headers: _formHeaders,
        contentType: Headers.formUrlEncodedContentType,
      ),
    );

    final body = _asMap(res.data);
    if (res.statusCode != 200 || body['device_code'] == null) {
      throw AuthException(
          body['error_description']?.toString() ?? 'Device code request failed');
    }

    return DeviceCodeInfo(
      deviceCode: body['device_code'].toString(),
      userCode: body['user_code']?.toString() ?? '',
      verificationUrl:
          (body['verification_url'] ?? body['verification_uri'] ?? '')
              .toString(),
      message: body['message']?.toString() ??
          'To sign in, open ${body['verification_url']} and enter '
              '${body['user_code']}.',
      interval: _asInt(body['interval'], 5),
      expiresIn: _asInt(body['expires_in'], 900),
    );
  }

  /// Step 2 — one poll of `teams_devicecode_login_poll`.
  ///
  /// Returns `true` when authorisation completed (tokens stored + services
  /// refresh kicked off), `false` while still `authorization_pending`.
  /// Throws [AuthException] on a terminal error.
  Future<bool> pollOnce(String deviceCode) async {
    final res = await _dio.post(
      TeamsConstants.deviceTokenUrl,
      data: {
        'client_id': TeamsConstants.personalOauthClientId,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        'code': deviceCode,
      },
      options: Options(
        headers: _formHeaders,
        contentType: Headers.formUrlEncodedContentType,
      ),
    );

    final body = _asMap(res.data);
    if (res.statusCode == 200 && body['access_token'] != null) {
      tokens.idToken = body['access_token'].toString();
      final refresh = body['refresh_token']?.toString();
      if (refresh != null) {
        tokens.refreshToken = refresh;
        await _store.writeRefreshToken(refresh);
      }
      // Kick off the service tokens (skype + substrate).
      await _refreshServices();
      return true;
    }

    final error = body['error']?.toString();
    // Still waiting for the user — keep polling.
    if (error == 'authorization_pending' || error == 'slow_down') return false;
    if (error == 'invalid_grant' || error == 'interaction_required') {
      await _store.clearRefreshToken();
      throw AuthException(body['error_description']?.toString() ?? error!,
          invalidGrant: true);
    }
    throw AuthException(body['error_description']?.toString() ??
        error ??
        'Device code poll failed');
  }

  /// `teams_oauth_refresh_token` — refresh the main id token *and* the service
  /// tokens, then reschedule. Use this on launch when a refresh token exists,
  /// and whenever the skype token nears expiry.
  Future<void> refreshAll() async {
    final refresh = tokens.refreshToken ?? await _store.readRefreshToken();
    if (refresh == null || refresh.isEmpty) {
      throw const AuthException('No refresh token', invalidGrant: true);
    }
    tokens.refreshToken = refresh;

    // Main scope → id token (and possibly a rolled refresh token).
    await _refreshMainToken();
    // Service scopes → skype token + substrate token.
    await _refreshServices();
  }

  /// `teams_oauth_with_code_cb` path: refresh the primary id token.
  Future<void> _refreshMainToken() async {
    final body = await _refreshForScope(TeamsConstants.oauthScope);
    final idToken = body['access_token']?.toString();
    if (idToken != null) tokens.idToken = idToken;

    final newRefresh = body['refresh_token']?.toString();
    if (newRefresh != null && newRefresh.isNotEmpty) {
      tokens.refreshToken = newRefresh;
      await _store.writeRefreshToken(newRefresh);
    }

    final error = body['error']?.toString();
    if (error == 'invalid_grant' || error == 'interaction_required') {
      await _store.clearRefreshToken();
      throw AuthException(body['error_description']?.toString() ?? error!,
          invalidGrant: true);
    }
  }

  /// `teams_oauth_refresh_services` (personal): skype token + substrate token.
  Future<void> _refreshServices() async {
    // Substrate token (best-effort; not fatal if it fails).
    try {
      final sub = await _refreshForScope(TeamsConstants.substrateScope);
      final t = sub['access_token']?.toString();
      if (t != null) tokens.substrateToken = t;
    } catch (_) {/* non-fatal */}

    // Skype token: refresh for the MBI_SSL scope, then exchange the resulting
    // access token at the authz/consumer endpoint.
    final skype = await _refreshForScope(TeamsConstants.skypeTokenScope);
    final accessToken = skype['access_token']?.toString();
    if (accessToken == null) {
      throw const AuthException('Could not obtain skype-token access token');
    }
    await _exchangeSkypeToken(accessToken);
  }

  /// POST to the consumers token endpoint for [scope] with the refresh token.
  Future<Map<String, dynamic>> _refreshForScope(String scope) async {
    final res = await _dio.post(
      TeamsConstants.consumerTokenUrl,
      data: {
        'scope': scope,
        'client_id': TeamsConstants.personalOauthClientId,
        'grant_type': 'refresh_token',
        'refresh_token': tokens.refreshToken,
      },
      options: Options(
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    return _asMap(res.data);
  }

  /// `teams_login_get_api_skypetoken` — exchange an MSA access token for a
  /// skype token at `teams.live.com/api/auth/v1.0/authz/consumer`.
  Future<void> _exchangeSkypeToken(String accessToken) async {
    final res = await _dio.post(
      TeamsConstants.skypeTokenAuthzUrl,
      options: Options(
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json; ver=1.0',
        },
      ),
    );

    final obj = _asMap(res.data);
    Map<String, dynamic>? tokensObj;
    String? skypeToken;
    if (obj['tokens'] is Map) {
      tokensObj = _asMap(obj['tokens']);
      skypeToken = tokensObj['skypeToken']?.toString();
    } else if (obj['skypeToken'] is Map) {
      tokensObj = _asMap(obj['skypeToken']);
      skypeToken = tokensObj['skypetoken']?.toString();
    }

    if (skypeToken == null) {
      final status = obj['status'];
      final detail = status is Map
          ? status['text']
          : (obj['message'] ?? obj['error_description'] ?? 'unknown error');
      throw AuthException('Failed getting Skype Token: $detail');
    }

    tokens.skypeToken = skypeToken;
    tokens.region = obj['region']?.toString();

    // Schedule the next refresh a few seconds before expiry.
    final expiresIn = _asInt(tokensObj?['expiresIn'], 3600);
    _scheduleRefresh(expiresIn - 5);

    onSkypeTokenReady?.call();
  }

  void _scheduleRefresh(int seconds) {
    _refreshTimer?.cancel();
    final delay = Duration(seconds: seconds.clamp(30, 86400));
    _refreshTimer = Timer(delay, () {
      // Best-effort; the connection layer surfaces hard failures.
      refreshAll().catchError((_) {});
    });
  }

  void dispose() => _refreshTimer?.cancel();

  // --- small coercion helpers (the OAuth APIs are loosely typed) ---
  static Map<String, dynamic> _asMap(dynamic v) =>
      v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

  static int _asInt(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }
}
