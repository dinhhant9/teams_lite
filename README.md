# Teams Lite

A from-scratch Flutter client for **Microsoft Teams personal accounts**, porting
the login + messaging logic of the [purple-teams](https://github.com/EionRobb/purple-teams)
Pidgin plugin (the `ENABLE_TEAMS_PERSONAL` build) directly to Dart. No Pidgin,
no Electron, no WebView for the chat itself.

## Features (v1 — text MVP)

- **Device-code sign in** (OAuth2, the same flow the plugin uses) with the
  refresh token persisted in secure storage for silent re-login.
- **Conversation list** + **chat view** with a responsive layout:
  - Desktop (macOS/Windows): sidebar list on the left, selected chat on the
    right, a Welcome pane when nothing is selected.
  - Mobile (iOS/Android): list screen → push chat screen.
- **Realtime messaging** over Trouter (socket.io-v1 WebSocket), plus history
  pagination and message send.

Deferred (not in v1): images, files, adaptive cards, reactions, presence,
typing indicators, calls.

## Architecture

The Dart layer mirrors the plugin's C modules:

| Dart | Ports from | Responsibility |
|------|-----------|----------------|
| `core/teams_constants.dart` | `libteams.h` | Personal hosts, client id, scopes, headers |
| `core/teams_util.dart` | `teams_util.c` | url→name helpers, js time |
| `data/services/auth_service.dart` | `teams_login.c` | Device code, token refresh, skype-token exchange |
| `data/services/teams_http_client.dart` | `teams_connection.c` | Per-request personal headers |
| `data/services/message_service.dart` | `teams_messages.c` | Conversation list, history, send, parse |
| `data/services/trouter_service.dart` | `teams_trouter.c` | WebSocket framing, registration, heartbeat |
| `data/services/session_store.dart` | refresh-token persistence + endpoint uuid |
| `state/teams_controller.dart` | `libteams.c` (`teams_do_all_the_things`) | Connection orchestration (Riverpod) |

## Auth flow (personal)

1. `POST login.microsoftonline.com/common/oauth2/devicecode` → show `user_code`.
2. Poll `/common/oauth2/token` until authorised → `access_token` + `refresh_token`.
3. Refresh service scopes at `/consumers/oauth2/v2.0/token`; exchange the
   `MBI_SSL` access token at `teams.live.com/api/auth/v1.0/authz/consumer` for a
   skype token.
4. Fetch self details, conversations; open the Trouter WebSocket.

Only the **refresh token** is persisted (secure storage), exactly like the
plugin storing it as the account password.

## Caveats

- **Personal accounts only.** Requires a consumer Microsoft account
  (outlook.com / hotmail / a personal MSA). Work/school accounts use different
  endpoints and are out of scope.
- **No web target.** Microsoft's consumer endpoints don't send CORS headers, so
  Flutter Web would be blocked. Build for desktop/mobile.
- **macOS sandbox:** `network.client` entitlement is enabled. If
  `flutter_secure_storage` fails to access the keychain, enable the Keychain
  Sharing capability in Xcode.
- Message content is currently rendered as plain text (HTML tags stripped).
</content>
