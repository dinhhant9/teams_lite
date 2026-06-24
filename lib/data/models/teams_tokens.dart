/// Token bundle held in memory during a session.
///
/// Only [refreshToken] is persisted across restarts (see `SessionStore`);
/// everything else is regenerated on launch — exactly like the plugin, which
/// stores the refresh token as the account "password" and nothing else.
class TeamsTokens {
  /// MSA access token (`sa->id_token`) — `Authorization: Bearer` for the
  /// `teams.live.com` origin and trouter authentication.
  String? idToken;

  /// Long-lived refresh token (`sa->refresh_token`) — the only persisted secret.
  String? refreshToken;

  /// Skype token (`sa->skype_token`) — `Authentication: skypetoken=…` header.
  String? skypeToken;

  /// Substrate/Office access token (`sa->substrate_access_token`).
  String? substrateToken;

  /// Server region returned alongside the skype token.
  String? region;

  TeamsTokens({
    this.idToken,
    this.refreshToken,
    this.skypeToken,
    this.substrateToken,
    this.region,
  });

  bool get hasSkypeToken => skypeToken != null && skypeToken!.isNotEmpty;
}
