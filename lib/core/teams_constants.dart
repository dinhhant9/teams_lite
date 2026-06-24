/// Constants ported from the purple-teams plugin (`libteams.h`, `teams_login.c`).
///
/// This app targets **Teams personal accounts only**, i.e. the plugin compiled
/// with `ENABLE_TEAMS_PERSONAL` defined. Every value below is the personal
/// branch of the corresponding `#ifdef ENABLE_TEAMS_PERSONAL`.
library;

class TeamsConstants {
  TeamsConstants._();

  // --- Hosts (libteams.h, personal branch) ---
  static const String baseOriginHost = 'teams.live.com';
  static const String contactsHost = 'teams.live.com';
  static const String contactsPathPrefix = '/api/chatsvc/consumer';
  static const String profilesPrefix = '/api/mt/beta/';

  // --- OAuth (teams_login.c) ---
  static const String personalOauthClientId =
      '8ec6bc83-69c8-4392-8f08-b3c986009232';
  static const String personalTenantId =
      '9188040d-6c67-4c5b-b112-36a304b66dad';
  static const String oauthResource = 'https://api.spaces.skype.com';

  /// `TEAMS_OAUTH_SERVICE` (personal).
  static const String oauthService =
      'https://mtsvc.fl.teams.microsoft.com/teams.mt.readwrite';

  /// `TEAMS_OAUTH_SCOPE` = service + " openid profile offline_access".
  static const String oauthScope =
      '$oauthService openid profile offline_access';

  /// Scope used to mint the skype token (personal).
  static const String skypeTokenScope =
      'service::api.fl.spaces.skype.com::MBI_SSL openid profile offline_access';

  /// Substrate (Office) scope (personal).
  static const String substrateScope =
      'https://substrate.office.com/M365.Access openid profile offline_access';

  /// Endpoint that exchanges an MSA access token for a skype token (personal).
  static const String skypeTokenAuthzUrl =
      'https://teams.live.com/api/auth/v1.0/authz/consumer';

  // Device-code flow uses the v1 `common` tenant endpoints.
  static const String deviceCodeUrl =
      'https://login.microsoftonline.com/common/oauth2/devicecode';
  static const String deviceTokenUrl =
      'https://login.microsoftonline.com/common/oauth2/token';

  /// Token refresh endpoint (personal → `consumers`).
  static const String consumerTokenUrl =
      'https://login.microsoftonline.com/consumers/oauth2/v2.0/token';

  // --- Client info (libteams.h, personal branch) ---
  static const String clientInfoName = 'skypeteams';
  static const String clientInfoVersion = '1415/26010401241';
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0 '
      'Teams/24165.1410.2974.6689/49';

  // --- Trouter (teams_trouter.c) ---
  static const String trouterTccv = '2024.23.01.2';
  static const int trouterTtl = 86400;
  static const String trouterBeginHost = 'go.trouter.teams.microsoft.com';
  static const String trouterFallbackSocketIo =
      'https://go.trouter.skype.com/';
  static const String registrarUrl =
      'https://edge.skype.com/registrar/prod/v2/registrations';

  // --- Misc behaviour ---
  static const int maxProcessedEventBuffer = 10;
}
