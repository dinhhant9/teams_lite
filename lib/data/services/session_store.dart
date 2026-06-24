import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Persists the two pieces of state the plugin keeps across restarts:
///
///  * the **refresh token** (stored by the plugin as the account "password"),
///  * the **endpoint UUID** (`sa->endpoint`, persisted once to avoid the
///    "Endpoint limit exceeded" error — see `teams_do_all_the_things`).
///
/// Short-lived tokens (id/skype/substrate) are intentionally NOT persisted;
/// they are regenerated on launch from the refresh token.
///
/// Note: shared_preferences stores values in plaintext (not the OS keychain).
/// That's acceptable here and avoids the macOS keychain entitlement/signing
/// issues; treat the refresh token as sensitive on shared machines.
class SessionStore {
  static const _kRefreshToken = 'teams_refresh_token';
  static const _kEndpoint = 'teams_endpoint_id';

  /// Optional injected instance (used by tests via
  /// `SharedPreferences.setMockInitialValues`).
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _store async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<String?> readRefreshToken() async {
    final prefs = await _store;
    return prefs.getString(_kRefreshToken);
  }

  Future<void> writeRefreshToken(String? token) async {
    final prefs = await _store;
    if (token == null) {
      await prefs.remove(_kRefreshToken);
    } else {
      await prefs.setString(_kRefreshToken, token);
    }
  }

  Future<void> clearRefreshToken() async {
    final prefs = await _store;
    await prefs.remove(_kRefreshToken);
  }

  /// Returns the persistent endpoint id, generating + storing one on first use.
  Future<String> readOrCreateEndpoint() async {
    final prefs = await _store;
    final existing = prefs.getString(_kEndpoint);
    if (existing != null && existing.isNotEmpty) return existing;
    final fresh = const Uuid().v4();
    await prefs.setString(_kEndpoint, fresh);
    return fresh;
  }
}
