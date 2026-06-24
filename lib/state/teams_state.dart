import '../data/models/teams_conversation.dart';
import '../data/models/teams_message.dart';
import '../data/models/teams_self.dart';
import '../data/services/auth_service.dart';

enum TeamsStatus {
  /// Booting / restoring a saved session.
  connecting,

  /// Waiting for the user to enter the device code in a browser.
  awaitingDeviceCode,

  /// Fully signed in and connected.
  connected,

  /// A terminal error occurred (see [error]).
  error,
}

/// Immutable app state exposed to the UI.
class TeamsState {
  final TeamsStatus status;
  final DeviceCodeInfo? deviceCode;
  final TeamsSelf? self;
  final List<TeamsConversation> conversations;

  /// Messages keyed by conversation id (oldest-first).
  final Map<String, List<TeamsMessage>> messagesByConv;

  /// Conversation ids whose history is currently loading.
  final Set<String> loadingHistory;

  final String? error;

  const TeamsState({
    this.status = TeamsStatus.connecting,
    this.deviceCode,
    this.self,
    this.conversations = const [],
    this.messagesByConv = const {},
    this.loadingHistory = const {},
    this.error,
  });

  TeamsState copyWith({
    TeamsStatus? status,
    DeviceCodeInfo? deviceCode,
    bool clearDeviceCode = false,
    TeamsSelf? self,
    List<TeamsConversation>? conversations,
    Map<String, List<TeamsMessage>>? messagesByConv,
    Set<String>? loadingHistory,
    String? error,
    bool clearError = false,
  }) {
    return TeamsState(
      status: status ?? this.status,
      deviceCode: clearDeviceCode ? null : (deviceCode ?? this.deviceCode),
      self: self ?? this.self,
      conversations: conversations ?? this.conversations,
      messagesByConv: messagesByConv ?? this.messagesByConv,
      loadingHistory: loadingHistory ?? this.loadingHistory,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
